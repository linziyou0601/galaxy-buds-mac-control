import Foundation
import ServiceManagement

/// 以同一份原生登入服務狀態同步開關與權限頁。
@Observable @MainActor
final class LaunchAtLogin {
    static let shared = LaunchAtLogin()
    private let service = SMAppService.mainApp
    private(set) var status: SMAppService.Status
    var isEnabled: Bool { status == .enabled }

    /// 初始化讀取系統快照，註冊副作用由 set 執行。
    private init() { status = service.status }

    /// 登錄或取消登入項目，成功與失敗都重新讀取系統狀態。
    ///
    /// - Parameters:
    ///   - enabled: 是否啟用此方法所管理的功能，實機結果由系統或耳機回報確認。
    /// - Throws: ServiceManagement 註冊或取消登入項目失敗時傳遞系統錯誤。
    func set(_ enabled: Bool) throws {
        defer { refresh() }
        if enabled {
            // 啟用登入啟動時，向 ServiceManagement 註冊。
            try service.register()
        } else {
            // 停用登入啟動時，向 ServiceManagement 取消註冊。
            try service.unregister()
        }
    }

    /// 重新讀取登入項目狀態，供前景切換及註冊結果共用。
    func refresh() { status = service.status }
}
