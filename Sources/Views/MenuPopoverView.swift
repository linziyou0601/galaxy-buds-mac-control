import AppKit
import SwiftUI

/// 固定開啟時的 viewport，內容變動由捲動區吸收。
struct MenuPopoverView: View {
    let content: MenuPopoverContent
    let viewportHeight: CGFloat
    var body: some View {
        ScrollView { content.fixedSize(horizontal: false, vertical: true) }
            .frame(width: InterfaceMetrics.popoverWidth, height: viewportHeight)
    }
}

/// 快捷控制的自然高度內容，同時供開啟量測與捲動畫面使用。
struct MenuPopoverContent: View {
    @Bindable var bluetooth: BluetoothManager
    @Bindable var audio: AudioOutputController
    let openDetail: () -> Void
    var body: some View { content }

    /// 固定產品區與強度區的高度，實機回報不改變資訊基準線。
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sound").font(.headline)
                Spacer()
                // 示範模式標示於面板，避免把合成狀態當成實機回報。
                if bluetooth.isDemo {
                    Text("Preview mode").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.bottom, 12)
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: Binding(get: { audio.volume }, set: { audio.setVolume($0) }), in: 0...1)
                    .disabled(bluetooth.isDemo || !audio.available)
                    .accessibilityLabel("System output volume")
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }
            // 系統音訊輸出與控制耳機不同時才顯示輸出名稱。
            if !bluetooth.isDemo && !audio.outputName.isEmpty,
                audio.outputName.filter({ !$0.isWhitespace }).lowercased()
                    != (bluetooth.connectedName ?? "").filter({ !$0.isWhitespace }).lowercased()
            {
                Text(verbatim: audio.outputName).font(.caption2).foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            Divider().padding(.vertical, 12)
            // 控制通道連線後才呈現耳機設定與電量。
            if bluetooth.isConnected {
                deviceRow
                Divider().padding(.vertical, 12)
                Text("Listening Mode").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.bottom, 5)
                ListenModePicker(
                    modes: bluetooth.connectedModel?.listenModes ?? [],
                    selection: bluetooth.status.hasControlStatus ? bluetooth.status.noiseControlMode : nil
                ) {
                    bluetooth.setNoiseControl($0)
                }.padding(.top, 8).disabled(!bluetooth.status.hasControlStatus && !bluetooth.isDemo)
                // 控制狀態尚未回報時，等待提示保留未知設定語意。
                if !bluetooth.status.hasControlStatus && !bluetooth.isDemo {
                    Text("Waiting for earbud settings").font(.caption).foregroundStyle(.secondary)
                }
                // 降噪強度只在目前模式為 ANC 時顯示。
                if bluetooth.status.noiseControlMode == .anc {
                    HStack {
                        Text("ANC strength").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        DiscreteLevelSlider(
                            level: bluetooth.status.ancLevel,
                            count: bluetooth.connectedModel?.ancLevelCount
                        ) {
                            bluetooth.setAncLevel($0)
                        }.frame(width: 165)
                    }.padding(.top, 8)
                }
                // 環境音音量只在目前模式為環境音時顯示。
                if bluetooth.status.noiseControlMode == .ambient {
                    HStack {
                        Text("Ambient volume").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        DiscreteLevelSlider(
                            label: "Ambient volume", level: bluetooth.status.ambientSoundVolume,
                            count: bluetooth.connectedModel.map { $0.maxAmbientVolume + 1 }
                        ) { bluetooth.setAmbientVolume($0) }.frame(width: 165)
                    }.padding(.top, 8)
                }
                let shortcuts = (bluetooth.connectedModel?.profile.quickControls ?? [])
                    .filter { bluetooth.selectedQuickControls.contains($0.rawValue) }
                // 使用者選取且機型提供的快捷項目才加入面板。
                if !shortcuts.isEmpty {
                    Divider().padding(.vertical, 12)
                    VStack(spacing: 10) {
                        // 各快捷操作使用共享狀態與相同設定服務。
                        ForEach(shortcuts) { control in
                            HStack {
                                Text(LocalizedStringKey(control.displayName)).font(.subheadline)
                                Spacer()
                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { bluetooth.quickControlValue(control) },
                                        set: { bluetooth.setQuickControl(control, enabled: $0) })
                                )
                                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                                .accessibilityLabel(Text(LocalizedStringKey(control.displayName)))
                            }
                        }
                    }
                }
            } else {
                // 未連線時顯示連線進度或裝置清單。
                // 連線嘗試進行中提供進度與取消入口。
                if bluetooth.isConnecting {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Connecting to \(bluetooth.connectedName ?? "Galaxy Buds")...")
                            .font(.subheadline)
                        Spacer()
                        Button("Cancel") { bluetooth.disconnect(deviceLink: false) }
                    }
                } else {
                    // 沒有連線作業時顯示未連線狀態。
                    Text("No Buds Connected").font(.subheadline)
                }
                // 連線錯誤由服務提供，保留原始可讀原因。
                if let error = bluetooth.connectionError {
                    Text(verbatim: error).font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                }
                // 未連線時依已辨識候選顯示連線入口。
                ForEach(bluetooth.discoveredDevices) { device in
                    ConnectionDeviceRow(bluetooth: bluetooth, device: device).controlSize(.small).padding(.top, 8)
                }
                HStack(spacing: 8) {
                    Button("Refresh paired devices") { bluetooth.refreshPairedDevices() }
                    Button(LocalizedStringKey(bluetooth.isScanning ? "Stop discovery" : "Find nearby earbuds")) {
                        // 探索按鈕依目前狀態開始或停止同一掃描作業。
                        if bluetooth.isScanning { bluetooth.stopScanning() } else { bluetooth.startScanning() }
                    }.disabled(!bluetooth.bluetoothReady || bluetooth.isConnecting)
                }.controlSize(.small).font(.caption).padding(.top, 10)
            }
            // 系統音量錯誤與耳機控制錯誤各自呈現。
            if let error = audio.errorText {
                Text(verbatim: error).font(.caption).foregroundStyle(.red).padding(.top, 8)
            }
            // 命令回饋有結果時才顯示，錯誤使用系統警示色。
            if let notice = bluetooth.commandNotice {
                Text(verbatim: notice.message).font(.caption2).foregroundStyle(notice.isError ? .red : .secondary)
                    .padding(.top, 10)
            }
            Divider().padding(.vertical, 12)
            Button("Galaxy Buds Settings…", action: openDetail).buttonStyle(.plain)
            // 預覽切換器僅供示範資料使用。
            if bluetooth.isDemo {
                Picker(
                    "Preview model",
                    selection: Binding(
                        get: { bluetooth.connectedModel ?? .defaultModel },
                        set: { bluetooth.configureDemo($0) })
                ) {
                    // 預覽機型切換只建立對應的示範快照。
                    ForEach(BudsModel.allCases) { model in Text(model.name).tag(model) }
                }.pickerStyle(.segmented).labelsHidden().padding(.top, 10)
                Toggle("Dark preview", isOn: $bluetooth.previewDark)
                    .toggleStyle(.checkbox).font(.caption).padding(.top, 8)
            }
            HStack {
                // 已連線時才提供中斷連線入口。
                if bluetooth.isConnected { Button("Disconnect") { bluetooth.disconnect() } }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary).padding(.top, 12)
        }
        .padding(16).frame(width: InterfaceMetrics.popoverWidth)
        .task {
            // 實機未連線時更新 Mac 配對清單，預覽不呼叫藍牙。
            if !bluetooth.isDemo && !bluetooth.isConnected { bluetooth.refreshPairedDevices() }
        }

    }

    /// 產品圖片置中於耳機名稱與行內電量上方。
    private var deviceRow: some View {
        VStack(spacing: 8) {
            BudsIllustration(model: bluetooth.connectedModel, variant: bluetooth.productVariant)
                .frame(width: InterfaceMetrics.productSize.width, height: InterfaceMetrics.productSize.height)
            Text(verbatim: bluetooth.connectedName ?? "Galaxy Buds")
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                Text("左 \(battery(bluetooth.status.batteryLeft))  右 \(battery(bluetooth.status.batteryRight))")
                Image(systemName: "battery.100percent")
                Text(battery(bluetooth.status.batteryCase))
            }.font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 130)
    }

    /// nil 表示未回報，耳機的有效零電量顯示為 0%。
    ///
    /// - Parameters:
    ///   - value: 有效電量百分比，nil 或超過 100 表示未回報。
    /// - Returns: 電量百分比文字，nil 顯示未回報，0 顯示 0%。
    private func battery(_ value: Int?) -> String { value.map { "\($0)%" } ?? String(localized: "Not reported") }

}
