@preconcurrency import CoreBluetooth
import Foundation
@preconcurrency import IOBluetooth

/// 協調耳機控制通道、設定命令、狀態回報與使用者偏好。
@Observable @MainActor
final class BluetoothManager: NSObject {
    // MARK: - 服務相依與連線邊界

    /// 自動嘗試的冷卻秒數，避免重複系統事件造成連線風暴。
    private let autoConnectCooldown: TimeInterval = 15
    private let maxConnectRetries = 2
    /// 每次連線嘗試的最長等待秒數。
    private let attemptTimeout: TimeInterval = 35
    /// 允許開始下一次重試的時間窗，單位為秒。
    private let connectBudget: TimeInterval = 45
    let firmware = FirmwareUpdater()

    /// 非同步寫入持有原生 buffer，各分段完成後由 ARC 釋放記憶體。
    private final class WriteBuffer {
        let pointer: UnsafeMutableRawPointer
        let count: Int
        let messageID: MessageID
        /// 複製編碼資料到連續原生記憶體，分段回呼完成前保持 buffer 有效。
        ///
        /// - Parameters:
        ///   - data: 完整的待傳送位元組，複製後持有至原生寫入回呼完成。
        ///   - messageID: 本次封包的命令識別，供傳輸完成與操作回饋對應。
        init(data: Data, messageID: MessageID) {
            count = data.count
            self.messageID = messageID
            pointer = .allocate(byteCount: count, alignment: MemoryLayout<UInt8>.alignment)
            data.copyBytes(to: pointer.assumingMemoryBound(to: UInt8.self), count: count)
        }
        deinit { pointer.deallocate() }
    }

    // MARK: - 可觀察狀態

    // 連線、探索、權限與操作回饋提供可觀察快照，主執行緒統一更新。
    private(set) var isConnected = false
    private(set) var isConnecting = false
    private(set) var isScanning = false
    private(set) var bluetoothReady = false
    var isWriting: Bool { !pendingWrites.isEmpty }
    private(set) var discoveredDevices: [DiscoveredDevice] = []
    private(set) var connectedModel: BudsModel?
    private(set) var connectedName: String?
    private(set) var status = BudsStatus()
    private(set) var selfTestRunning = false
    private(set) var spatialDataReceived = false
    private var selfTestTimeout: Task<Void, Never>?
    private var spatialKeepAlive: Task<Void, Never>?
    private var spatialPreviousEnabled: Bool?
    private(set) var connectionError: String?
    private(set) var commandNotice: CommandFeedback?
    private(set) var isDemo = false
    var previewDark = false
    var preferredAudioDeviceName: String?
    var onAutoConnected: (@MainActor () -> Void)?
    @ObservationIgnored var onSpatialQuaternion: (@MainActor ([Double]) -> Void)?

    // MARK: - 使用者偏好

    // 裝置偏好與快捷選擇從 UserDefaults 載入，示範模式另隔離寫入。
    private(set) var selectedQuickControls =
        UserDefaults.standard.stringArray(forKey: "quickControls")
        ?? [QuickControl.detectConversations.rawValue]
    private(set) var appearanceColorOverride: String?
    var productVariant: ProductVariant? {
        connectedModel?.profile.variant(reportedID: status.deviceColorID, overrideID: appearanceColorOverride)
    }
    private var appearanceKey: String {
        "appearance." + (connectedDevice?.addressString ?? connectedModel?.id ?? "unknown")
    }
    private var customEQKey: String { "customEQ." + (connectedDevice?.addressString ?? "unknown") }

    // MARK: - 通道與連線嘗試

    // 原生裝置與 RFCOMM 通道由服務持有，回呼需核對同一實體。
    private var connectedDevice: IOBluetoothDevice?
    private var rfcommChannel: IOBluetoothRFCOMMChannel?
    private var streamDecoder = SppStreamDecoder()
    private var centralManager: CBCentralManager?
    private var inquiry: IOBluetoothDeviceInquiry?
    private var pendingSDPDevice: IOBluetoothDevice?
    private var pendingSDPGeneration: Int?
    private var pendingScan = false
    private var connectNotification: IOBluetoothUserNotification?
    private var autoConnectArmed = false
    private var autoConnectShouldNotify = false
    private var suppressAutoConnect = false
    /// 單調時間避免系統日期調整延長或略過冷卻窗。
    private var lastAutoAttempt: ContinuousClock.Instant?
    private var lastPollSkipReason: String?
    private var attemptTimeoutTask: Task<Void, Never>?
    private var pendingSettingID: MessageID?
    private var failedSettingID: MessageID?
    private var pendingWrites: [UInt: WriteBuffer] = [:]
    private var connectRetryCount = 0
    private var connectDeadline = ContinuousClock.now
    /// 連線世代用於排除取消或重試前留下的非同步結果。
    private var connectGeneration = 0

    /// 裝置名稱與位址取自 macOS，model 包含使用者保存的型號對應。
    struct DiscoveredDevice: Identifiable, Sendable {
        let id: String
        let name: String
        let address: String
        let device: IOBluetoothDevice
        let model: BudsModel?

        /// 將系統裝置轉成可辨識的耳機快照，缺少位址或候選資格時回傳 nil。
        ///
        /// - Parameters:
        ///   - device: 本次連線或服務探索的系統裝置，回呼需核對其身分與世代。
        nonisolated init?(device: IOBluetoothDevice) {
            // 缺少裝置位址時無法建立穩定識別，拒絕加入裝置清單。
            guard let address = device.addressString, !address.isEmpty else { return nil }
            self.id = address.lowercased().filter { $0.isHexDigit }
            self.name = device.name ?? String(localized: "Unnamed Bluetooth device")
            self.address = address
            self.device = device
            let savedID = UserDefaults.standard.string(forKey: "model." + self.address)
            self.model = BudsModel.detect(from: self.name) ?? BudsModel.allCases.first { $0.id == savedID }
            // 已辨識耳機或系統音訊類別裝置才可成為連線候選。
            guard
                self.model != nil
                    || device.deviceClassMajor == BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio)
            else { return nil }
        }
    }

    // MARK: - 裝置與公開連線操作

    /// 啟動藍牙授權與已連線耳機的自動控制通道。
    func startAutoConnect() {
        autoConnectArmed = true
        primeBluetoothPermission()
        // 授權及電源已就緒才註冊原生連線通知，等待時由狀態事件接續。
        if bluetoothReady { armConnectNotifications() }
    }

    /// 移除系統連線通知，停止服務的自動連線入口。
    func stopAutoConnect() {
        autoConnectArmed = false
        connectNotification?.unregister()
        connectNotification = nil
    }

    /// 讀取 Mac 配對清單，權限尚未就緒時先啟動授權。
    func refreshPairedDevices() {
        // 首次操作先觸發原生授權，權限完成後再讀取配對清單。
        guard bluetoothReady else {
            primeBluetoothPermission()
            return
        }
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        var seen = Set<String>()
        // 同一藍牙位址只保留一筆，音訊裝置篩選由快照建立邊界負責。
        discoveredDevices = paired.compactMap { DiscoveredDevice(device: $0) }.filter { seen.insert($0.id).inserted }
    }

    /// 啟動附近裝置探索，保留授權等待狀態。
    func startScanning() {
        isScanning = true
        discoveredDevices = []
        connectionError = nil

        primeBluetoothPermission()

        // 授權及電源已就緒才註冊原生連線通知，等待時由狀態事件接續。
        if bluetoothReady {
            performScan()
        } else {
            // 藍牙尚未就緒時保留掃描要求，等權限與電源事件再執行。
            pendingScan = true
        }
    }

    /// 停止附近探索並清除掃描狀態。
    func stopScanning() {
        inquiry?.stop()
        inquiry = nil
        pendingScan = false
        isScanning = false
    }

    /// 建立單一連線嘗試，重設狀態快照並載入該裝置偏好。
    ///
    /// - Parameters:
    ///   - device: 本次連線或服務探索的系統裝置，回呼需核對其身分與世代。
    ///   - model: 目前操作的機型，能力、命令與來源由其配置提供。
    ///   - notifyOnSuccess: 連線成功後是否發出可見通知，預設為 false。
    func connect(to device: DiscoveredDevice, model: BudsModel, notifyOnSuccess: Bool = false) {

        // 單一服務不重入目前連線嘗試，取消由 disconnect 負責。
        if isConnecting {
            return
        }
        stopScanning()
        isConnecting = true
        autoConnectShouldNotify = notifyOnSuccess

        // 新連線嘗試先清除舊封包與操作回饋，避免跨裝置沿用狀態。
        connectionError = nil
        streamDecoder = SppStreamDecoder()
        pendingSettingID = nil
        commandNotice = nil
        status = BudsStatus()
        connectedModel = model
        connectedName = device.name
        connectedDevice = device.device
        suppressAutoConnect = false
        loadCustomEqualizer()
        let savedColor = UserDefaults.standard.string(forKey: appearanceKey)
        appearanceColorOverride = model.profile.colors.first(where: { $0.id == savedColor })?.id
        connectRetryCount = 0
        connectDeadline = ContinuousClock.now.advanced(by: .seconds(connectBudget))
        // 世代遞增讓舊 callback 與逾時任務失效，再重設耳機快照。
        connectGeneration &+= 1
        DiagnosticsLog.shared.log(
            "connect: \(device.name) [\(device.address)] as \(model.name), notify=\(notifyOnSuccess)")
        attemptConnection(device: device, model: model)
    }

    /// 取消控制通道與過期任務，deviceLink 決定是否關閉完整裝置連線。
    ///
    /// - Parameters:
    ///   - deviceLink: true 關閉完整裝置連線；false 僅釋放 App 的控制通道。
    func disconnect(deviceLink: Bool = true) {
        // 更新期間由韌體生命週期管理通道，手動斷線不能中斷寫入。
        guard !firmware.isRunning else { return }
        spatialKeepAlive?.cancel()
        spatialKeepAlive = nil
        spatialPreviousEnabled = nil
        spatialDataReceived = false
        selfTestTimeout?.cancel()
        selfTestRunning = false
        // 使用者明確中斷才關閉完整耳機連線，結束 App 保留系統音訊路由。
        if deviceLink { connectedDevice?.closeConnection() }
        // 關閉控制通道後清除待寫 buffer 與作業快照。
        rfcommChannel?.close()
        rfcommChannel = nil
        pendingWrites.removeAll()
        failedSettingID = nil
        connectedDevice = nil
        isConnected = false
        connectedModel = nil
        connectedName = nil
        pendingSettingID = nil
        commandNotice = nil
        isConnecting = false
        cancelAttemptTimeout()
        suppressAutoConnect = true
        connectGeneration &+= 1
        streamDecoder = SppStreamDecoder()
        status = BudsStatus()
    }

    /// 更新重啟或意外斷線後重建目前裝置的控制通道。
    func reconnectCurrentDevice() {
        // 重連需要目前裝置、機型與有效快照，任一缺少就保留現況。
        guard let device = connectedDevice, let model = connectedModel,
            let snapshot = DiscoveredDevice(device: device)
        else { return }
        connect(to: snapshot, model: model)
    }

    /// 依冷卻時間檢查目前音訊耳機，手動中斷後維持暫停。
    func pollAutoConnect() {
        // 示範資料不寫入系統偏好或啟動真實連線。
        guard !isDemo else { return }
        // 權限、目前通道、手動中斷與進行中的嘗試共同限制自動連線。
        guard autoConnectArmed, bluetoothReady, !isConnected,
            rfcommChannel == nil, !isConnecting, !suppressAutoConnect
        else {
            // 條件排列與連線守門順序一致，日誌只描述第一個阻擋原因。
            let reasons = [
                (!autoConnectArmed, "auto-connect not armed"),
                (!bluetoothReady, "Bluetooth not ready (permission or powered off)"),
                (isConnected, "already connected"),
                (isConnecting, "attempt in flight"),
                (suppressAutoConnect, "suppressed after manual disconnect"),
                (rfcommChannel != nil, "channel still open"),
            ]
            notePollSkip(reasons.first(where: { $0.0 })?.1)
            return
        }
        notePollSkip(nil)

        // 失敗後保留冷卻窗，避免系統通知與定時檢查重複開啟通道。
        if let last = lastAutoAttempt, last.duration(to: .now) < .seconds(autoConnectCooldown) {
            return
        }
        // 配對清單必須包含可用耳機，否則記錄自動連線略過原因。
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice],
            let device = preferredDevice(in: paired)
        else {
            notePollSkip("no paired Galaxy Buds")
            return
        }

        lastAutoAttempt = .now
        // 系統裝置轉成有效耳機快照後才開始連線。
        guard let snapshot = DiscoveredDevice(device: device), let model = snapshot.model else { return }
        connect(to: snapshot, model: model, notifyOnSuccess: true)
    }

    // MARK: - 偏好與預覽

    /// 建立機型的示範快照，維持預覽與真實藍牙分離。
    ///
    /// - Parameters:
    ///   - model: 目前操作的機型，能力、命令與來源由其配置提供。
    func configureDemo(_ model: BudsModel) {
        // 示範快照提供預覽功能，數值與實機藍牙回報分開。
        isDemo = true
        isConnected = true
        connectedModel = model
        connectedName = model.name + " · " + String(localized: "Preview mode")
        status = BudsStatus()
        appearanceColorOverride = nil
        status.deviceColorID = model.profile.variant(reportedID: nil, overrideID: nil).deviceIDs.first
        status.batteryLeft = 76
        status.batteryRight = 81
        status.batteryCase = 64
        status.noiseControlMode = .anc
        status.hasControlStatus = true
        status.gestureEnabled = Array(repeating: true, count: 7)
        status.touchCommandTail = [1, 1]
        status.stereoBalance = 16
        status.additionalSettings = Dictionary(
            uniqueKeysWithValues: model.profile.additionalSettings.map { ($0, true) })
        status.touchHoldLeft = .noiseControl
        status.touchHoldRight = .noiseControl
        // 示範的輪替與等級遵循既有協定值域，操作不傳到真實裝置。
        status.noiseCycleLeft = .ancAmbient
        status.noiseCycleRight = .ancAmbient
        status.ancLevel = 2
        // 示範快照只包含配置提供的能力，非實機驗收結果。
        if model.profile.features.contains(.headGestures) { status.headGestureMask = 2 }
        commandNotice = nil
    }

    /// 更新快捷項目選擇，實機模式保存偏好。
    ///
    /// - Parameters:
    ///   - control: 要讀取或操作的快捷項目，來源由機型配置限制。
    ///   - visible: 是否將此項目加入目前裝置的快捷面板偏好。
    func setQuickControlVisible(_ control: QuickControl, visible: Bool) {
        selectedQuickControls.removeAll { $0 == control.rawValue }
        // 快捷項目選擇去重後追加，保持使用者選擇的順序。
        if visible { selectedQuickControls.append(control.rawValue) }
        // 裝置與使用者偏好只在實機模式保存。
        if !isDemo { UserDefaults.standard.set(selectedQuickControls, forKey: "quickControls") }
    }

    /// 讀取指定快捷項目在最新快照中的開關值。
    ///
    /// - Parameters:
    ///   - control: 要讀取或操作的快捷項目，來源由機型配置限制。
    /// - Returns: 目前狀態快照中此快捷設定的開關值。
    func quickControlValue(_ control: QuickControl) -> Bool {
        // 快捷操作讀取同一份狀態快照，避免面板自行保存設定值。
        switch control {
        // 語音偵測讀取共享狀態快照。
        case .detectConversations: status.detectConversations
        // 通話環境音讀取共享狀態快照。
        case .ambientDuringCalls: status.ambientDuringCalls
        // 觸控鎖定讀取共享狀態快照。
        case .touchpadLock: status.touchpadLocked
        }
    }

    /// 把快捷項目轉送至對應的耳機設定方法。
    ///
    /// - Parameters:
    ///   - control: 要讀取或操作的快捷項目，來源由機型配置限制。
    ///   - enabled: 是否啟用此方法所管理的功能，實機結果由系統或耳機回報確認。
    func setQuickControl(_ control: QuickControl, enabled: Bool) {
        // 快捷操作轉送既有設定入口，沿用相同驗證與傳輸流程。
        switch control {
        // 語音偵測使用詳細設定的相同寫入入口。
        case .detectConversations: setDetectConversations(enabled)
        // 通話環境音使用詳細設定的相同寫入入口。
        case .ambientDuringCalls: setAmbientDuringCalls(enabled)
        // 觸控鎖定使用詳細設定的相同寫入入口。
        case .touchpadLock: setTouchpadLock(enabled)
        }
    }

    /// 驗證機型配色並保存裝置的手動選色，nil 表示自動辨識。
    ///
    /// - Parameters:
    ///   - color: 機型配置中的配色 ID，nil 表示依裝置回報自動辨識。
    func setAppearanceColor(_ color: String?) {
        // 手動選色必須命中機型配置，nil 表示回到裝置辨識。
        guard color == nil || connectedModel?.profile.colors.contains(where: { $0.id == color }) == true else { return }
        appearanceColorOverride = color
        // 裝置與使用者偏好只在實機模式保存。
        if !isDemo { UserDefaults.standard.set(color, forKey: appearanceKey) }
    }

    // MARK: - 耳機設定

    /// 送出聆聽模式命令，實機值由耳機回報確認。
    ///
    /// - Parameters:
    ///   - mode: 要選擇或查詢的已知噪音模式，協定碼由共用列舉提供。
    func setNoiseControl(_ mode: NoiseControlMode) {
        let msg = SppMessage(
            messageID: .noiseControls,
            payload: Data([UInt8(mode.rawValue)])
        )
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(msg) else { return }

        // 預覽只修改示範快照，真實狀態由裝置回報取得。
        if isDemo { status.noiseControlMode = mode }
    }

    /// 將環境音等級限制於機型範圍後傳送。
    ///
    /// - Parameters:
    ///   - volume: 環境音等級索引，傳送前限制於目前機型的有效範圍。
    func setAmbientVolume(_ volume: Int) {
        // 未載入機型範圍時不猜測可寫入等級。
        guard let model = connectedModel else { return }
        let volume = max(0, min(model.maxAmbientVolume, volume))
        let msg = SppMessage(
            messageID: .ambientVolume,
            payload: Data([UInt8(volume)])
        )
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(msg) else { return }
        // 預覽只修改示範快照，真實狀態由裝置回報取得。
        if isDemo { status.ambientSoundVolume = volume }
    }

    /// 以 0 起算的配置索引傳送 ANC 等級。
    ///
    /// - Parameters:
    ///   - level: 以 0 起算的 ANC 等級索引，限制於機型配置範圍。
    func setAncLevel(_ level: Int) {
        // 未載入機型範圍時不猜測可寫入段數。
        guard let model = connectedModel else { return }
        let count = model.ancLevelCount
        let clamped = max(0, min(count - 1, level))
        DiagnosticsLog.shared.log("ANC strength: sending step \(clamped) of \(count)")
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(SppMessage(messageID: .noiseReductionLevel, payload: Data([UInt8(clamped)]))) else { return }
        // 預覽只修改示範快照，真實狀態由裝置回報取得。
        if isDemo { status.ancLevel = clamped }
    }

    /// 傳送單耳噪音控制開關，傳輸失敗時保留既有值。
    ///
    /// - Parameters:
    ///   - enabled: 是否啟用此方法所管理的功能，實機結果由系統或耳機回報確認。
    func setNoiseControlWithOneEarbud(_ enabled: Bool) {
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(SppMessage(messageID: .setAncWithOneEarbud, payload: Data([enabled ? 1 : 0]))) else { return }
        status.ncWithOneEarbud = enabled
    }

    /// 現行自訂環境音命令保留三個附加欄位，避免改寫耳機的其他環境音設定。
    ///
    /// - Parameters:
    ///   - enabled: 是否啟用此方法所管理的功能，實機結果由系統或耳機回報確認。
    ///   - left: 左耳自訂環境音等級，限制於機型配置上限。
    ///   - right: 右耳自訂環境音等級，限制於機型配置上限。
    func setCustomAmbient(enabled: Bool, left: Int, right: Int) {
        // 自訂環境音需要機型範圍與完整尾端欄位，避免覆寫未知設定。
        guard let profile = connectedModel?.profile, let tail = status.ambientCommandTail else { return }
        let left = max(0, min(profile.ambientCustomMax, left))
        let right = max(0, min(profile.ambientCustomMax, right))
        let payload = Data([enabled ? 1 : 0, UInt8(left), UInt8(right)] + tail)
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(SppMessage(messageID: .customizeAmbientSound, payload: payload)) else { return }
        status.ambientCustomEnabled = enabled
        status.ambientCustomLeft = left
        status.ambientCustomRight = right
    }

    /// 傳送語音偵測開關，候選顯示值維持待回報狀態。
    ///
    /// - Parameters:
    ///   - enabled: 是否啟用此方法所管理的功能，實機結果由系統或耳機回報確認。
    func setDetectConversations(_ enabled: Bool) {
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(SppMessage(messageID: .setDetectConversations, payload: Data([enabled ? 1 : 0]))) else {
            return
        }
        status.detectConversations = enabled
    }

    /// 傳送語音偵測持續時間，0、1、2 分別代表 5、10、15 秒。
    ///
    /// - Parameters:
    ///   - duration: 持續時間索引，0、1、2 分別代表 5、10、15 秒。
    func setDetectConversationsDuration(_ duration: Int) {
        let duration = max(0, min(2, duration))
        // 命令排入成功後才更新持續時間的候選值。
        guard
            sendMessage(
                SppMessage(
                    messageID: .setDetectConversationsDuration, payload: Data([UInt8(duration)])))
        else { return }
        status.detectConversationsDuration = duration
    }

    /// 傳送通話時聽見自身聲音的開關。
    ///
    /// - Parameters:
    ///   - enabled: 是否啟用此方法所管理的功能，實機結果由系統或耳機回報確認。
    func setSidetone(_ enabled: Bool) {
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(SppMessage(messageID: .setSidetone, payload: Data([enabled ? 1 : 0]))) else { return }
        status.sidetone = enabled
    }

    /// 傳送通話環境音開關，協定以 0 表示啟用。
    ///
    /// - Parameters:
    ///   - enabled: 是否啟用此方法所管理的功能，實機結果由系統或耳機回報確認。
    func setAmbientDuringCalls(_ enabled: Bool) {
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(SppMessage(messageID: .setCallPathControl, payload: Data([enabled ? 0 : 1]))) else { return }
        status.ambientDuringCalls = enabled
    }

    /// 選擇預設 EQ，自訂模式會先傳送九段增益。
    ///
    /// - Parameters:
    ///   - preset: 要套用的 EQ 預設，自訂模式另依已回報曲線處理。
    func setEqualizer(_ preset: EqualizerPreset) {
        // 自訂 wire 模式與九段曲線分開，未知曲線不能默默改成平坦。
        if preset == .custom {

            // 有完整候選曲線時送出內容，否則只選擇耳機已有的自訂模式。
            if let bands = status.customEqualizerBands {
                setCustomEqualizer(bands: bands)
            } else if sendMessage(SppMessage(messageID: .equalizer, payload: Data([7]))) {
                // 尚無自訂曲線時，只請耳機切換到其既有自訂 EQ。
                status.equalizerPreset = .custom
            }
            return
        }

        let msg = SppMessage(
            messageID: .equalizer,
            payload: Data([UInt8(preset.rawValue)])
        )
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(msg) else { return }
        status.equalizerPreset = preset
    }

    /// 傳送九段 -10...10 增益與自訂模式，兩個封包排入成功才保存候選曲線。
    ///
    /// - Parameters:
    ///   - bands: 九段整數增益，各值使用 -10...10 範圍。
    func setCustomEqualizer(bands: [Int]) {
        // 自訂命令要求完整九段曲線，缺少的頻段保留未知而拒絕寫入。
        guard bands.count == 9 else { return }
        let clamped = bands.map { Int8(max(-10, min(10, $0))) }
        var payload = Data([9])
        // 九段增益各轉為協定整數，保留頻段順序。
        for band in clamped {
            payload.append(UInt8(bitPattern: band))
        }
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(SppMessage(messageID: .customEqualize, payload: payload)) else { return }
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(SppMessage(messageID: .equalizer, payload: Data([7]))) else { return }
        let intBands = clamped.map { Int($0) }
        status.customEqualizerBands = intBands
        status.equalizerPreset = .custom
        saveCustomEqualizer(intBands)
    }

    /// 更新單一頻段候選值，再傳送完整九段曲線。
    ///
    /// - Parameters:
    ///   - index: 以 0 起算的 EQ 頻段索引，須位於已回報曲線範圍內。
    ///   - value: 目前頻段的整數增益，限制於 -10...10。
    func setCustomEqualizerBand(_ index: Int, value: Int) {
        // 只修改已回報曲線中的有效頻段，缺少資料時保留現況。
        guard var bands = status.customEqualizerBands, bands.indices.contains(index) else { return }
        bands[index] = max(-10, min(10, value))
        setCustomEqualizer(bands: bands)
    }

    /// 傳送七個手勢開關，協定首位元組使用反向布林值。
    ///
    /// - Parameters:
    ///   - locked: 是否鎖定耳機操作，協定的反向旗標由方法轉換。
    func setTouchpadLock(_ locked: Bool) {

        // 七個手勢及操作尾段必須完整，寫回保留未修改的功能。
        guard let flags = status.gestureEnabled, let tail = status.touchCommandTail, flags.count == 7 else {
            commandNotice = .error(String(localized: "Waiting for earbud settings"))
            return
        }
        let payload = Data([locked ? 0 : 1] + flags.map { $0 ? UInt8(1) : UInt8(0) } + tail)
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(SppMessage(messageID: .lockTouchpad, payload: payload)) else { return }
        status.touchpadLocked = locked
    }

    /// 單獨設定操作旗標，保留其他手勢與整體鎖定狀態。
    ///
    /// - Parameters:
    ///   - gesture: 要修改的耳機手勢，其餘手勢狀態維持原值。
    ///   - enabled: 是否啟用此方法所管理的功能，實機結果由系統或耳機回報確認。
    func setTouchGesture(_ gesture: TouchGesture, enabled: Bool) {
        // 單一手勢以完整旗標快照組包，缺值不推測為停用。
        guard var flags = status.gestureEnabled, let tail = status.touchCommandTail, flags.count == 7 else { return }
        flags[gesture.rawValue] = enabled
        let payload = Data(
            [status.touchpadLocked ? 0 : 1] + flags.map { $0 ? UInt8(1) : UInt8(0) } + tail)
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(SppMessage(messageID: .lockTouchpad, payload: payload)) else { return }
        status.gestureEnabled = flags
    }

    /// 設定須已配置及回報，複合音效命令還需要完整的兩個原始開關值。
    ///
    /// - Parameters:
    ///   - setting: 機型配置允許的進階設定項目。
    /// - Returns: 配置、回報與複合命令原始值齊備時為 true。
    func canSetAdditionalSetting(_ setting: AdditionalSetting) -> Bool {
        // UI 和送出入口共用能力與資料完整性判定。
        guard connectedModel?.profile.additionalSettings.contains(setting) == true,
            status.additionalSettings[setting] != nil
        else { return false }
        // 複合封包會帶上另一個開關，未知值不能以 false 代替。
        // 人聲與音量標準化共用複合命令，另一欄須保留已回報原值。
        if setting.command == .setBoostLoudness {
            return status.additionalSettings[.voiceBoost] != nil
                && status.additionalSettings[.volumeNormalization] != nil
        }
        return true
    }

    /// 配置只允許已有命令對應的開關，成功傳輸後顯示候選值。
    ///
    /// - Parameters:
    ///   - setting: 機型配置允許的進階設定項目。
    ///   - enabled: 是否啟用此方法所管理的功能，實機結果由系統或耳機回報確認。
    func setAdditionalSetting(_ setting: AdditionalSetting, enabled: Bool) {
        // 配置、回報與複合欄位必須齊備，才允許傳送進階設定。
        guard canSetAdditionalSetting(setting) else { return }
        var payload: Data
        // 人聲與音量標準化共用複合命令，另一欄須保留已回報原值。
        if setting.command == .setBoostLoudness {
            // 人聲增強與音量標準化共用命令，兩個原始值都必須已回報。
            guard let boost = status.additionalSettings[.voiceBoost],
                let normalized = status.additionalSettings[.volumeNormalization]
            else { return }
            payload = Data([
                (setting == .voiceBoost ? enabled : boost) ? 1 : 0,
                (setting == .volumeNormalization ? enabled : normalized) ? 1 : 0,
            ])
        } else {
            // 獨立命令依配置處理反向布林值與命令前綴。
            let value = setting.isInverted ? !enabled : enabled
            payload = Data(setting.commandPrefix + [value ? 1 : 0])
        }
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(SppMessage(messageID: setting.command, payload: payload)) else { return }
        status.additionalSettings[setting] = enabled
    }

    /// 設定耳機左右平衡，協定範圍 0...32，16 代表置中。
    ///
    /// - Parameters:
    ///   - value: 耳機左右平衡值，限制於 0...32，16 代表置中。
    func setStereoBalance(_ value: Int) {
        let value = max(0, min(32, value))
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(SppMessage(messageID: .stereoBalance, payload: Data([UInt8(value)]))) else { return }
        status.stereoBalance = value
    }

    /// 已配置燈效能力的機型透過操作命令尾端傳送樣式，保留七個手勢與進階長按值。
    ///
    /// - Parameters:
    ///   - style: 燈效協定碼，1 為固定、2 為閃爍、3 為淡入淡出。
    func setLightingStyle(_ style: Int) {
        // 是否提供燈效由機型能力注入，樣式碼遵循共用協定。
        guard connectedModel?.profile.features.contains(.bladeLights) == true,
            (1...3).contains(style), let flags = status.gestureEnabled, let existing = status.touchCommandTail,
            flags.count == 7
        else { return }
        let tail = [UInt8(style), existing[1]]
        let payload = Data([status.touchpadLocked ? 0 : 1] + flags.map { $0 ? UInt8(1) : UInt8(0) } + tail)
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(SppMessage(messageID: .lockTouchpad, payload: payload)) else { return }
        status.touchCommandTail = tail
    }

    /// 設定耳機的頭部動作偵測方向，註冊測試位元維持關閉，偏好按裝置保存。
    ///
    /// - Parameters:
    ///   - enabled: 是否啟用此方法所管理的功能，實機結果由系統或耳機回報確認。
    ///   - nodForPositive: 點頭是否代表肯定，false 使用另一偵測方向。
    func setHeadGestures(enabled: Bool, nodForPositive: Bool) {
        // 機型能力限制送出入口，未配置的頁面不能開啟偵測。
        guard connectedModel?.profile.features.contains(.headGestures) == true else { return }
        let mask: UInt8 = (enabled ? 1 : 0) | (nodForPositive ? 2 : 0)
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(SppMessage(messageID: .headGestures, payload: Data([mask]))) else { return }
        status.headGestureMask = mask
        // 裝置與使用者偏好只在實機模式保存。
        if !isDemo, let address = connectedDevice?.addressString {
            UserDefaults.standard.set(Int(mask), forKey: "headGestures." + address)
        }
    }

    /// 分別傳送左右耳的長按動作碼。
    ///
    /// - Parameters:
    ///   - left: 左耳長按動作，協定碼依機型配置選擇。
    ///   - right: 右耳長按動作，協定碼依機型配置選擇。
    func setTouchHoldActions(left: TouchHoldAction, right: TouchHoldAction) {
        // 長按碼由機型配置提供，未知機型不建立命令。
        guard let profile = connectedModel?.profile else { return }
        /// 依注入的動作與助理規則選擇 wire 碼，未知或缺失基本碼回傳 nil。
        ///
        /// - Parameters:
        ///   - action: 機型配置可編碼的長按動作。
        ///   - base: 耳機回報的基本長按碼，nil 表示尚未提供。
        /// - Returns: 可傳送的長按動作碼；缺少能力、配置或基本碼時回傳 nil。
        func code(_ action: TouchHoldAction, base: UInt8?) -> UInt8? {
            // 助理提供者需要依機型規則使用基本碼或獨立助理動作碼。
            if profile.assistantProviders[action.rawValue] != nil {
                // 耳機尚未回報助理能力時，拒絕建立助理長按設定。
                guard status.touchAssistantSupported else { return nil }
                // 使用助理覆蓋欄位的機型保留原基本動作碼。
                if profile.assistantOverridesAction { return base }
                return profile.touchActionCodes[TouchHoldAction.digitalAssistant.rawValue].map(UInt8.init)
            }
            return profile.touchActionCodes[action.rawValue].map(UInt8.init)
        }
        // 左右耳都能編碼後才傳送，避免寫入不完整長按設定。
        guard let leftCode = code(left, base: status.touchHoldBaseLeft),
            let rightCode = code(right, base: status.touchHoldBaseRight)
        else { return }
        // 左右基本動作都可編碼後，組成同一命令並另保留助理提供者。
        var payload = Data([leftCode, rightCode])
        let leftAssistant =
            left == status.touchHoldLeft
            ? (status.touchAssistantLeft ?? 0) : (profile.assistantProviders[left.rawValue] ?? 0)
        let rightAssistant =
            right == status.touchHoldRight
            ? (status.touchAssistantRight ?? 0) : (profile.assistantProviders[right.rawValue] ?? 0)
        // 耳機支援助理欄位時才追加兩耳的助理提供者。
        if status.touchAssistantSupported { payload.append(contentsOf: [leftAssistant, rightAssistant]) }
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(SppMessage(messageID: .setTouchpadOption, payload: payload)) else { return }
        status.touchHoldBaseLeft = leftCode
        status.touchHoldBaseRight = rightCode
        status.touchAssistantLeft = leftAssistant
        status.touchAssistantRight = rightAssistant
        status.touchHoldLeft = left
        status.touchHoldRight = right
    }

    /// 傳送左右耳噪音輪替遮罩。
    ///
    /// - Parameters:
    ///   - left: 左耳噪音模式輪替，至少包含兩種已知模式。
    ///   - right: 右耳噪音模式輪替，至少包含兩種已知模式。
    func setNoiseControlCycle(left: NoiseControlCycle, right: NoiseControlCycle) {
        // 只有四個已知模式位元且各選至少兩種才可構成輪替。
        guard left.rawValue & ~15 == 0, right.rawValue & ~15 == 0,
            left.rawValue.nonzeroBitCount >= 2, right.rawValue.nonzeroBitCount >= 2
        else { return }
        let payload = Data([UInt8(left.rawValue), UInt8(right.rawValue)])
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(SppMessage(messageID: .setTouchAndHoldNoiseControls, payload: payload)) else { return }
        status.noiseCycleLeft = left
        status.noiseCycleRight = right
    }

    /// 開始或停止尋找音效，回傳控制封包是否成功排入。
    ///
    /// - Parameters:
    ///   - start: 是否開始尋找音效，false 傳送停止命令。
    /// - Returns: 命令成功排入或示範模式接受時為 true，傳輸拒絕時為 false。
    @discardableResult
    func findMyBuds(start: Bool) -> Bool {
        let messageID: MessageID
        // 尋找音效依實際配戴狀態選擇已知協定碼，停止使用獨立命令。
        if start {

            let worn = status.isLeftWearing || status.isRightWearing
            messageID = worn ? .findMyEarbudsOnWearingStart : .findMyEarbudsStart
        } else {
            // 停止尋找使用獨立停止命令，不受配戴狀態影響。
            messageID = .findMyEarbudsStop
        }
        return sendMessage(SppMessage(messageID: messageID))
    }

    /// 設定尋找音效的左右靜音，回傳排入結果。
    ///
    /// - Parameters:
    ///   - left: 左耳是否靜音，與另一耳分開編碼。
    ///   - right: 右耳是否靜音，與另一耳分開編碼。
    /// - Returns: 靜音命令成功排入時為 true，尚未代表耳機已套用。
    @discardableResult
    func setMuteEarbud(left: Bool, right: Bool) -> Bool {
        return sendMessage(
            SppMessage(
                messageID: .muteEarbud, payload: Data([left ? 1 : 0, right ? 1 : 0])))
    }

    /// 查詢耳機與充電盒的韌體及序號。
    func requestAboutInfo() {
        sendMessage(SppMessage(messageID: .debugGetAllData))
        sendMessage(SppMessage(messageID: .debugSerialNumber))
        sendMessage(SppMessage(messageID: .cradleSerialNumber))
    }

    /// 啟停密合度測試，命令排入後清除前次結果。
    ///
    /// - Parameters:
    ///   - active: 是否啟動密合度測試，停止時保留先前結果。
    /// - Returns: 測試命令成功排入時為 true，測試結果由後續回報提供。
    @discardableResult
    func setFitTest(active: Bool) -> Bool {
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(SppMessage(messageID: .checkFitOfEarbuds, payload: Data([active ? 1 : 0]))) else {
            return false
        }
        // 開始測試才清除前次結果，停止時保留已回報資訊。
        if active {
            status.fitLeft = .unknown
            status.fitRight = .unknown
        }
        return true
    }

    /// 自我測試以四個 byte 的位元結果回報，逾時保留失敗資訊。
    func runSelfTest() {
        // 配置未提供診斷或已有測試時保留現況，不建立第二個 watchdog。
        guard connectedModel?.profile.features.contains(.hardwareDiagnostics) == true, !selfTestRunning else { return }
        status.selfTestMask = nil
        // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
        guard sendMessage(SppMessage(messageID: .selfTest)) else { return }
        selfTestRunning = true
        selfTestTimeout?.cancel()
        selfTestTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            // 取消、服務釋放或測試已結束時，逾時任務不再修改狀態。
            guard !Task.isCancelled, let self, self.selfTestRunning else { return }
            self.selfTestRunning = false
            self.commandNotice = .error(String(localized: "The earbuds did not return diagnostic results."))
        }
    }

    /// 感測器啟動與 keep-alive 沿用公開研究協定，離頁或斷線停止。
    ///
    /// - Parameters:
    ///   - enabled: 是否啟用此方法所管理的功能，實機結果由系統或耳機回報確認。
    func setSpatialTracking(_ enabled: Bool) {
        let hadSession = spatialKeepAlive != nil || spatialPreviousEnabled != nil
        spatialKeepAlive?.cancel()
        spatialKeepAlive = nil
        // 耳機能力決定是否提供感測器流程，Mac 渲染器維持獨立。
        guard connectedModel?.profile.features.contains(.spatialAudio) == true else { return }
        // 啟用前保存耳機原值，停止後恢復同一份設定。
        if enabled {
            spatialDataReceived = false
            // 追蹤啟動前保存實際回報值，未知值不能作為還原基準。
            guard let original = status.spatialAudioEnabled else { return }
            // 同一追蹤工作只保存首次基準，避免重複啟動覆蓋還原值。
            if spatialPreviousEnabled == nil { spatialPreviousEnabled = original }
            // 排入失敗時結束操作，實際回報由接收流程獨立驗證。
            guard sendMessage(SppMessage(messageID: .setSpatialAudio, payload: Data([1]))),
                sendMessage(SppMessage(messageID: .spatialAudioControl, payload: Data([0])))
            else { return }
            spatialKeepAlive = Task { @MainActor [weak self] in
                // 追蹤啟用期間每兩秒維持感測串流，取消後不再寫入。
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    // 取消、斷線或服務釋放後停止 keep-alive。
                    guard !Task.isCancelled, let self, self.isConnected else { return }
                    // keep-alive 排入失敗時結束背景任務，避免持續向失效通道寫入。
                    guard self.sendMessage(SppMessage(messageID: .spatialAudioControl, payload: Data([4]))) else {
                        return
                    }
                }
            }
        } else {
            // 停用追蹤時結束感測串流，並依保存的基準還原耳機設定。
            // 未曾啟動的頁面離開事件不寫入耳機空間音訊設定。
            guard hadSession else { return }
            _ = sendMessage(SppMessage(messageID: .spatialAudioControl, payload: Data([1])))
            _ = sendMessage(
                SppMessage(messageID: .setSpatialAudio, payload: Data([spatialPreviousEnabled == true ? 1 : 0])))
            spatialPreviousEnabled = nil
            spatialDataReceived = false
            status.spatialAttached = false
        }
    }

    /// 更新條件由服務統一判斷，防止介面與傳輸入口各自放寬限制。
    ///
    /// - Parameters:
    ///   - binary: 已通過機型、版本與區段校驗的完整韌體映像。
    /// - Returns: 連線、機型、版本、能力、電量與作業狀態都符合時為 true。
    func canInstallFirmware(_ binary: FirmwareBinary) -> Bool {
        // 韌體安裝資格必須依目前連線機型判斷。
        guard let model = connectedModel else { return false }
        let minimum = model.profile.firmware.minimumBatteryPercent
        return isConnected && !isDemo && !firmware.isRunning
            && model.profile.features.contains(.firmwareUpdate)
            && binary.buildName.hasPrefix(model.profile.firmware.buildPrefix)
            && FirmwareVersion.isNewer(binary.buildName, than: status.softwareVersion)
            && status.batteryLeft.map({ $0 >= minimum }) == true
            && status.batteryRight.map({ $0 >= minimum }) == true
    }

    /// 映像與機型已在選取流程驗證，寫入必須由確認按鈕觸發。
    ///
    /// - Parameters:
    ///   - binary: 已通過機型、版本與區段校驗的完整韌體映像。
    func installFirmware(_ binary: FirmwareBinary) {
        // 安裝條件與通道都有效後，才啟動裝置驅動傳輸。
        guard canInstallFirmware(binary), let channel = rfcommChannel else { return }
        setSpatialTracking(false)
        firmware.send = { [weak self] message in self?.sendMessage(message) ?? false }
        firmware.start(binary: binary, channelMtu: Int(channel.getMTU()))
    }

    // MARK: - 連線協調與服務探索

    /// 透過 CoreBluetooth 取得權限與電源狀態。
    func primeBluetoothPermission() {
        // 原生權限管理器只建立一次，後續沿用其 delegate 回報。
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: .main)
        }
    }

    /// 註冊已配對裝置連線通知並嘗試目前音訊耳機。
    private func armConnectNotifications() {
        // 一個服務只持有一份全域配對裝置連線通知。
        guard connectNotification == nil else { return }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceDidConnect(_:device:))
        )
        attemptAutoConnect(notify: false)
    }

    /// 將系統裝置事件送回 MainActor 進行選擇。
    ///
    /// - Parameters:
    ///   - notification: 系統送出的生命週期或選取通知，事件內容由框架提供。
    ///   - device: 本次連線或服務探索的系統裝置，回呼需核對其身分與世代。
    @objc nonisolated func deviceDidConnect(
        _ notification: IOBluetoothUserNotification!,
        device: IOBluetoothDevice!
    ) {
        let snapshot = device.flatMap { DiscoveredDevice(device: $0) }
        Task { @MainActor in
            // 有效機型事件只在尚未連線時觸發自動選擇。
            guard snapshot?.model != nil, !self.isConnected else { return }
            self.attemptAutoConnect(notify: true)
        }
    }

    /// 優先連接目前音訊裝置，未取得型號時保持未連線。
    ///
    /// - Parameters:
    ///   - notify: 自動連線成功後是否通知使用者。
    private func attemptAutoConnect(notify: Bool) {
        // 權限、目前通道、手動中斷與進行中的嘗試共同限制自動連線。
        guard autoConnectArmed, !suppressAutoConnect, bluetoothReady, !isConnected, rfcommChannel == nil, !isConnecting
        else { return }
        // 自動連線使用 Mac 的配對資料，缺少清單時等待後續事件。
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        // 找到符合音訊輸出的優先裝置後，建立一次連線。
        if let device = preferredDevice(in: paired) {
            // 候選裝置必須可建立快照並辨識機型。
            guard let snapshot = DiscoveredDevice(device: device), let model = snapshot.model else { return }
            connect(to: snapshot, model: model, notifyOnSuccess: notify)
            return
        }
    }

    /// 依目前音訊名稱與已連線狀態排序可辨識裝置。
    ///
    /// - Parameters:
    ///   - devices: Mac 已配對的裝置清單，依音訊輸出與連線狀態選擇。
    /// - Returns: 優先的已連線耳機；沒有可辨識候選時回傳 nil。
    private func preferredDevice(in devices: [IOBluetoothDevice]) -> IOBluetoothDevice? {
        let candidates = devices.filter { DiscoveredDevice(device: $0)?.model != nil }
        let name = preferredAudioDeviceName?.filter { !$0.isWhitespace }.lowercased()
        // 目前 CoreAudio 輸出名稱與可辨識配對裝置相符時優先使用。
        if let name, !name.isEmpty,
            let active = candidates.first(where: { ($0.name ?? "").filter { !$0.isWhitespace }.lowercased() == name })
        {
            return active
        }
        return candidates.first { $0.isConnected() }
    }

    /// 先更新配對清單，再啟動 Classic Bluetooth inquiry。
    private func performScan() {
        refreshPairedDevices()
        // 系統無法建立探索物件時，清除掃描狀態並回報錯誤。
        guard let search = IOBluetoothDeviceInquiry(delegate: self) else {
            isScanning = false
            connectionError = String(localized: "Nearby discovery failed.")
            return
        }
        search.updateNewDeviceNames = true
        search.searchType = kIOBluetoothDeviceSearchClassic.rawValue
        inquiry = search
        let result = search.start()
        // 原生 inquiry 啟動失敗即釋放探索快照並保留結果碼。
        if result != kIOReturnSuccess {
            inquiry = nil
            isScanning = false
            connectionError = String(localized: "Nearby discovery failed.") + " (\(result))"
        }
    }

    /// 使用系統服務記錄或原生非同步 SDP 查詢取得通道，完成與取消由世代判定。
    ///
    /// - Parameters:
    ///   - device: 本次連線或服務探索的系統裝置，回呼需核對其身分與世代。
    ///   - model: 目前操作的機型，能力、命令與來源由其配置提供。
    private func attemptConnection(device: DiscoveredDevice, model: BudsModel) {
        let generation = connectGeneration
        DiagnosticsLog.shared.log("attempt \(connectRetryCount + 1)/\(maxConnectRetries + 1) started")
        startAttemptTimeout(device: device, model: model, generation: generation)
        // 系統已有有效服務記錄時直接使用公開 SDK 快取，避免等待未回報的 SDP 事件。
        if let match = firstChannel(on: device.device, uuidStrings: model.serviceUUIDCandidates) {
            DiagnosticsLog.shared.log("SPP found in system SDP records: \(match.string) → rfcomm \(match.channel)")
            connectViaRFCOMM(device: device, model: model, channelID: match.channel)
            return
        }
        // 同一裝置的服務查詢可由新嘗試接續，結果依當前注入機型解讀。
        if pendingSDPDevice === device.device {
            pendingSDPGeneration = generation
            return
        }
        pendingSDPDevice = device.device
        pendingSDPGeneration = generation
        let result = device.device.performSDPQuery(self)
        // 原生查詢拒絕排入時立即重試，接受後等待 sdpQueryComplete。
        guard result == kIOReturnSuccess else {
            pendingSDPDevice = nil
            pendingSDPGeneration = nil
            handleConnectFailure(device: device, model: model)
            return
        }
    }

    /// 監控單次嘗試，取消或世代過期時不再重試。
    ///
    /// - Parameters:
    ///   - device: 本次連線或服務探索的系統裝置，回呼需核對其身分與世代。
    ///   - model: 目前操作的機型，能力、命令與來源由其配置提供。
    ///   - generation: 目前連線嘗試的世代，舊世代回呼不得接管新連線。
    private func startAttemptTimeout(
        device: DiscoveredDevice, model: BudsModel, generation: Int
    ) {
        attemptTimeoutTask?.cancel()
        attemptTimeoutTask = Task { @MainActor [weak self] in
            // 服務已釋放時，逾時任務不持有或存取失效物件。
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.attemptTimeout))
            // 只有仍在連線且世代一致的嘗試才能觸發逾時處理。
            guard !Task.isCancelled, self.isConnecting, !self.isConnected,
                self.connectGeneration == generation
            else { return }
            DiagnosticsLog.shared.log("attempt timed out after \(Int(self.attemptTimeout))s")
            self.handleConnectFailure(device: device, model: model)
        }
    }

    /// 取消該次連線的逾時任務。
    private func cancelAttemptTimeout() {
        attemptTimeoutTask?.cancel()
        attemptTimeoutTask = nil
    }

    /// 釋放失敗通道，在重試次數與時間窗內再次探索。
    ///
    /// - Parameters:
    ///   - device: 本次連線或服務探索的系統裝置，回呼需核對其身分與世代。
    ///   - model: 目前操作的機型，能力、命令與來源由其配置提供。
    private func handleConnectFailure(device: DiscoveredDevice, model: BudsModel) {
        // 只有進行中的連線嘗試需要失敗回復，完成後的事件略過。
        guard isConnecting else { return }
        cancelAttemptTimeout()

        connectGeneration &+= 1
        rfcommChannel?.close()
        rfcommChannel = nil
        connectRetryCount += 1

        // 只在次數與開始重試的時間窗內嘗試，世代隔離前次非同步結果。
        if connectRetryCount <= maxConnectRetries, ContinuousClock.now < connectDeadline {
            let generation = connectGeneration

            Task { @MainActor [weak self] in
                // 服務已釋放時，重試任務結束。
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.connectRetryCount))
                // 重試前核對連線世代，避免舊作業接管新裝置。
                guard self.isConnecting, self.connectGeneration == generation else { return }
                self.attemptConnection(device: device, model: model)
            }
            return
        }
        DiagnosticsLog.shared.log("connect failed after \(connectRetryCount) attempt(s)")

        failConnect(
            String(
                localized:
                    "Could not open the earbud control channel. Confirm the earbuds are connected to this Mac, then retry."
            ))
    }

    /// 依已驗證 UUID 配置順序，從原生 SDP 記錄取得第一個可用通道。
    ///
    /// - Parameters:
    ///   - target: 本次連線或服務探索的系統裝置，回呼需核對其身分與世代。
    ///   - uuidStrings: 機型配置注入的服務 UUID，依配置順序探索。
    /// - Returns: 第一個有效服務 UUID 與通道；沒有符合的服務時回傳 nil。
    private func firstChannel(
        on target: IOBluetoothDevice, uuidStrings: [String]
    ) -> (string: String, channel: BluetoothRFCOMMChannelID)? {
        // 服務 UUID 依機型配置的優先順序探索。
        for string in uuidStrings {
            // 配置載入已驗證 UUID 格式，原生物件採完整 128-bit bytes。
            var storage = UUID(uuidString: string)!.uuid
            let uuid = withUnsafeBytes(of: &storage) { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: $0.count) }
            // 依配置順序探索服務，未找到該 UUID 時繼續下一項。
            guard let record = target.getServiceRecord(for: uuid) else { continue }
            var channelID: BluetoothRFCOMMChannelID = 0
            // 服務存在且有有效 RFCOMM 屬性才可進入通道建立流程。
            if record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess {
                return (string, channelID)
            }
        }
        return nil
    }

    /// 整理服務名稱與通道，供本機連線診斷。
    ///
    /// - Parameters:
    ///   - target: 本次連線或服務探索的系統裝置，回呼需核對其身分與世代。
    /// - Returns: 包含服務名稱與已提供通道的診斷摘要。
    private nonisolated func serviceRecordSummary(of target: IOBluetoothDevice) -> String {
        // 系統未提供服務清單時，以明確摘要記錄資料缺失。
        guard let records = target.services as? [IOBluetoothSDPServiceRecord], !records.isEmpty else {
            return "none"
        }
        return records.map { record in
            let name = record.getServiceName() ?? "unnamed"
            var channel: BluetoothRFCOMMChannelID = 0
            // 服務未提供 RFCOMM 通道時，診斷摘要只保留服務名稱。
            guard record.getRFCOMMChannelID(&channel) == kIOReturnSuccess else { return name }
            return "\(name) (rfcomm \(channel))"
        }.joined(separator: ", ")
    }

    /// 以原生非同步 API 開啟通道，接受後由完成回呼交接，拒絕時走共用重試。
    ///
    /// - Parameters:
    ///   - device: 本次連線或服務探索的系統裝置，回呼需核對其身分與世代。
    ///   - model: 目前操作的機型，能力、命令與來源由其配置提供。
    ///   - channelID: SDP 探索取得的 RFCOMM 通道識別。
    private func connectViaRFCOMM(
        device: DiscoveredDevice,
        model: BudsModel,
        channelID: BluetoothRFCOMMChannelID
    ) {
        var channel: IOBluetoothRFCOMMChannel?
        let result = device.device.openRFCOMMChannelAsync(
            &channel, withChannelID: channelID, delegate: self)
        // 排入成功才持有通道，開啟結果由 rfcommChannelOpenComplete 回報。
        guard result == kIOReturnSuccess, let channel else {
            handleConnectFailure(device: device, model: model)
            return
        }
        rfcommChannel = channel
        connectedDevice = device.device
    }

    /// 通道確實開啟後完成連線並送出初始查詢。
    private func markConnected() {
        // 通道實際開啟且尚未完成初始化時才送出握手。
        guard !isConnected, rfcommChannel?.isOpen() == true else { return }
        cancelAttemptTimeout()
        isConnecting = false
        isConnected = true

        connectionError = nil
        // 機型與裝置位址齊備後，保存此次選擇供後續重連使用。
        if let model = connectedModel, let address = connectedDevice?.addressString {
            UserDefaults.standard.set(model.id, forKey: "model." + address)
        }
        DiagnosticsLog.shared.log(
            "connected to \(connectedName ?? "?") as \(connectedModel?.name ?? "?"), channel mtu \(rfcommChannel?.getMTU() ?? 0)"
        )
        stopScanning()
        sendInitialHandshake()

        requestAboutInfo()
        // 頭部動作能力與已保存偏好齊備時，套用目前裝置的設定。
        if connectedModel?.profile.features.contains(.headGestures) == true,
            let address = connectedDevice?.addressString,
            let mask = UserDefaults.standard.object(forKey: "headGestures." + address) as? Int,
            (0...3).contains(mask)
        {
            setHeadGestures(enabled: mask & 1 != 0, nodForPositive: mask & 2 != 0)
        }

        // EQ 能力從配置讀取，只有支援的機型查詢九段曲線。
        if connectedModel?.supportsCustomEqualizer == true {
            // 支援自訂 EQ 的機型查詢完整預設曲線，顯示採耳機回報。
            sendMessage(SppMessage(messageID: .customEqualizeRecv))
        }
        // 成功提示是一次性請求，顯示快捷面板後解除。
        if autoConnectShouldNotify {
            autoConnectShouldNotify = false
            onAutoConnected?()
        }
    }

    /// 結束失敗嘗試，保留可見錯誤與冷卻起點。
    ///
    /// - Parameters:
    ///   - message: 可顯示的連線失敗原因。
    private func failConnect(_ message: String) {
        cancelAttemptTimeout()
        isConnecting = false
        rfcommChannel?.close()
        rfcommChannel = nil
        connectionError = message
        lastAutoAttempt = .now
    }

    /// 狀態變動時記錄自動連線的略過原因。
    ///
    /// - Parameters:
    ///   - reason: 逾時或略過時的診斷原因，nil 代表沒有原因。
    private func notePollSkip(_ reason: String?) {
        // 略過原因有變化才寫入日誌，避免輪詢產生重複紀錄。
        guard reason != lastPollSkipReason else { return }
        lastPollSkipReason = reason
        // 有效原因才加入診斷；nil 代表清除略過狀態。
        if let reason {
            DiagnosticsLog.shared.log("auto-connect idle: \(reason)")
        }
    }

    // MARK: - 傳輸、回報與保存

    /// 依 MTU 非同步排入封包，原生完成 callback 與耳機回報分別確認結果。
    ///
    /// - Parameters:
    ///   - message: 要傳送的耳機命令，編碼與分段寫入由此入口處理。
    /// - Returns: 預覽接受或全部分段成功排入時為 true，並非耳機設定確認。
    @discardableResult
    private func sendMessage(_ message: SppMessage) -> Bool {
        // 更新中的控制通道優先保留給 FOTA，不混入一般耳機設定。
        if firmware.isTransferring
            && ![MessageID.fotaOpen, .fotaControl, .fotaDownloadData, .fotaUpdate, .fotaResult].contains(
                message.messageID)
        {
            return false
        }
        // 預覽只修改示範快照，真實狀態由裝置回報取得。
        if isDemo {
            commandNotice = .info(String(localized: "Preview mode: changes apply to sample data."))
            return true
        }
        // 非同步送出必須使用本服務持有且已開啟的原生通道。
        guard let channel = rfcommChannel, channel.isOpen() else {
            commandNotice = .error(String(localized: "The control channel is disconnected. Reconnect your earbuds."))
            return false
        }
        // 超出 SPP 長度欄位的資料先拒絕，避免截斷 payload。
        guard let encoded = message.encode() else {
            commandNotice = .error(String(localized: "The setting exceeds the Bluetooth packet size limit."))
            return false
        }
        let limit = Int(channel.getMTU())
        // 原生 MTU 不可為零，分段長度由系統通道回報。
        guard limit > 0 else {
            commandNotice = .error(String(localized: "The control channel is not ready yet."))
            return false
        }
        // 完整封包複製到原生 buffer，再依 MTU 切分，完成回呼才釋放。
        let buffer = WriteBuffer(data: encoded, messageID: message.messageID)
        // 每個原生寫入片段不超過通道 MTU，buffer 持有至完成回呼。
        for offset in stride(from: 0, to: buffer.count, by: limit) {
            let pointer = buffer.pointer.advanced(by: offset)
            let key = UInt(bitPattern: pointer)
            pendingWrites[key] = buffer
            let result = channel.writeAsync(pointer, length: UInt16(min(limit, buffer.count - offset)), refcon: pointer)
            // 原生 writeAsync 拒絕排入時移除該段持有，保留已排入分段生命週期。
            guard result == kIOReturnSuccess else {
                pendingWrites.removeValue(forKey: key)
                DiagnosticsLog.shared.log("TX queue failed id=\(message.messageID.rawValue), result=\(result)")
                // 可見操作追蹤送出與 ACK，不把傳輸成功等同耳機已套用。
                if message.messageID.isSetting {
                    commandNotice = .error(String(localized: "Bluetooth transmission failed. Reconnect your earbuds."))
                }
                return false
            }
        }
        // 可見操作追蹤送出與 ACK，不把傳輸成功等同耳機已套用。
        if message.messageID.isSetting {
            pendingSettingID = message.messageID
            failedSettingID = nil
            commandNotice = .info(String(localized: "Setting queued."))
        }
        return true
    }

    /// 傳送管理端的協定相容資訊。
    private func sendInitialHandshake() {
        // 協定欄位依序為訊息版本、客戶端類型及 Android SDK。
        // Mac 宣告 Other 類型，Android SDK 以 0 表示非 Android 平台。
        let managerInfo = SppMessage(
            messageID: .managerInfo,
            payload: Data([1, 2, 0])
        )
        sendMessage(managerInfo)
        sendMessage(.timeUpdate())

    }

    /// 組合 RFCOMM 分段資料，逐一處理通過 CRC 的訊息。
    ///
    /// - Parameters:
    ///   - data: 已接收的原始位元組，格式、長度與欄位有效性由此解析入口檢查。
    private func handleReceivedData(_ data: Data) {
        DiagnosticsLog.shared.log(
            "RX bytes=\(data.count), prefix=\(data.prefix(4).map { String(format: "%02x", $0) }.joined())")
        // 組框器只產出完整且 CRC 通過的已知訊息，再交給狀態服務。
        for message in streamDecoder.append(data) { handleMessage(message) }
    }

    /// 將回報交給快照，依對應 ACK 或結果碼更新設定回饋。
    ///
    /// - Parameters:
    ///   - message: 有效且已通過 SPP CRC 的訊息，依命令解析或分派。
    private func handleMessage(_ message: SppMessage) {
        // 高頻感測事件直接交給音場，避免每筆四元數引發 SwiftUI 重繪。
        if message.messageID == .spatialAudioData {
            // 有效追蹤事件可確認感測串流，分片資料等待完整訊息處理。
            if spatialKeepAlive != nil, !message.isFragment,
                let values = BudsStatus.decodeSpatialQuaternion(message.payload)
            {
                onSpatialQuaternion?(values)
                // 首次收到感測資料時標記串流有效。
                if !spatialDataReceived { spatialDataReceived = true }
                // 感測資料已到達時同步追蹤連線狀態。
                if !status.spatialAttached { status.spatialAttached = true }
            }
            return
        }
        firmware.handle(message)
        let applied = status.apply(message, profile: connectedModel?.profile)
        // 完整裝置資訊成功解析後，才交給韌體服務確認安裝版本。
        if message.messageID == .debugGetAllData, applied { firmware.confirmInstalledVersion(status.softwareVersion) }
        // 有效自我測試回報結束等待，未通過 bit 仍由配置說明其意義。
        if message.messageID == .selfTest, applied {
            selfTestTimeout?.cancel()
            selfTestRunning = false
        }
        DiagnosticsLog.shared.log(
            "RX id=\(message.messageID.rawValue), applied=\(applied), bytes=\(message.payload.count), battery=\(String(describing: status.batteryLeft))/\(String(describing: status.batteryRight)), mode=\(status.noiseControlMode.rawValue), hold=\(String(describing: status.touchHoldLeft))/\(String(describing: status.touchHoldRight)), assistant=\(String(describing: status.touchAssistantLeft))/\(String(describing: status.touchAssistantRight))"
        )
        // 語音開關採獨立子命令回報，只有有效回報確認該操作。
        if message.messageID == .setVoiceCommands, pendingSettingID == .setVoiceCommands, applied {
            pendingSettingID = nil
            // 保留其他設定錯誤，同一語音命令的後續結果才可取代回饋。
            if commandNotice?.isError != true || failedSettingID == .setVoiceCommands {
                failedSettingID = nil
                commandNotice = .info(String(localized: "The earbuds replied to the setting."))
            }
        }
        // 韌體拒絕碼保留錯誤狀態，後來的傳輸完成不能覆蓋。
        if message.messageID == .resp, message.payload.count >= 2, message.payload[1] != 0 {
            // 只將已知設定命令的錯誤套用到設定回饋。
            guard let failed = MessageID(rawValue: message.payload[0]), failed.isSetting else { return }
            failedSettingID = failed
            // 錯誤對應目前等待命令時才清除等待狀態。
            if pendingSettingID?.rawValue == message.payload[0] { pendingSettingID = nil }
            commandNotice = .error(String(localized: "The earbuds rejected the setting.") + " (\(message.payload[1]))")
            return
        }
        // ACK 必須帶有結果且對應等待命令，才可判定該次操作。
        guard let pending = pendingSettingID, message.payload.count >= 2,
            message.payload[0] == pending.rawValue
        else { return }
        // ACK 的解析結果有效且對應待確認命令才更新回饋。
        if message.messageID == .acknowledgement && applied {
            pendingSettingID = nil
            // 避免成功 ACK 蓋掉其他命令的錯誤訊息。
            if commandNotice?.isError != true || failedSettingID == pending {
                failedSettingID = nil
                commandNotice = .info(String(localized: "The earbuds replied to the setting."))
            }
        } else if message.messageID == .resp {
            // 一般結果回覆與 ACK 使用各自的成功判定。
            pendingSettingID = nil
            // 一般回覆只更新同一操作的回饋，保留其他已知錯誤。
            if commandNotice?.isError != true || failedSettingID == pending {
                failedSettingID = nil
                commandNotice = .info(String(localized: "The earbuds accepted the setting."))
            }
        }
    }

    /// 載入目前裝置的九段自訂 EQ 偏好。
    private func loadCustomEqualizer() {
        // 保存的 EQ 必須有九段且各值有效，才載入目前裝置。
        if let saved = UserDefaults.standard.array(forKey: customEQKey) as? [Int],
            saved.count == 9, saved.allSatisfy({ (-10...10).contains($0) })
        {
            status.customEqualizerBands = saved
            return
        }
    }

    /// 實機模式保存目前裝置的候選 EQ 曲線。
    ///
    /// - Parameters:
    ///   - bands: 九段整數增益，各值使用 -10...10 範圍。
    private func saveCustomEqualizer(_ bands: [Int]) {
        // 示範資料不寫入系統偏好或啟動真實連線。
        guard !isDemo else { return }
        UserDefaults.standard.set(bands, forKey: customEQKey)
    }

}

// MARK: - 藍牙權限與電源事件

extension BluetoothManager: CBCentralManagerDelegate {
    /// 原生授權與電源事件交給 MainActor，停用時釋放控制通道與探索作業。
    ///
    /// - Parameters:
    ///   - central: CoreBluetooth 提供電源與授權狀態的管理實體。
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        Task { @MainActor in
            DiagnosticsLog.shared.log("CoreBluetooth state: \(state.rawValue)")
            // 藍牙電源與授權狀態決定是否開始掃描、連線或釋放通道。
            switch state {
            // 電源就緒後讀取配對清單，接續等待的掃描與自動連線。
            case .poweredOn:
                self.bluetoothReady = true
                self.refreshPairedDevices()
                // 電源就緒後執行先前等待的掃描要求。
                if self.pendingScan {
                    self.pendingScan = false
                    self.performScan()
                }
                // 已註冊自動連線時，電源就緒後再選擇目前音訊耳機。
                if self.autoConnectArmed {
                    self.armConnectNotifications()
                }
            // 授權未允許時停止掃描與連線，交由使用者調整系統權限。
            case .unauthorized:
                self.bluetoothReady = false
                let suppressed = self.suppressAutoConnect
                self.disconnect(deviceLink: false)
                self.suppressAutoConnect = suppressed
                self.stopScanning()
                self.isScanning = false
                self.pendingScan = false
                self.connectionError = String(
                    localized:
                        "Bluetooth permission denied. Allow this app under System Settings → Privacy & Security → Bluetooth."
                )
            // 電源關閉時停止控制通道與探索作業。
            case .poweredOff:
                self.bluetoothReady = false
                let suppressed = self.suppressAutoConnect
                self.disconnect(deviceLink: false)
                self.suppressAutoConnect = suppressed
                self.stopScanning()
                self.isScanning = false
                self.connectionError = String(localized: "Bluetooth is off. Please turn it on.")
            // 其他電源狀態保留等待或停用狀態，避免誤啟動連線。
            default:
                self.bluetoothReady = false
            }
        }
    }
}

// MARK: - 原生 SDP 完成事件

extension BluetoothManager: IOBluetoothDeviceAsyncCallbacks {
    /// 原生非同步協定要求名稱回呼，記錄結果，配對名稱仍由系統快照取得。
    ///
    /// - Parameters:
    ///   - device: 本次連線或服務探索的系統裝置，回呼需核對其身分與世代。
    ///   - result: 原生 API 回報碼，0 表示成功，其餘保留為錯誤資訊。
    nonisolated func remoteNameRequestComplete(_ device: IOBluetoothDevice!, status result: IOReturn) {
        DiagnosticsLog.shared.log("Native remote-name completion: \(result)")
    }

    /// 原生基礎連線事件只記錄結果，控制通道是否開啟由 RFCOMM 完成回呼決定。
    ///
    /// - Parameters:
    ///   - device: 本次連線或服務探索的系統裝置，回呼需核對其身分與世代。
    ///   - result: 原生 API 回報碼，0 表示成功，其餘保留為錯誤資訊。
    nonisolated func connectionComplete(_ device: IOBluetoothDevice!, status result: IOReturn) {
        DiagnosticsLog.shared.log("Native baseband completion: \(result)")
    }

    /// SDP 完成後依等待世代及注入 UUID 解讀服務，舊裝置事件不建立通道。
    ///
    /// - Parameters:
    ///   - device: 本次連線或服務探索的系統裝置，回呼需核對其身分與世代。
    ///   - result: 原生 API 回報碼，0 表示成功，其餘保留為錯誤資訊。
    @objc nonisolated func sdpQueryComplete(_ device: IOBluetoothDevice!, status result: IOReturn) {
        Task { @MainActor in
            // 只處理本服務等待的裝置，其他或已被取代的查詢不改動目前快照。
            guard let device, self.pendingSDPDevice === device else { return }
            let generation = self.pendingSDPGeneration
            self.pendingSDPDevice = nil
            self.pendingSDPGeneration = nil
            // SDP 結果須對應裝置、連線世代與等待狀態，避免接受過期回呼。
            guard self.isConnecting, self.connectedDevice === device, self.connectGeneration == generation,
                let model = self.connectedModel, let snapshot = DiscoveredDevice(device: device)
            else { return }
            // 原生完成結果與本機服務記錄共同決定是否開啟通道。
            if result == kIOReturnSuccess,
                let match = self.firstChannel(on: device, uuidStrings: model.serviceUUIDCandidates)
            {
                DiagnosticsLog.shared.log(
                    "SPP found after native SDP callback: \(match.string) → rfcomm \(match.channel)")
                self.connectViaRFCOMM(device: snapshot, model: model, channelID: match.channel)
            } else {
                // SDP 查詢失敗交回共用連線失敗流程。
                DiagnosticsLog.shared.log("SDP failed: \(result), services: \(self.serviceRecordSummary(of: device))")
                self.handleConnectFailure(device: snapshot, model: model)
            }
        }
    }
}

// MARK: - RFCOMM 通道事件

extension BluetoothManager: IOBluetoothRFCOMMChannelDelegate {
    /// 原生開啟回呼驗證通道身分，成功初始化，失敗依機型快照走共用重試。
    ///
    /// - Parameters:
    ///   - rfcommChannel: IOBluetooth 提供的通道，須對應目前持有的控制通道。
    ///   - error: 原生 API 回報碼，0 表示成功，其餘保留為錯誤資訊。
    nonisolated func rfcommChannelOpenComplete(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        status error: IOReturn
    ) {
        Task { @MainActor in
            // 舊嘗試的回呼不能初始化或關閉目前的控制通道。
            guard self.rfcommChannel === rfcommChannel else { return }
            DiagnosticsLog.shared.log("RFCOMM open completion: \(error)")
            // 原生結果碼分辨失敗與成功，逾時監控處理完全沒有回呼的情況。
            guard error == kIOReturnSuccess else {
                // RFCOMM 開啟失敗時，使用仍有效的裝置與機型快照決定重試。
                if let device = self.connectedDevice, let model = self.connectedModel,
                    let snapshot = DiscoveredDevice(device: device)
                {
                    self.handleConnectFailure(device: snapshot, model: model)
                }
                return
            }
            self.markConnected()
        }
    }

    /// 先複製原生 callback 指標範圍，再切回 MainActor 組框，舊通道資料略過。
    ///
    /// - Parameters:
    ///   - rfcommChannel: IOBluetooth 提供的通道，須對應目前持有的控制通道。
    ///   - dataPointer: IOBluetooth 借用的資料指標，返回原生回呼前先複製內容。
    ///   - dataLength: 原生回報的資料長度，單位為 bytes。
    nonisolated func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        // 原生資料指標與長度有效後才複製，避免跨執行緒使用借用記憶體。
        guard let dataPointer, dataLength > 0 else { return }
        let receivedData = Data(bytes: dataPointer, count: dataLength)
        Task { @MainActor in
            // 舊通道的完成或資料事件不能寫入目前連線世代。
            guard self.rfcommChannel === rfcommChannel else { return }
            self.handleReceivedData(receivedData)
        }
    }

    /// 依 refcon 釋放完成的原生 buffer，傳輸結果與耳機 ACK 分開呈現。
    ///
    /// - Parameters:
    ///   - channel: IOBluetooth 提供的通道，須對應目前持有的控制通道。
    ///   - refcon: 寫入時附帶的原生資料識別，供完成回呼釋放對應 buffer。
    ///   - result: 原生 API 回報碼，0 表示成功，其餘保留為錯誤資訊。
    nonisolated func rfcommChannelWriteComplete(
        _ channel: IOBluetoothRFCOMMChannel!, refcon: UnsafeMutableRawPointer!, status result: IOReturn
    ) {
        // 寫入回呼必須攜帶原始 buffer 識別，才可安全釋放資料。
        guard let refcon else { return }
        let key = UInt(bitPattern: refcon)
        Task { @MainActor in
            // 舊通道的完成或資料事件不能寫入目前連線世代。
            guard self.rfcommChannel === channel,
                let buffer = self.pendingWrites.removeValue(forKey: key)
            else { return }
            DiagnosticsLog.shared.log("TX complete id=\(buffer.messageID.rawValue), result=\(result)")
            // 傳輸完成僅更新目前等待的設定命令。
            guard self.pendingSettingID == buffer.messageID else { return }
            // 系統接受寫入只代表傳輸完成，耳機確認由 ACK 決定。
            if result == kIOReturnSuccess {
                // 傳輸成功保留既有耳機錯誤，避免較晚回呼覆蓋失敗結果。
                if self.commandNotice?.isError != true {
                    self.commandNotice = .info(String(localized: "Setting sent."))
                }
            } else {
                // 系統寫入失敗時回報傳輸錯誤，保留與耳機確認的區別。
                self.failedSettingID = buffer.messageID
                self.commandNotice = .error(String(localized: "Bluetooth transmission failed. Reconnect your earbuds."))
            }
        }
    }

    /// 當前通道關閉清除作業快照，韌體服務分辨預期重啟與意外中斷。
    ///
    /// - Parameters:
    ///   - rfcommChannel: IOBluetooth 提供的通道，須對應目前持有的控制通道。
    nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        DiagnosticsLog.shared.log("rfcomm channel closed")
        Task { @MainActor in
            // 舊通道的完成或資料事件不能寫入目前連線世代。
            guard self.rfcommChannel === rfcommChannel else { return }
            // 通道關閉先通知韌體服務，再停止追蹤與清除控制快照。
            self.firmware.connectionLost()
            self.spatialKeepAlive?.cancel()
            self.spatialKeepAlive = nil
            self.spatialPreviousEnabled = nil
            self.spatialDataReceived = false
            self.selfTestTimeout?.cancel()
            self.selfTestRunning = false
            self.isConnected = false
            self.rfcommChannel = nil
            self.pendingWrites.removeAll()
            self.failedSettingID = nil
            self.streamDecoder = SppStreamDecoder()
            self.pendingSettingID = nil
            self.status = BudsStatus()
        }
    }
}

// MARK: - 附近裝置探索事件

extension BluetoothManager: IOBluetoothDeviceInquiryDelegate {
    /// 原生探索只接收有效裝置快照，同一探索作業與位址保留一筆。
    ///
    /// - Parameters:
    ///   - sender: IOBluetooth 提供的目前探索作業。
    ///   - device: 本次連線或服務探索的系統裝置，回呼需核對其身分與世代。
    nonisolated func deviceInquiryDeviceFound(
        _ sender: IOBluetoothDeviceInquiry!,
        device: IOBluetoothDevice!
    ) {
        // 探索回呼沒有裝置時，忽略空事件。
        guard let device else { return }
        // 裝置需有有效位址與候選資格，才能加入探索結果。
        guard let discovered = DiscoveredDevice(device: device) else { return }
        Task { @MainActor in
            // 停止或被取代的探索回呼不更動目前裝置清單。
            guard self.inquiry === sender else { return }
            // 同一裝置位址只保存一筆，重複探索回呼不增加清單。
            if !self.discoveredDevices.contains(where: { $0.id == discovered.id }) {
                self.discoveredDevices.append(discovered)
            }
        }
    }

    /// 完成或取消探索釋放 inquiry，未主動取消的錯誤保留系統結果碼。
    ///
    /// - Parameters:
    ///   - sender: IOBluetooth 提供的目前探索作業。
    ///   - error: 原生 API 回報碼，0 表示成功，其餘保留為錯誤資訊。
    ///   - aborted: 探索是否由使用者或服務主動取消。
    nonisolated func deviceInquiryComplete(
        _ sender: IOBluetoothDeviceInquiry!,
        error: IOReturn,
        aborted: Bool
    ) {
        Task { @MainActor in
            // 停止或被取代的探索回呼不更動目前裝置清單。
            guard self.inquiry === sender else { return }
            self.isScanning = false
            self.inquiry = nil
            // 非使用者取消的探索失敗才顯示錯誤。
            if error != kIOReturnSuccess && !aborted {
                self.connectionError = String(localized: "Nearby discovery failed.") + " (\(error))"
            }
        }
    }
}
