import Foundation

/// 配置可啟用的快捷控制，識別碼對應已實作的控制命令。
enum QuickControl: String, Codable, Identifiable, Sendable {
    case detectConversations
    case ambientDuringCalls
    case touchpadLock
    var id: String { rawValue }
    var displayName: String {
        // 快捷項目名稱對應詳細設定的相同功能。
        switch self {
        // 語音偵測對應此翻譯鍵，顯示文字由語系資源提供。
        case .detectConversations: "Detect conversations"
        // 通話環境音對應此翻譯鍵，顯示文字由語系資源提供。
        case .ambientDuringCalls: "Ambient sound during calls"
        // 觸控鎖定對應此翻譯鍵，顯示文字由語系資源提供。
        case .touchpadLock: "Touchpad lock"
        }
    }
}
