import SwiftUI
import UniformTypeIdentifiers

/// 原生韌體來源、映像預檢與明確確認後的更新流程。
struct FirmwareUpdateView: View {
    @Bindable var bluetooth: BluetoothManager
    @State private var releases: [FirmwareRelease] = []
    @State private var binary: FirmwareBinary?
    @State private var error: String?
    @State private var loadingMessage: LocalizedStringKey?
    @State private var updateNotice: String?
    @State private var importing = false
    @State private var confirming = false
    @State private var operation: Task<Void, Never>?
    private var busy: Bool { loadingMessage != nil }

    var body: some View {
        Form {
            Section {
                LabeledContent(
                    "Current version",
                    value: bluetooth.status.softwareVersion.isEmpty
                        ? String(localized: "Not reported") : bluetooth.status.softwareVersion)
                // 官方資訊與封存來源依目前機型配置提供。
                if let profile = bluetooth.connectedModel?.profile {
                    LabeledContent("Model", value: profile.name)
                    Link("Samsung update information", destination: profile.firmware.officialInformationURL)
                    Link("Third-party firmware archive", destination: profile.firmware.archiveBaseURL)
                    Text(
                        "The archive collects Samsung OTA files. Its list is separate from the official update availability for your earbuds."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                // 控制通道尚未連線時提供重連入口。
                if !bluetooth.isConnected { Button("Reconnect") { bluetooth.reconnectCurrentDevice() } }
                Button("Check archived versions") { checkUpdates() }.disabled(
                    busy || bluetooth.firmware.isRunning || bluetooth.isDemo || bluetooth.status.softwareVersion.isEmpty
                )
                Button("Choose firmware file…") { importing = true }.disabled(
                    busy || bluetooth.firmware.isRunning || bluetooth.isDemo)
                // 查詢與下載期間以進度提示說明目前作業。
                if let loadingMessage {
                    ProgressView(loadingMessage).controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                // 來源查詢有明確結果時顯示通知。
                if let updateNotice { Text(verbatim: updateNotice).foregroundStyle(.secondary) }
            }
            // 來源包含版本時才呈現最新封存項目。
            if let latest = releases.first {
                Section("Available update") {
                    LabeledContent("Latest archived version for this model", value: latest.buildName)
                    Text(verbatim: latest.releaseDescription).font(.caption).foregroundStyle(.secondary)
                    Button("Download archived firmware") { download(latest) }
                        .disabled(busy || bluetooth.firmware.isRunning || bluetooth.isDemo)
                    // 較舊項目只有存在時才提供展開清單。
                    if releases.count > 1 {
                        DisclosureGroup("Other newer versions") {
                            // 較舊封存項目保留版本順序，各自提供下載入口。
                            ForEach(Array(releases.dropFirst())) { release in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(verbatim: release.buildName)
                                        Text(verbatim: release.releaseDescription).font(.caption).foregroundStyle(
                                            .secondary)
                                    }
                                    Spacer()
                                    Button("Download") { download(release) }
                                        .disabled(busy || bluetooth.firmware.isRunning || bluetooth.isDemo)
                                }
                            }
                        }
                    }
                }
            }
            // 已選取且驗證的映像才可顯示安裝摘要。
            if let binary {
                Section("Selected firmware") {
                    LabeledContent("Version", value: binary.buildName)
                    LabeledContent("Bytes", value: binary.totalSize.formatted())
                    // 最低電量依目前機型配置顯示。
                    if let minimum = bluetooth.connectedModel?.profile.firmware.minimumBatteryPercent {
                        LabeledContent("Minimum earbud charge", value: (Double(minimum) / 100).formatted(.percent))
                    }
                    Text("Keep both earbuds in the open case and keep the Mac nearby.")
                    Button("Install firmware", role: .destructive) { confirming = true }
                        .disabled(!bluetooth.canInstallFirmware(binary) || bluetooth.firmware.isRunning)
                }
            }
            Section("Update progress") {
                progress
                // 更新進行中才提供該階段允許的取消操作。
                if bluetooth.firmware.isRunning {
                    Text("Keep this app running until the installed version has been confirmed.")
                    Button("Cancel transfer") { bluetooth.firmware.cancel() }
                        .disabled(!bluetooth.firmware.canCancel)
                }
                // 作業失敗時保留可讀的錯誤原因。
                if let error { Text(verbatim: error).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        // 開啟版本頁時重讀裝置識別，重連握手的未回報快照可由原生查詢更新。
        .onAppear { bluetooth.requestAboutInfo() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            // 選檔成功且機型已知時，才開始映像解析。
            guard case .success(let url) = result, let profile = bluetooth.connectedModel?.profile else { return }
            loadingMessage = "Validating firmware file…"
            operation = Task {
                let access = url.startAccessingSecurityScopedResource()
                defer {
                    // 已取得安全範圍存取權時，作業結束必須釋放。
                    if access { url.stopAccessingSecurityScopedResource() }
                    // 取消作業不更新已由新工作接管的進度提示。
                    if !Task.isCancelled { loadingMessage = nil }
                }
                do {
                    let parsed = try await Task.detached(priority: .userInitiated) {
                        try FirmwareBinary(
                            data: Data(contentsOf: url), buildName: url.deletingPathExtension().lastPathComponent,
                            profile: profile)
                    }.value
                    // 解析結果僅回寫仍有效的作業與原機型。
                    guard !Task.isCancelled, bluetooth.connectedModel?.profile.id == profile.id else { return }
                    binary = parsed
                    error = nil
                } catch {
                    // 下載或解析失敗只回報目前仍有效的作業。
                    // 已取消作業的錯誤不覆蓋較新的頁面狀態。
                    if !Task.isCancelled { self.error = error.localizedDescription }
                }
            }
        }
        .confirmationDialog("Install this firmware?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Install firmware", role: .destructive) {
                // 確認按鈕仍須由服務檢查安裝資格。
                if let binary, bluetooth.canInstallFirmware(binary) { bluetooth.installFirmware(binary) }
            }
        } message: {
            Text(
                "Interrupting firmware installation can damage the earbuds. Confirm the model and version before continuing."
            )
        }
        .onChange(of: bluetooth.connectedModel?.id) { _, _ in
            operation?.cancel()
            releases = []
            binary = nil
            loadingMessage = nil
            updateNotice = nil
        }
        .onChange(of: bluetooth.status.softwareVersion) { _, version in
            releases = releases.filter { FirmwareVersion.isNewer($0.buildName, than: version) }
        }
        .onDisappear {
            operation?.cancel()
            loadingMessage = nil
        }
    }

    @ViewBuilder private var progress: some View {
        // 進度呈現依更新服務階段，等待重啟與完成分開顯示。
        switch bluetooth.firmware.phase {
        // 尚未開始更新時提示選擇映像。
        case .idle: Text("Choose an update to begin.")
        // 等待工作階段與協商時顯示不確定進度。
        case .preparing: ProgressView("Preparing…").controlSize(.small).frame(maxWidth: .infinity)
        // 傳輸進度使用服務回報的 0...1 比例。
        case .sending(let fraction): ProgressView("Sending firmware…", value: fraction)
        // 裝置安裝百分比轉成 0...1 進度。
        case .installing(let percent): ProgressView("Installing…", value: Double(percent) / 100)
        // 等待重新連線與版本讀取時保留進度提示。
        case .awaitingRestart:
            ProgressView("Waiting for restart and version confirmation…").controlSize(.small).frame(maxWidth: .infinity)
        // 只有版本確認成功才顯示已安裝。
        case .finished: Text("Installed version confirmed.")
        // 顯示服務保存的錯誤原因。
        case .failed(let message): Text(verbatim: message).foregroundStyle(.red)
        }
    }

    /// 以當前機型查詢來源，只呈現與安裝版本同系列且較新的封存項目。
    /// 取消與換機型後的回覆不更新此頁，來源失敗保留可見錯誤。
    private func checkUpdates() {
        // 已知機型與目前韌體版本齊備後才查詢相容更新。
        guard let model = bluetooth.connectedModel, !bluetooth.status.softwareVersion.isEmpty else { return }
        let current = bluetooth.status.softwareVersion
        loadingMessage = "Checking for firmware updates…"
        updateNotice = nil
        error = nil
        operation = Task {
            defer {
                // 仍有效的作業結束後清除自己的進度提示。
                if !Task.isCancelled { loadingMessage = nil }
            }
            do {
                let items = try await FirmwareCatalog().releases(for: model)
                // 舊查詢取消或已換機型時，結果不寫入此頁。
                guard !Task.isCancelled, bluetooth.connectedModel?.id == model.id else { return }
                let compatible = items.filter { $0.buildName.prefix(6) == current.prefix(6) }
                releases = compatible.filter { FirmwareVersion.isNewer($0.buildName, than: current) }
                // 沒有同系列版本時，明確說明來源未提供相容項目。
                if compatible.isEmpty {
                    updateNotice = String(localized: "The archive has no firmware matching this device's build family.")
                } else if releases.isEmpty {
                    // 同系列版本存在但沒有較新版時，顯示已無可用更新。
                    updateNotice = String(localized: "The archive has no version newer than the installed firmware.")
                }
            } catch {
                // 下載或解析失敗只回報目前仍有效的作業。
                // 已取消作業的錯誤不覆蓋較新的頁面狀態。
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    /// 下載封存項目並在背景驗證映像，選定檔案仍須獨立確認才可刷寫。
    /// 取消或機型變動時略過較舊作業結果。
    ///
    /// - Parameters:
    ///   - release: 來源目錄中選取的韌體項目，包含機型、版本與下載識別。
    private func download(_ release: FirmwareRelease) {
        // 下載需以目前機型提供的來源與格式驗證。
        guard let model = bluetooth.connectedModel else { return }
        loadingMessage = "Downloading and validating firmware…"
        error = nil
        operation = Task {
            defer {
                // 仍有效的作業結束後清除自己的進度提示。
                if !Task.isCancelled { loadingMessage = nil }
            }
            do {
                let data = try await FirmwareCatalog().download(release, profile: model.profile)
                // 下載完成後仍核對作業取消與機型身分。
                guard !Task.isCancelled, bluetooth.connectedModel?.id == model.id else { return }
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try FirmwareBinary(data: data, buildName: release.buildName, profile: model.profile)
                }.value
                // 失敗回饋只屬於仍有效的目前下載作業。
                guard !Task.isCancelled, bluetooth.connectedModel?.id == model.id else { return }
                binary = parsed
            } catch {
                // 下載或解析失敗只回報目前仍有效的作業。
                // 已取消作業的錯誤不覆蓋較新的頁面狀態。
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}
