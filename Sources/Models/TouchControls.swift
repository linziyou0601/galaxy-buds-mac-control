import Foundation

/// 標準長按動作的協定碼，執行行為由耳機及所連裝置決定。
enum TouchHoldAction: String, CaseIterable, Identifiable, Sendable {
    case disabled, voiceAssistant, noiseControl, volume, spotify, digitalAssistant, googleAssistant, otherApp
    var id: String { rawValue }

    /// 將系統裝置轉成可辨識的耳機快照，缺少位址或候選資格時回傳 nil。
    ///
    /// - Parameters:
    ///   - protocolCode: 耳機回報的原始長按動作碼。
    ///   - profile: 目前裝置的已驗證機型配置，決定欄位位置、能力與範圍。
    init?(protocolCode: Int, profile: DeviceProfile?) {
        // 長按碼需存在於注入配置並對應已知動作，否則維持未回報。
        guard let key = profile?.touchActionCodes.first(where: { $0.value == protocolCode })?.key,
            let action = Self(rawValue: key)
        else { return nil }
        self = action
    }

    var displayName: String {
        // 長按動作名稱保留助理、音量與噪音控制的獨立語意。
        switch self {
        // 停用動作對應此翻譯鍵，顯示文字由語系資源提供。
        case .disabled: "Off"
        // 語音助理對應此翻譯鍵，顯示文字由語系資源提供。
        case .voiceAssistant: "Voice assistant"
        // 噪音控制對應此翻譯鍵，顯示文字由語系資源提供。
        case .noiseControl: "Noise control"
        // 音量對應此翻譯鍵，顯示文字由語系資源提供。
        case .volume: "Volume"
        // Spotify對應此翻譯鍵，顯示文字由語系資源提供。
        case .spotify: "Spotify"
        // 數位助理對應此翻譯鍵，顯示文字由語系資源提供。
        case .digitalAssistant: "Digital assistant"
        // Google 助理對應此翻譯鍵，顯示文字由語系資源提供。
        case .googleAssistant: "Google Assistant"
        // 其他 App對應此翻譯鍵，顯示文字由語系資源提供。
        case .otherApp: "Other app"
        }
    }
}

/// 四種模式的輪替遮罩，至少選擇兩種。
struct NoiseControlCycle: OptionSet, Sendable {
    let rawValue: Int
    static let ancAmbient = NoiseControlCycle(rawValue: 0x09)
    /// 以共用協定模式 bit 查詢輪替遮罩，保留 OptionSet 原值。
    ///
    /// - Parameters:
    ///   - mode: 要選擇或查詢的已知噪音模式，協定碼由共用列舉提供。
    /// - Returns: 此輪替遮罩包含指定模式時為 true。
    func contains(_ mode: NoiseControlMode) -> Bool { rawValue & mode.cycleBit != 0 }
}

/// 七種已知的操作開關，位置對應 LOCK_TOUCHPAD 命令的啟用旗標。
enum TouchGesture: Int, CaseIterable, Identifiable, Sendable {
    case singlePress, doublePress, triplePress, hold, answerCall, rejectCall, swipe
    var id: Int { rawValue }
    var statusBit: Int { [3, 2, 1, 0, 4, 5, 6][rawValue] }
    var displayName: String {
        // 輪替包含的模式使用共用噪音模式名稱。
        switch self {
        // 單次按壓對應此翻譯鍵，顯示文字由語系資源提供。
        case .singlePress: "Single press"
        // 連按兩次對應此翻譯鍵，顯示文字由語系資源提供。
        case .doublePress: "Double press"
        // 連按三次對應此翻譯鍵，顯示文字由語系資源提供。
        case .triplePress: "Triple press"
        // 長按對應此翻譯鍵，顯示文字由語系資源提供。
        case .hold: "Press and hold"
        // 接聽或結束通話對應此翻譯鍵，顯示文字由語系資源提供。
        case .answerCall: "Answer or end calls"
        // 拒接通話對應此翻譯鍵，顯示文字由語系資源提供。
        case .rejectCall: "Decline calls"
        // 滑動調整音量對應此翻譯鍵，顯示文字由語系資源提供。
        case .swipe: "Swipe to adjust volume"
        }
    }
}
