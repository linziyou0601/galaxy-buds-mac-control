import SwiftUI

/// 裝置識別、密合度測試與本機診斷匯出。
struct AboutView: View {
    @Bindable var bluetooth: BluetoothManager
    @State private var fitTestRequested = false
    @State private var diagnosticsCopied = false
    private var status: BudsStatus { bluetooth.status }

    var body: some View {
        Form {
            Section("Device") {
                LabeledContent("Model", value: bluetooth.connectedModel?.name ?? "Galaxy Buds")
                infoRow("Software version", value: status.softwareVersion)
                infoRow("Left serial", value: status.serialLeft)
                infoRow("Right serial", value: status.serialRight)
                infoRow("Case serial", value: status.serialCase)
                infoRow("Case software version", value: status.caseSoftwareVersion)
            }
            Section("Earbud fit test") {
                Text("Put both earbuds in and start the test to check the seal.")
                LabeledContent("Left") { Text(resultLabel(status.fitLeft)) }
                LabeledContent("Right") { Text(resultLabel(status.fitRight)) }
                Button(LocalizedStringKey(fitTestRequested ? "Stop" : "Check earbud fit")) {
                    let next = !fitTestRequested
                    // 命令排入成功才顯示測試進行中，結果仍需裝置回報。
                    if bluetooth.setFitTest(active: next) { fitTestRequested = next }
                }
            }
            // 能力集合決定是否建立診斷區，不依模型名稱判斷。
            if bluetooth.connectedModel?.profile.features.contains(.hardwareDiagnostics) == true {
                Section("Hardware diagnostics") {
                    Text(
                        "This is an undocumented firmware self-test. A failed flag can also mean the firmware does not implement that check."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    // 能力集合決定是否建立診斷區，不依模型名稱判斷。
                    if bluetooth.connectedModel?.profile.features.contains(.spatialAudio) == true {
                        Button(
                            bluetooth.status.spatialAttached ? "Stop head tracking test" : "Test head tracking sensor"
                        ) {
                            bluetooth.setSpatialTracking(!bluetooth.status.spatialAttached)
                        }
                        LabeledContent("Head tracking") {
                            Text(bluetooth.spatialDataReceived ? "Sensor data received" : "No sensor data yet")
                        }
                    }
                    Button("Run hardware self-test") { bluetooth.runSelfTest() }
                        .disabled(bluetooth.selfTestRunning || !bluetooth.isConnected || bluetooth.isDemo)
                    // 等待回報期間的進度指示置中，服務擁有逾時作業。
                    if bluetooth.selfTestRunning {
                        ProgressView("Waiting for diagnostic results…").controlSize(.small).frame(maxWidth: .infinity)
                    }
                    // 有結果才按配置的 bit 清單解讀，未知旗標不宣稱裝置故障。
                    if let mask = bluetooth.status.selfTestMask {
                        // 診斷旗標名稱與 bit 位置由目前機型配置提供。
                        ForEach(bluetooth.connectedModel?.profile.diagnosticChecks ?? []) { check in
                            LabeledContent(LocalizedStringKey(check.labelKey)) {
                                Text(mask & (1 << check.bit) == 0 ? "Passed" : "Failed or unavailable")
                            }
                        }
                    }
                }
            }
            Section("Development status") {
                Text(verbatim: bluetooth.connectedModel?.name ?? "Galaxy Buds").font(.subheadline)
                Text(
                    "Statuses distinguish implementation, device validation and platform limitations for the current model."
                )
                .font(.caption).foregroundStyle(.secondary)
                // 開發狀態依目前機型配置顯示，避免跨機型宣稱支援。
                ForEach(bluetooth.connectedModel?.profile.developmentFeatures ?? []) { feature in
                    LabeledContent {
                        Text(LocalizedStringKey(feature.status.displayName)).foregroundStyle(.secondary)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(LocalizedStringKey("research." + feature.id))
                            Text(LocalizedStringKey(feature.reasonKey))
                                .font(.caption).foregroundStyle(.secondary)
                            // 參考連結逐項保留標題與來源，供使用者追查依據。
                            ForEach(feature.references) { reference in
                                Link(reference.title, destination: reference.url).font(.caption)
                            }
                        }
                    }
                }
            }
            Section("Diagnostics") {
                Text("Copies the connection log, so you can paste it into a bug report on GitHub.")
                Button(LocalizedStringKey(diagnosticsCopied ? "Copied" : "Copy diagnostics")) { copyDiagnostics() }
            }
        }.formStyle(.grouped)
            .onAppear { bluetooth.requestAboutInfo() }
            .onChange(of: [status.fitLeft, status.fitRight]) { _, results in
                // 左右結果完整後結束本地等待，未知結果保持測試狀態。
                if results.allSatisfy({ $0 != .unknown }) { fitTestRequested = false }
            }
            .onDisappear {
                // 離開頁面結束由此頁啟動的測試，避免隱藏操作持續。
                if fitTestRequested { bluetooth.setFitTest(active: false) }
                bluetooth.setSpatialTracking(false)
            }
    }

    /// 空白識別資料表示耳機尚未回報，序號允許選取複製。
    ///
    /// - Parameters:
    ///   - label: 此資料列使用的翻譯標籤。
    ///   - value: 顯示於資料列的識別文字，空字串表示尚未回報。
    /// - Returns: 顯示識別內容或未回報文字的資料列。
    private func infoRow(_ label: LocalizedStringKey, value: String) -> some View {
        LabeledContent(label) {
            Text(value.isEmpty ? String(localized: "Not reported") : value).monospaced().textSelection(.enabled)
        }
    }

    /// 測試結果顯示與協定結果碼一致。
    ///
    /// - Parameters:
    ///   - result: 密合度測試回報的結果碼。
    /// - Returns: 密合度結果碼對應的翻譯鍵。
    private func resultLabel(_ result: BudsStatus.FitResult) -> LocalizedStringKey {
        // 直接使用穩定結果列舉，unknown 與測試失敗保留不同語意。
        switch result {
        // 密合度良好對應此翻譯鍵，顯示文字由語系資源提供。
        case .good: "Good seal"
        // 需要調整配戴對應此翻譯鍵，顯示文字由語系資源提供。
        case .bad: "Adjust fit"
        // 測試或作業失敗對應此翻譯鍵，顯示文字由語系資源提供。
        case .failed: "Test failed"
        // 尚無結果對應此翻譯鍵，顯示文字由語系資源提供。
        case .unknown: "No result yet"
        }
    }

    /// 使用者主動匯出時才把裝置摘要與診斷寫入剪貼簿。
    private func copyDiagnostics() {
        let summary = "Device: \(bluetooth.connectedName ?? "Not reported")\nFirmware: \(status.softwareVersion)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DiagnosticsLog.shared.export(deviceSummary: summary), forType: .string)
        diagnosticsCopied = true
    }
}
