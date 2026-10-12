import CoreAudio
import Foundation

/// 目前系統輸出裝置的主音量或立體聲聲道音量。
@Observable @MainActor
final class AudioOutputController {
    // CoreAudio 通知在專用序列 queue 交接，可觀察快照維持 MainActor。
    private let listenerQueue = DispatchQueue(label: "dev.local.galaxybudscontrol.audio-events")

    // MARK: - 輸出快照與監聽狀態
    // 系統音量快照與錯誤由此服務更新，音量使用 0...1 比例。
    private(set) var volume: Double = 0
    private(set) var available = false
    private(set) var outputName = ""
    private(set) var errorText: String?
    private var device = AudioDeviceID(0)
    private var elements: [AudioObjectPropertyElement] = []
    private var channelLevels: [Float32] = []

    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress)] = []
    private var propertyListener: AudioObjectPropertyListenerBlock?
    private var notificationRefresh: Task<Void, Never>?

    // MARK: - 監聽生命週期

    /// 系統輸出與音量變更直接通知主執行緒，停止時移除相同的 callback。
    func startObserving() {
        // 原生 listener 只註冊一次，重複啟動共用現有監聽。
        guard propertyListener == nil else { return }
        propertyListener = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                // 已停止監聽或已有通知合併作業時不建立另一份刷新。
                guard let self, self.propertyListener != nil, self.notificationRefresh == nil else { return }
                // 一輪連續按鍵合併通知；CoreAudio callback 不等待主執行緒。
                self.notificationRefresh = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(10))
                    // 被取消或擁有者已釋放的合併作業不再刷新系統快照。
                    guard let self, !Task.isCancelled else { return }
                    self.refresh()
                    self.notificationRefresh = nil
                }
            }
        }
        refresh()
    }

    /// 停止合併中的通知並移除相同 callback，結束服務持有的監聽。
    func stopObserving() {
        notificationRefresh?.cancel()
        notificationRefresh = nil
        // 停止前未註冊 listener 時，不向 CoreAudio 移除未知 callback。
        guard let propertyListener else { return }
        // 移除每個已註冊的原生 listener，使用同一 callback 與位址。
        for (object, var address) in listeners {
            AudioObjectRemovePropertyListenerBlock(object, &address, listenerQueue, propertyListener)
        }
        listeners.removeAll()
        self.propertyListener = nil
    }

    // MARK: - 系統輸出與音量

    /// 讀取預設輸出與可寫入聲道，固定音量裝置維持停用。
    func refresh() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var output = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        available = false
        outputName = ""
        // 預設輸出不存在或讀取失敗時維持停用控制，避免寫入裝置 0。
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                0, nil, &size, &output) == noErr, output != 0
        else { return }
        // 換到新輸出裝置後清除舊裝置的寫入錯誤。
        if device != output { errorText = nil }
        device = output
        address.mSelector = kAudioObjectPropertyName
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        // 裝置名稱由 CoreAudio 取得，失敗保持空字串。
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr {
            outputName = name?.takeRetainedValue() as String? ?? ""
        }
        // 每次重新建立可寫聲道清單，避免沿用上一個輸出裝置。
        elements = []
        var levels: [Float32] = []
        // 依主聲道及左右聲道查詢可寫音量，保留有效的聲道元素。
        for element: AudioObjectPropertyElement in [0, 1, 2] {
            address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var writable: DarwinBoolean = false
            var level: Float32 = 0
            size = UInt32(MemoryLayout<Float32>.size)
            // 原生主音量或聲道屬性必須存在、可寫且回報有限值。
            guard AudioObjectHasProperty(device, &address),
                AudioObjectIsPropertySettable(device, &address, &writable) == noErr, writable.boolValue,
                AudioObjectGetPropertyData(device, &address, 0, nil, &size, &level) == noErr,
                level.isFinite
            else { continue }
            elements.append(element)
            levels.append(level)
            // 裝置有主音量時使用原生 master，避免重複寫入左右聲道。
            if element == 0 { break }
        }
        // 非 master 的單一聲道不足以代表立體聲輸出，保留停用狀態。
        if elements.count == 1 && elements[0] != 0 {
            elements = []
            return
        }
        // 有完整可寫屬性才公開可用音量，聲道比例保存供後續調整。
        if !levels.isEmpty {
            channelLevels = levels
            volume = Double(levels.max() ?? 0)
            available = true
        }
        // 只有已啟動的服務維護 listener，手動 refresh 保留唯讀路徑。
        if let propertyListener {
            // 系統輸出變更與有效聲道音量都需要原生 listener。
            let requested =
                [
                    (
                        AudioObjectID(kAudioObjectSystemObject),
                        AudioObjectPropertyAddress(
                            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                    )
                ]
                + elements.map {
                    (
                        device,
                        AudioObjectPropertyAddress(
                            mSelector: kAudioDevicePropertyVolumeScalar,
                            mScope: kAudioDevicePropertyScopeOutput, mElement: $0)
                    )
                }
            let unchanged =
                requested.count == listeners.count
                && zip(requested, listeners).allSatisfy { current, installed in
                    current.0 == installed.0 && current.1.mSelector == installed.1.mSelector
                        && current.1.mScope == installed.1.mScope && current.1.mElement == installed.1.mElement
                }
            // 音量通知只讀值，只有輸出裝置或聲道變更才重新註冊。
            guard !unchanged else { return }
            // listener 集合有變化時，先移除舊集合再註冊新輸出。
            for (object, var address) in listeners {
                AudioObjectRemovePropertyListenerBlock(object, &address, listenerQueue, propertyListener)
            }
            listeners = requested.filter { object, address in
                var address = address
                return AudioObjectAddPropertyListenerBlock(object, &address, listenerQueue, propertyListener) == noErr
            }
        }
    }

    /// 依既有聲道比例送出音量，失敗時保留錯誤並重新讀取實際值。
    ///
    /// - Parameters:
    ///   - level: 系統音量比例，範圍為 0...1，寫入時保留聲道比例。
    func setVolume(_ level: Double) {
        // 外部要求須有限且裝置可寫，值域限制在 CoreAudio 的 0...1。
        guard available, level.isFinite else { return }
        // 目標音量限制於 0...1，先取得既有最高聲道值作為比例基準。
        let requested = Float32(max(0, min(1, level)))
        let previous = channelLevels.max() ?? 0
        var updated: [Float32] = []
        // 各聲道依原比例調整，保持左右平衡。
        for (index, element) in elements.enumerated() {
            var value = requested * (previous > 0 ? channelLevels[index] / previous : 1)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            let result = AudioObjectSetPropertyData(
                device, &address, 0, nil,
                UInt32(MemoryLayout<Float32>.size), &value)
            // 寫入任一聲道失敗時重讀實際值，候選值不冒充系統結果。
            guard result == noErr else {
                errorText = String(localized: "Could not change the system volume.") + " (\(result))"
                refresh()
                return
            }
            updated.append(value)
        }
        channelLevels = updated
        volume = Double(requested)
        errorText = nil
    }
}
