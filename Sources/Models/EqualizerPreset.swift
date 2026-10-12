import Foundation

/// EQ 預設索引，自訂模式在傳輸時使用協定值 7。
enum EqualizerPreset: Int, CaseIterable, Identifiable, Sendable {
    case normal = 0
    case bassBoost = 1
    case soft = 2
    case dynamic = 3
    case clear = 4
    case trebleBoost = 5
    case custom = 6

    var id: Int { rawValue }

    var displayName: String {
        // 已知 EQ 預設使用固定翻譯名稱，自訂模式保留獨立語意。
        switch self {
        // 一般音效對應此翻譯鍵，顯示文字由語系資源提供。
        case .normal: "Normal"
        // 低音增強對應此翻譯鍵，顯示文字由語系資源提供。
        case .bassBoost: "Bass Boost"
        // 柔和音效對應此翻譯鍵，顯示文字由語系資源提供。
        case .soft: "Soft"
        // 動態音效對應此翻譯鍵，顯示文字由語系資源提供。
        case .dynamic: "Dynamic"
        // 清晰音效對應此翻譯鍵，顯示文字由語系資源提供。
        case .clear: "Clear"
        // 高音增強對應此翻譯鍵，顯示文字由語系資源提供。
        case .trebleBoost: "Treble Boost"
        // 自訂音效對應此翻譯鍵，顯示文字由語系資源提供。
        case .custom: "Custom"
        }
    }

}
