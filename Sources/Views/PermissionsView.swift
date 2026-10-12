import AppKit
import CoreBluetooth
import ServiceManagement
import SwiftUI

/// 讀取公開授權狀態，系統音訊以實際擷取狀態呈現，授權開關由系統設定管理。
struct PermissionsView: View {
    let bluetooth: BluetoothManager
    let audio: SpatialAudioController
    @State private var authorization = CBManager.authorization
    private let login = LaunchAtLogin.shared

    var body: some View {
        Section("Privacy and permissions") {
            LabeledContent("Bluetooth permission") {
                Text(LocalizedStringKey(bluetoothStatus)).foregroundStyle(.secondary)
            }
            Text("Bluetooth access is required to discover and control paired earbuds.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Open Bluetooth privacy settings") { openSettings("Privacy_Bluetooth") }
                .disabled(bluetooth.isDemo)
            LabeledContent("System audio capture") {
                Text(audio.isProcessing ? "Capturing audio" : "Not capturing audio")
                    .foregroundStyle(.secondary)
            }
            Text(
                "Optional spatial audio requests system audio recording permission when enabled. Audio is processed locally without saving or uploading. Check the permission switch in System Settings."
            )
            .font(.caption).foregroundStyle(.secondary)
            Button("Open system audio privacy settings") { openSettings("Privacy_AudioCapture") }
                .disabled(bluetooth.isDemo)
            LabeledContent("Login item status") {
                Text(LocalizedStringKey(loginStatusText)).foregroundStyle(.secondary)
            }
            Button("Open login item settings") { SMAppService.openSystemSettingsLoginItems() }
                .disabled(bluetooth.isDemo)
        }
        .onAppear { refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
    }

    private var bluetoothStatus: String {
        // 原生藍牙授權狀態對應各自的可讀文字。
        switch authorization {
        // 藍牙已授權對應此翻譯鍵，顯示文字由語系資源提供。
        case .allowedAlways: "Allowed"
        // 藍牙遭拒絕對應此翻譯鍵，顯示文字由語系資源提供。
        case .denied: "Denied"
        // 系統政策限制藍牙對應此翻譯鍵，顯示文字由語系資源提供。
        case .restricted: "Restricted by system policy"
        // 尚未要求藍牙授權對應此翻譯鍵，顯示文字由語系資源提供。
        case .notDetermined: "Not requested"
        // 未來系統新增的授權狀態明確顯示未知。
        @unknown default: "Unknown"
        }
    }

    private var loginStatusText: String {
        // 登入服務回報區分已註冊、需核准與不可用。
        switch login.status {
        // 登入項目已啟用對應此翻譯鍵，顯示文字由語系資源提供。
        case .enabled: "Allowed"
        // 登入項目尚未註冊對應此翻譯鍵，顯示文字由語系資源提供。
        case .notRegistered: "Not registered"
        // 登入項目等待系統核准對應此翻譯鍵，顯示文字由語系資源提供。
        case .requiresApproval: "Requires system approval"
        // 系統無法取得登入項目對應此翻譯鍵，顯示文字由語系資源提供。
        case .notFound: "Login item unavailable"
        // 未來新增的登入狀態明確顯示未知。
        @unknown default: "Unknown"
        }
    }

    /// 前景切換重新讀取公開 Bluetooth 與登入服務快照，音訊狀態由引擎提供。
    private func refreshStatus() {
        authorization = CBManager.authorization
        login.refresh()
    }

    /// 以原生系統設定 URL 開啟指定隱私權頁，授權變更由使用者完成。
    ///
    /// - Parameters:
    ///   - pane: 公開系統設定 URL 的頁面識別。
    private func openSettings(_ pane: String) {
        // 入口只使用內部已知 pane 名稱，無法建立 URL 時保留現況。
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane) else { return }
        NSWorkspace.shared.open(url)
    }
}
