import Foundation

/// 聆聽模式的協定值、名稱與系統圖示。
enum NoiseControlMode: Int, Identifiable, Sendable {
    case off = 0
    case anc = 1
    case ambient = 2
    case adaptive = 3

    var id: Int { rawValue }

    var displayName: String {
        // 四種聆聽模式使用固定翻譯名稱。
        switch self {
        // 關閉對應此翻譯鍵，顯示文字由語系資源提供。
        case .off: "Off"
        // 主動式降噪對應此翻譯鍵，顯示文字由語系資源提供。
        case .anc: "Noise Cancelling"
        // 環境音對應此翻譯鍵，顯示文字由語系資源提供。
        case .ambient: "Ambient Sound"
        // 最佳化對應此翻譯鍵，顯示文字由語系資源提供。
        case .adaptive: "Adaptive"
        }
    }

    /// 長按輪替使用 Off=4、ANC=8、Ambient=1、Adaptive=2。
    var cycleBit: Int {
        // 模式圖示與命令碼共用同一列舉語意。
        switch self {
        // 關閉使用輪替協定遮罩 4，與模式 rawValue 分開。
        case .off: 4
        // 主動式降噪使用輪替協定遮罩 8，與模式 rawValue 分開。
        case .anc: 8
        // 環境音使用輪替協定遮罩 1，與模式 rawValue 分開。
        case .ambient: 1
        // 最佳化使用輪替協定遮罩 2，與模式 rawValue 分開。
        case .adaptive: 2
        }
    }

    var iconName: String {
        // 輪替遮罩採協定位元映射，與 rawValue 分開處理。
        switch self {
        // 關閉使用 SF Symbol「speaker.slash」。
        case .off: "speaker.slash"
        // 主動式降噪使用 SF Symbol「ear.badge.waveform」。
        case .anc: "ear.badge.waveform"
        // 環境音對應此翻譯鍵，顯示文字由語系資源提供。
        case .ambient: "ear"
        // 最佳化對應此翻譯鍵，顯示文字由語系資源提供。
        case .adaptive: "waveform"
        }
    }

}
