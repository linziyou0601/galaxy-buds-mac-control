import Foundation

/// 已有命令與回報依據的進階開關，由機型配置決定顯示項目。
enum AdditionalSetting: String, Codable, Sendable, Identifiable {
    case seamlessConnection
    case pauseWhenRemoved
    case clearCalls
    case sirenDetection
    case voiceCommands
    case adaptiveVolume
    case fitAdjustment
    case voiceBoost
    case volumeNormalization

    var id: String { rawValue }
    var displayName: String {
        // 進階設定名稱共用翻譯鍵，配置只選擇可用設定。
        switch self {
        // 流暢耳機連線對應此翻譯鍵，顯示文字由語系資源提供。
        case .seamlessConnection: "Seamless earbud connection"
        // 摘耳暫停對應此翻譯鍵，顯示文字由語系資源提供。
        case .pauseWhenRemoved: "Pause media when an earbud is removed"
        // 清晰通話對應此翻譯鍵，顯示文字由語系資源提供。
        case .clearCalls: "Clearer calls"
        // 警報偵測對應此翻譯鍵，顯示文字由語系資源提供。
        case .sirenDetection: "Detect sirens"
        // 語音指令對應此翻譯鍵，顯示文字由語系資源提供。
        case .voiceCommands: "Voice commands"
        // 適應性音量對應此翻譯鍵，顯示文字由語系資源提供。
        case .adaptiveVolume: "Adaptive volume"
        // 配戴音效調整對應此翻譯鍵，顯示文字由語系資源提供。
        case .fitAdjustment: "Adjust sound to fit"
        // 人聲增強對應此翻譯鍵，顯示文字由語系資源提供。
        case .voiceBoost: "Boost dialogue"
        // 音量標準化對應此翻譯鍵，顯示文字由語系資源提供。
        case .volumeNormalization: "Volume normalization"
        }
    }
    var descriptionKey: String {
        // 每項進階設定對應既有協定命令，傳輸共用同一服務。
        switch self {
        // 流暢耳機連線對應此翻譯鍵，顯示文字由語系資源提供。
        case .seamlessConnection: "Allow other paired devices to connect to your earbuds."
        // 摘耳暫停對應此翻譯鍵，顯示文字由語系資源提供。
        case .pauseWhenRemoved: "Pause playback when an earbud is removed."
        // 清晰通話對應此翻譯鍵，顯示文字由語系資源提供。
        case .clearCalls: "Improve voice clarity during calls."
        // 警報偵測對應此翻譯鍵，顯示文字由語系資源提供。
        case .sirenDetection: "Switch to ambient sound when a siren is detected."
        // 語音指令對應此翻譯鍵，顯示文字由語系資源提供。
        case .voiceCommands: "Control playback and calls with voice commands."
        // 適應性音量對應此翻譯鍵，顯示文字由語系資源提供。
        case .adaptiveVolume: "Adjust volume automatically for your surroundings."
        // 配戴音效調整對應此翻譯鍵，顯示文字由語系資源提供。
        case .fitAdjustment: "Adjust sound using the fit of your earbuds."
        // 人聲增強對應此翻譯鍵，顯示文字由語系資源提供。
        case .voiceBoost: "Make speech clearer in media."
        // 音量標準化對應此翻譯鍵，顯示文字由語系資源提供。
        case .volumeNormalization: "Reduce differences in volume between audio sources."
        }
    }

    var command: MessageID {
        // 特定設定使用子命令前綴，其餘使用一般布林格式。
        switch self {
        // 流暢耳機連線對應既有命令 .setSeamlessConnection，格式由傳輸入口處理。
        case .seamlessConnection: .setSeamlessConnection
        // 摘耳暫停對應既有命令 .pauseMediaWhenRemoved，格式由傳輸入口處理。
        case .pauseWhenRemoved: .pauseMediaWhenRemoved
        // 清晰通話對應既有命令 .setClearCalls，格式由傳輸入口處理。
        case .clearCalls: .setClearCalls
        // 警報偵測對應既有命令 .setSirenDetection，格式由傳輸入口處理。
        case .sirenDetection: .setSirenDetection
        // 語音指令對應既有命令 .setVoiceCommands，格式由傳輸入口處理。
        case .voiceCommands: .setVoiceCommands
        // 適應性音量對應既有命令 .setAdaptiveVolume，格式由傳輸入口處理。
        case .adaptiveVolume: .setAdaptiveVolume
        // 配戴音效調整對應既有命令 .setFitAdjustment，格式由傳輸入口處理。
        case .fitAdjustment: .setFitAdjustment
        // 人聲增強對應既有命令 .setBoostLoudness，格式由傳輸入口處理。
        case .voiceBoost, .volumeNormalization: .setBoostLoudness
        }
    }
    /// 語音指令子命令 1 控制開關，其餘單一布林命令直接傳值。
    var commandPrefix: [UInt8] { self == .voiceCommands ? [1] : [] }
    var isInverted: Bool { self == .seamlessConnection }
}
