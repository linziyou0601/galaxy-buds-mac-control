import AppKit

@main
@MainActor
/// 保留應用程式 delegate 並啟動 AppKit 主迴圈。
enum BudsControlApplication {
    static let delegate = AppDelegate()

    /// 以 accessory 政策進入 AppKit 主迴圈，AppDelegate 擁有系統服務。
    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
