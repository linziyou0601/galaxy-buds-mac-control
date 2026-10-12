import Foundation

/// 耳機回報與已送出候選設定的值型別快照。
struct BudsStatus: Sendable {
    // MARK: - 電量與配戴

    /// nil 表示尚未收到有效百分比，0 表示有效的零電量。
    var batteryLeft: Int?
    var batteryRight: Int?
    /// 盒子電量的 0 與 FF 表示未提供資料。
    var batteryCase: Int?
    var isLeftWearing = false
    var isRightWearing = false
    var deviceColorID: Int?
    /// 已收到有效模式回報，控制項才可使用。
    var hasControlStatus = false

    // MARK: - 音效與降噪

    var noiseControlMode: NoiseControlMode = .off
    /// ANC 以 0 起算，實際上限由機型配置決定。
    var ancLevel = 0
    var ambientSoundVolume = 0
    var ncWithOneEarbud = false
    var ambientCustomEnabled = false
    /// 自訂環境音左右等級從 0 起算，上限由機型配置提供。
    var ambientCustomLeft = 1
    var ambientCustomRight = 1
    var ambientCommandTail: [UInt8]?
    var detectConversations = false
    /// 0、1、2 分別代表 5、10、15 秒。
    var detectConversationsDuration = 0
    var sidetone = false
    var ambientDuringCalls = false

    // MARK: - 手勢與 EQ

    /// nil 表示尚未回報或目前動作不在實作的協定表中。
    // 長按基本碼與助理提供者分開保存，nil 表示尚未取得有效回報。
    var touchHoldLeft: TouchHoldAction?
    var touchHoldRight: TouchHoldAction?
    var touchHoldBaseLeft: UInt8?
    var touchHoldBaseRight: UInt8?
    var touchAssistantSupported = false
    var touchAssistantLeft: UInt8?
    var touchAssistantRight: UInt8?
    var noiseCycleLeft: NoiseControlCycle?
    var noiseCycleRight: NoiseControlCycle?
    var touchpadLocked = false
    /// nil 表示尚未收到完整的七個操作旗標。
    var gestureEnabled: [Bool]?
    /// 命令尾端為燈效與進階長按值，nil 表示必要欄位尚未完整回報。
    var touchCommandTail: [UInt8]?
    var headGestureMask: UInt8?
    var lastHeadGesture: Bool?
    var additionalSettings: [AdditionalSetting: Bool] = [:]
    /// 0...32，16 為左右置中，nil 表示尚未回報。
    var stereoBalance: Int?
    var equalizerPreset: EqualizerPreset = .normal
    var customEqualizerBands: [Int]?
    /// 空集合表示尚未收到完整的預設 EQ 曲線。
    var presetEqualizerCurves: [[Int]] = []

    // MARK: - 識別與密合度

    // 版本與序號保存耳機回報文字，空字串表示尚未取得資料。
    var softwareVersion = ""
    var serialLeft = ""
    var serialRight = ""
    var serialCase = ""
    var caseSoftwareVersion = ""
    var fitLeft: FitResult = .unknown
    var fitRight: FitResult = .unknown
    // 診斷遮罩與追蹤連線獨立於 Mac 音訊引擎，未回報值維持 optional。
    var selfTestMask: UInt32?
    var spatialAttached = false
    var spatialAudioEnabled: Bool?

    /// 密合度回報結果碼。
    enum FitResult: Int, Sendable {
        case bad = 0
        case good = 1
        case failed = 2
        case unknown = 99
    }

    /// 解析已通過封包 CRC 的 payload，短資料不覆寫既有快照。
    ///
    /// - Parameters:
    ///   - message: 有效且已通過 SPP CRC 的訊息，依命令解析或分派。
    ///   - profile: 目前裝置的已驗證機型配置，決定欄位位置、能力與範圍。
    /// - Returns: 有效訊息已解析時為 true；短資料、分片或未知訊息為 false。
    @discardableResult
    mutating func apply(_ message: SppMessage, profile: DeviceProfile? = nil) -> Bool {
        // 韌體片段不是狀態快照，交給更新服務處理。
        guard !message.isFragment else { return false }
        let payload = Data(message.payload)
        // 命令分派採共用協定 ID，機型欄位差異由 profile 注入。
        switch message.messageID {
        // 基本狀態包含耳機電量，配戴與盒子欄位按實際長度讀取。
        case .statusUpdated:
            // 基本電量快照至少需要表頭與兩耳電量，短資料保留既有狀態。
            guard payload.count >= 3 else { return false }
            batteryLeft = battery(payload[1])
            batteryRight = battery(payload[2])
            // 配戴欄位存在時才解析，舊版短回報仍可更新電量。
            if payload.count > 5 { applyPlacement(payload[5]) }
            // 盒子欄位以 0 表示未提供，與耳機有效零電量分開判讀。
            if payload.count > 6 { batteryCase = payload[6] == 0 ? nil : battery(payload[6]) }
        // 延伸快照由共用格式及機型配置的尾端位置解析。
        case .extendedStatusUpdated:
            return applyExtendedStatus(payload, profile: profile)
        // 設定 ACK 需驗證命令及回傳值，候選狀態才可成為已回報值。
        case .acknowledgement:
            return applyAcknowledgement(payload, profile: profile)
        // 原生模式事件必須對應已知列舉，未知值保留上一份快照。
        case .noiseControlsUpdate:
            // 噪音事件只接受已知模式碼，未知值不覆寫快照。
            if let value = payload.first, let mode = NoiseControlMode(rawValue: Int(value)) {
                noiseControlMode = mode
                hasControlStatus = true
            }
        // 識別回報前 2 bytes 是表頭，後續 20 bytes 包含韌體版本字串。
        case .debugGetAllData:
            // 版本回報必須包含完整表頭與版本字串。
            guard payload.count >= 22 else { return false }
            softwareVersion = ascii(Data(payload[2..<22]))
        // 左右耳各提供 11-byte ASCII 序號，資料不足不覆寫。
        case .debugSerialNumber:
            // 兩耳序號資料都完整後才更新，避免顯示截斷識別資料。
            guard payload.count >= 22 else { return false }
            serialLeft = ascii(Data(payload[0..<11]))
            serialRight = ascii(Data(payload[11..<22]))
        // 充電盒的韌體與序號長度由當前機型配置注入。
        case .cradleSerialNumber:
            // 充電盒欄位長度依機型注入，缺少配置時保留未知。
            guard let profile else { return false }
            let split = profile.cradleVersionLength
            let end = split + profile.cradleSerialLength
            // 回報長度足以容納完整版本與序號後才切分資料。
            guard payload.count >= end else { return false }
            caseSoftwareVersion = ascii(Data(payload[0..<split]))
            serialCase = ascii(Data(payload[split..<end]))
        // 語音命令只有子命令 1 是布林開關，其他子命令保留給各自流程。
        case .setVoiceCommands:
            // 語音子命令 1 才表示開關，且只接受 0／1 回報。
            guard payload.count >= 2, payload[0] == 1, payload[1] <= 1 else { return false }
            additionalSettings[.voiceCommands] = payload[1] == 1
        // 已配置且啟用的偵測事件，依耳機設定的肯定方向轉換。
        case .headGestures:
            // 事件需有頭部動作能力、有效方向及啟用遮罩，才轉成肯定或否定。
            guard profile?.features.contains(.headGestures) == true, let value = payload.first, value <= 1,
                let mask = headGestureMask, mask & 1 != 0
            else { return false }
            lastHeadGesture = mask & 2 != 0 ? value == 1 : value == 0
        // 四個 little-endian bytes 組成配置診斷項目使用的位元遮罩。
        case .selfTest:
            // 自我測試需有機型能力與完整 32-bit 遮罩。
            guard profile?.features.contains(.hardwareDiagnostics) == true, payload.count >= 4 else { return false }
            selfTestMask = (0..<4).reduce(UInt32(0)) { $0 | UInt32(payload[$1]) << ($1 * 8) }
        // 控制碼 2、3 分別表示感測連上與離開，不代表音訊引擎狀態。
        case .spatialAudioControl:
            // 缺少感測控制碼時，追蹤狀態維持原值。
            guard let code = payload.first else { return false }
            // 控制碼 2 與 3 分別表示追蹤連上與離開，其他值保留原狀。
            if code == 2 { spatialAttached = true } else if code == 3 { spatialAttached = false }
        // 左右耳結果碼各自解析，未知碼保持 unknown。
        case .checkFitResult:
            // 左右耳密合度結果須同時存在，未知列舉另以 unknown 表示。
            guard payload.count >= 2 else { return false }
            fitLeft = FitResult(rawValue: Int(payload[0])) ?? .unknown
            fitRight = FitResult(rawValue: Int(payload[1])) ?? .unknown
        // 完整曲線格式與增益驗證集中在同一個解析邊界。
        case .customEqualizeRecv:
            return applyEqualizerCurves(payload)
        // 未知命令不改寫快照，也不回報解析成功。
        default:
            return false
        }
        return true
    }

    /// 感測事件的 int16 little-endian 四元數，比例為 1/10000。
    ///
    /// - Parameters:
    ///   - payload: 已接收的原始位元組，格式、長度與欄位有效性由此解析入口檢查。
    /// - Returns: 依 x、y、z、w 排列的四元數；短資料或無效格式時為 nil。
    static func decodeSpatialQuaternion(_ payload: Data) -> [Double]? {
        // GRV 事件碼 32 後接四個 int16，其他事件與短資料拒絕解碼。
        guard payload.count >= 10, payload[0] == 32 else { return nil }
        let values = (0..<4).map { index -> Double in
            let offset = 1 + index * 2
            return Double(Int16(bitPattern: UInt16(payload[offset]) | UInt16(payload[offset + 1]) << 8)) / 10000
        }
        let norm = values.reduce(0) { $0 + $1 * $1 }
        // 有限且接近單位長度的姿態才可作為音場方向。
        guard norm > 0.1, norm < 2 else { return nil }
        return values.map { $0 / sqrt(norm) }
    }

    /// ACK 帶回設定的實際值；資料不足或未支援的 ACK 不更新快照。
    ///
    /// - Parameters:
    ///   - payload: 已接收的原始位元組，格式、長度與欄位有效性由此解析入口檢查。
    ///   - profile: 目前裝置的已驗證機型配置，決定欄位位置、能力與範圍。
    /// - Returns: 已知 ACK 與有效值完成更新時為 true，無效資料保留快照並回傳 false。
    private mutating func applyAcknowledgement(_ payload: Data, profile: DeviceProfile?) -> Bool {
        // 第一個 byte 是已回覆命令，第二個才是其設定值。
        guard payload.count >= 2, let command = MessageID(rawValue: payload[0]) else { return false }
        let value = Int(payload[1])
        // 複合音效命令一次回傳兩個開關，兩欄完整才更新。
        if command == .setBoostLoudness {
            // 兩個複合音效開關都完整且有效後才一起更新。
            guard payload.count >= 3, payload[1] <= 1, payload[2] <= 1 else { return false }
            additionalSettings[.voiceBoost] = payload[1] == 1
            additionalSettings[.volumeNormalization] = payload[2] == 1
            return true
        }
        // 配置列出的單一布林命令共用解析，語音子命令維持獨立格式。
        if let setting = profile?.additionalSettings.first(where: { $0.command == command }), setting != .voiceCommands,
            value <= 1
        {
            additionalSettings[setting] = setting.isInverted ? value == 0 : value == 1
            return true
        }
        // 固定協定語意以有限列舉分派，不依耳機名稱或手機資訊判斷。
        switch command {
        // 空間音訊開關接受布林回報，並與感測器連線狀態分開。
        case .setSpatialAudio:
            // 空間音訊開關僅接受布林碼，超限值不套用。
            guard value <= 1 else { return false }
            spatialAudioEnabled = value == 1
        // 左右輪替必須各含至少兩個已知模式，完整 ACK 才覆寫。
        case .setTouchAndHoldNoiseControls:
            // 左右輪替遮罩都需包含至少兩個已知模式。
            guard payload.count >= 3, payload[1] <= 15, payload[2] <= 15,
                let left = cycle(payload[1]), let right = cycle(payload[2])
            else { return false }
            noiseCycleLeft = left
            noiseCycleRight = right
        // 噪音模式只接受已知協定碼，有效回報開啟操作能力。
        case .noiseControls:
            // 模式 ACK 必須對應已知噪音模式，才更新控制狀態。
            guard let mode = NoiseControlMode(rawValue: value) else { return false }
            noiseControlMode = mode
            hasControlStatus = true
        // ANC 的 0 起算索引須落在機型配置的段數內。
        case .noiseReductionLevel:
            // ANC 索引須落在目前機型配置的段數內。
            guard let profile, value < profile.ancSteps else { return false }
            ancLevel = value
        // 環境音上限從當前機型取得，超限值保留原狀。
        case .ambientVolume:
            // 環境音 ACK 上限依機型配置判斷。
            guard let profile, value <= profile.ambientMax else { return false }
            ambientSoundVolume = value
        // 語音偵測的布林值只接受 0 與 1。
        case .setDetectConversations:
            // 語音偵測開關只接受 0／1。
            guard value <= 1 else { return false }
            detectConversations = value == 1
        // 持續時間索引 0、1、2 對應共用協定的 5、10、15 秒。
        case .setDetectConversationsDuration:
            // 持續時間索引限制為三種已知秒數。
            guard value <= 2 else { return false }
            detectConversationsDuration = value
        // 單耳降噪設定使用一般布林回報。
        case .setAncWithOneEarbud:
            // 單耳降噪 ACK 只接受布林回報。
            guard value <= 1 else { return false }
            ncWithOneEarbud = value == 1
        // 通話時聽見自身聲音的開關使用一般布林回報。
        case .setSidetone:
            // 自身聲音 ACK 只接受布林回報。
            guard value <= 1 else { return false }
            sidetone = value == 1
        // 通話環境音使用反向布林，0 表示啟用。
        case .setCallPathControl:
            // 通話環境音的反向布林仍只接受 0／1。
            guard value <= 1 else { return false }
            ambientDuringCalls = value == 0
        // 平衡值域為 0...32，16 表示左右置中。
        case .stereoBalance:
            // 左右平衡超過 0...32 時保留已知值。
            guard value <= 32 else { return false }
            stereoBalance = value
        // 已配置且啟用的偵測事件，依耳機設定的肯定方向轉換。
        case .headGestures:
            // 頭部設定遮罩只能使用已知三個位元，且機型必須支援。
            guard value <= 7, profile?.features.contains(.headGestures) == true else { return false }
            headGestureMask = UInt8(value)
        // 整體鎖定使用反向布林，完整後段才更新七個手勢旗標。
        case .lockTouchpad:
            // 整體觸控鎖定只接受 0／1，避免未知碼被當成啟用。
            guard value <= 1 else { return false }
            touchpadLocked = value == 0
            // 完整七個手勢旗標都有效，才取代個別操作快照。
            if payload.count >= 9, payload[2..<9].allSatisfy({ $0 <= 1 }) {
                gestureEnabled = payload[2..<9].map { $0 == 1 }
            }
        // 左右基本動作與可選助理類型分開保存，解讀交給注入配置。
        case .setTouchpadOption:
            // 左右耳基本長按碼都存在後才更新。
            guard payload.count >= 3 else { return false }
            touchHoldBaseLeft = payload[1]
            touchHoldBaseRight = payload[2]
            // 助理位置與最低 revision 都由機型配置決定。
            if touchAssistantSupported, payload.count >= 5 {
                touchAssistantLeft = payload[3]
                touchAssistantRight = payload[4]
            }
            applyTouchHold(profile: profile)
        // 自訂左右等級由配置驗證，三個附加欄位完整時才保存。
        case .customizeAmbientSound:
            // 自訂環境音需保留完整尾端欄位，左右等級由配置驗證。
            guard let profile, payload.count >= 7, value <= 1,
                Int(payload[2]) <= profile.ambientCustomMax,
                Int(payload[3]) <= profile.ambientCustomMax
            else { return false }
            ambientCustomEnabled = value == 1
            ambientCustomLeft = Int(payload[2])
            ambientCustomRight = Int(payload[3])
            ambientCommandTail = Array(payload[4...6])
        // 自訂模式的 wire 值是 7，已知預設沿用其列舉碼。
        case .equalizer:
            // 自訂 EQ 使用獨立協定碼 7。
            if value == 7 {
                equalizerPreset = .custom
            } else if let preset = EqualizerPreset(rawValue: value), preset != .custom {
                // 其他 EQ 碼須對應已知預設，不能重複當成自訂模式。
                equalizerPreset = preset
            } else {
                // 未知 EQ 碼不更新已知曲線與預設。
                return false
            }
        // 未知命令不改寫快照，也不回報解析成功。
        default:
            return false
        }
        // 完整 ACK 才提供燈效及進階長按尾段，短回報保留有效快照。
        if command == .lockTouchpad, payload.count >= 11 { touchCommandTail = Array(payload[9..<11]) }
        return true
    }

    /// 擷取 Buds3/4 Pro 延伸狀態，未知列舉碼保留前次有效值。
    ///
    /// - Parameters:
    ///   - payload: 已接收的原始位元組，格式、長度與欄位有效性由此解析入口檢查。
    ///   - profile: 目前裝置的已驗證機型配置，決定欄位位置、能力與範圍。
    /// - Returns: 有效核心快照已套用時為 true，短核心回報為 false。
    private mutating func applyExtendedStatus(_ payload: Data, profile: DeviceProfile?) -> Bool {
        // 共用核心需要至少 14 bytes，尾端各功能按自身邊界讀取。
        guard payload.count >= 14 else { return false }
        batteryLeft = battery(payload[2])
        batteryRight = battery(payload[3])
        batteryCase = payload[7] == 0 ? nil : battery(payload[7])
        applyPlacement(payload[6])
        // wire 值 7 代表自訂 EQ，其他碼必須命中已知預設。
        if payload[9] == 7 {
            equalizerPreset = .custom
        } else if let preset = EqualizerPreset(rawValue: Int(payload[9])), preset != .custom {
            // 非自訂 EQ 僅採用已知預設碼。
            equalizerPreset = preset
        }
        // 未知噪音模式不冒充關閉，也不開啟未確認的控制能力。
        if let mode = NoiseControlMode(rawValue: Int(payload[12])) {
            noiseControlMode = mode
            hasControlStatus = true
        }
        // 完整兩個色碼 bytes 組成 little-endian UInt16。
        if payload.count >= 16 { deviceColorID = Int(payload[14]) | Int(payload[15]) << 8 }
        touchpadLocked = payload[10] & 0x80 == 0
        gestureEnabled = TouchGesture.allCases.map { payload[10] & (1 << $0.statusBit) != 0 }
        // 平衡欄位超限或缺失時保留已知值。
        if payload.count > 25, payload[25] <= 32 { stereoBalance = Int(payload[25]) }
        // 只有機型列出的進階設定才解析各自的 offset。
        for setting in profile?.additionalSettings ?? [] {
            // 進階開關的機型 offset 必須存在於已驗證配置。
            guard let offset = profile?.additionalStatusOffsets[setting.rawValue] else { continue }
            // 缺失與非布林資料保留未知，反向語意由設定型別提供。
            if payload.count > offset, payload[offset] <= 1 {
                additionalSettings[setting] = setting.isInverted ? payload[offset] == 0 : payload[offset] == 1
            }
        }
        // 不同機型的操作尾段位置由 JSON 提供，nil 表示保留欄位。
        if let offsets = profile?.touchTailOffsets {
            let tail: [UInt8] = offsets.compactMap { offset in
                // 配置中的 nil 對應機型未提供的保留欄位，命令以 1 表示。
                guard let offset else { return 1 }
                return payload.count > offset ? payload[offset] : nil
            }
            // 命令要求完整兩個尾端 bytes，部分回報不能覆寫。
            if tail.count == 2 { touchCommandTail = tail }
        }
        touchHoldBaseLeft = payload[11] >> 4
        touchHoldBaseRight = payload[11] & 0x0F
        touchAssistantSupported =
            profile?.assistantStatusOffset != nil && Int(payload[0]) >= (profile?.assistantMinimumRevision ?? 255)
        // 助理位置與最低 revision 都由機型配置決定。
        if touchAssistantSupported, let offset = profile?.assistantStatusOffset, payload.count > offset {
            touchAssistantLeft = payload[offset] >> 4
            touchAssistantRight = payload[offset] & 0x0F
        } else {
            // 助理欄位未提供或 revision 不支援時，清除助理提供者快照。
            touchAssistantLeft = nil
            touchAssistantRight = nil
        }
        applyTouchHold(profile: profile)
        // 韌體空間音訊設定與 Mac 音訊處理狀態分開保存。
        if payload.count > 35, payload[35] <= 1 { spatialAudioEnabled = payload[35] == 1 }
        // 左右輪替分別占高、低 nibble，共用至少兩個模式的驗證。
        if payload.count > 21 {
            noiseCycleLeft = cycle(payload[21] >> 4)
            noiseCycleRight = cycle(payload[21] & 0x0F)
        }
        // 後續欄位逐一檢查長度與範圍，未出現的欄位維持原值。
        if let profile, payload.count > 23, Int(payload[23]) <= profile.ambientMax {
            ambientSoundVolume = Int(payload[23])
        }
        // ANC 欄位存在且索引在配置範圍內才更新。
        if let profile, payload.count > 24, Int(payload[24]) < profile.ancSteps { ancLevel = Int(payload[24]) }
        // 語音偵測欄位存在且為布林值才更新。
        if payload.count > 26, payload[26] <= 1 { detectConversations = payload[26] == 1 }
        // 持續時間僅接受已知的 0、1、2 索引。
        if payload.count > 27, payload[27] <= 2 { detectConversationsDuration = Int(payload[27]) }
        // 單耳降噪欄位以有效布林回報更新。
        if payload.count > 28, payload[28] <= 1 { ncWithOneEarbud = payload[28] == 1 }
        // 自訂環境音啟用狀態以有效布林回報更新。
        if payload.count > 29, payload[29] <= 1 { ambientCustomEnabled = payload[29] == 1 }
        // 高、低 nibble 是自訂左右等級，上限沿用已注入配置。
        if let profile, payload.count > 30 {
            let left = Int(payload[30] >> 4)
            let right = Int(payload[30] & 0x0F)
            // 左耳等級須符合目前機型上限。
            if left <= profile.ambientCustomMax { ambientCustomLeft = left }
            // 右耳等級獨立驗證，左耳有效不代表右耳也有效。
            if right <= profile.ambientCustomMax { ambientCustomRight = right }
        }
        // 三個附加環境音欄位必須完整，寫回時才能保留其他原值。
        if let offsets = profile?.ambientCommandTailOffsets, offsets.allSatisfy({ payload.count > $0 }) {
            ambientCommandTail = offsets.map { payload[$0] }
        }
        // 自身聲音欄位只接受有效布林回報。
        if payload.count > 33, payload[33] <= 1 { sidetone = payload[33] == 1 }
        // 通話環境音以反向布林解讀，0 代表啟用。
        if payload.count > 34, payload[34] <= 1 { ambientDuringCalls = payload[34] == 0 }
        return true
    }

    /// Buds3 新協定用助理欄位覆蓋原動作，Buds4 使用獨立數位助理動作碼。
    ///
    /// - Parameters:
    ///   - profile: 目前裝置的已驗證機型配置，決定欄位位置、能力與範圍。
    private mutating func applyTouchHold(profile: DeviceProfile?) {
        /// 解碼單耳的基本動作及助理提供者，缺少配置或必要欄位回傳 nil。
        ///
        /// - Parameters:
        ///   - base: 耳機回報的基本長按碼，nil 表示尚未提供。
        ///   - assistant: 耳機回報的助理提供者碼，nil 表示該欄位未提供。
        /// - Returns: 可辨識的長按動作，配置或必要助理欄位不足時為 nil。
        func action(base: UInt8?, assistant: UInt8?) -> TouchHoldAction? {
            // 裝置基本碼及對應模型是辨識動作的必要資料。
            guard let base, let profile else { return nil }
            // 助理位置與最低 revision 都由機型配置決定。
            if touchAssistantSupported,
                profile.assistantOverridesAction
                    || TouchHoldAction(protocolCode: Int(base), profile: profile) == .digitalAssistant,
                let assistant, let key = profile.assistantProviders.first(where: { $0.value == assistant })?.key
            {
                return TouchHoldAction(rawValue: key)
            }
            // 助理位置與最低 revision 都由機型配置決定。
            if touchAssistantSupported && profile.assistantOverridesAction && assistant == nil { return nil }
            return TouchHoldAction(protocolCode: Int(base), profile: profile)
        }
        touchHoldLeft = action(base: touchHoldBaseLeft, assistant: touchAssistantLeft)
        touchHoldRight = action(base: touchHoldBaseRight, assistant: touchAssistantRight)
    }

    /// 九段曲線必須完整且在 -10...10 範圍內，才更新預設與自訂值。
    ///
    /// - Parameters:
    ///   - payload: 已接收的原始位元組，格式、長度與欄位有效性由此解析入口檢查。
    /// - Returns: 完整曲線成功解析時為 true，資料長度或預設增益無效時為 false。
    private mutating func applyEqualizerCurves(_ payload: Data) -> Bool {
        // 前兩欄宣告曲線數與九個頻段，短表或未知段數拒絕解析。
        guard payload.count >= 2, payload[1] == 9, (1...16).contains(payload[0]) else { return false }
        let presets = Int(payload[0])
        let tableEnd = 2 + (presets - 1) * 9
        // 完整預設表不足時保留先前曲線。
        guard payload.count >= tableEnd else { return false }
        let values = payload[2..<tableEnd].map { Int(Int8(bitPattern: $0)) }
        // signed int8 增益只接受協定的 -10...10 dB。
        guard values.allSatisfy({ (-10...10).contains($0) }) else { return false }
        var curves = [Array(repeating: 0, count: 9)]
        // 完整資料以九個頻段為一組拆成各條 EQ 曲線。
        for start in stride(from: 0, to: values.count, by: 9) { curves.append(Array(values[start..<(start + 9)])) }
        presetEqualizerCurves = curves
        // 可選自訂曲線完整時再驗證，缺失不推測為平坦。
        if payload.count >= tableEnd + 9 {
            let custom = payload[tableEnd..<(tableEnd + 9)].map { Int(Int8(bitPattern: $0)) }
            // 九段自訂增益全部落在 -10...10，才保存完整曲線。
            if custom.allSatisfy({ (-10...10).contains($0) }) { customEqualizerBands = custom }
        }
        return true
    }

    /// 高半位元組為左耳、低半位元組為右耳，值 1 表示配戴中。
    ///
    /// - Parameters:
    ///   - byte: 配戴狀態位元組，高半位元組為左耳、低半位元組為右耳。
    private mutating func applyPlacement(_ byte: UInt8) {
        isLeftWearing = byte >> 4 == 1
        isRightWearing = byte & 0x0F == 1
    }

    /// 至少兩個已知模式組成輪替，單模式與空遮罩回傳 nil。
    ///
    /// - Parameters:
    ///   - mask: 噪音模式的協定位元遮罩。
    /// - Returns: 至少兩種已知模式組成的輪替；空遮罩、單模式或未知位元為 nil。
    private func cycle(_ mask: UInt8) -> NoiseControlCycle? {
        // 空遮罩或單模式不足以構成輪替。
        guard mask.nonzeroBitCount >= 2 else { return nil }
        return NoiseControlCycle(rawValue: Int(mask))
    }

    /// 有效電量包含零，FF 或超出百分比的值以 nil 表示。
    ///
    /// - Parameters:
    ///   - value: 有效電量百分比，nil 或超過 100 表示未回報。
    /// - Returns: 0...100 的電量百分比；255 或超過 100 的值回傳 nil。
    private func battery(_ value: UInt8) -> Int? { value <= 100 ? Int(value) : nil }

    /// 識別資料忽略 NUL 與邊界空白。
    ///
    /// - Parameters:
    ///   - data: 已接收的原始位元組，格式、長度與欄位有效性由此解析入口檢查。
    /// - Returns: 移除 NUL 與邊界空白後的識別字串。
    private func ascii(_ data: Data) -> String {
        String(data: Data(data.filter { $0 != 0 }), encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}
