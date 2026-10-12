import SwiftUI

/// 直接列出 Mac 已配對裝置，未知型號由使用者指定。
struct ConnectionView: View {
    @Bindable var bluetooth: BluetoothManager
    let spatialAudio: SpatialAudioController

    var body: some View {
        Form {
            Section("Mac Bluetooth devices") {
                // 權限或電源尚未就緒時保留原生入口，狀態由 CoreBluetooth 提供。
                if !bluetooth.bluetoothReady {
                    Text("Waiting for Bluetooth permission or power.")
                }
                // 連線等待以帶標題的原生進度列呈現，取消只停止本次控制通道。
                if bluetooth.isConnecting {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Connecting to \(bluetooth.connectedName ?? "Galaxy Buds")...")
                        Spacer()
                        Button("Cancel") { bluetooth.disconnect(deviceLink: false) }
                    }
                }
                // 配對或探索得到的候選裝置共用原生連線資料列。
                ForEach(bluetooth.discoveredDevices) { device in
                    ConnectionDeviceRow(bluetooth: bluetooth, device: device)
                }
                // 有效配對清單為空才顯示配對指引，等待授權不宣稱沒有裝置。
                if bluetooth.discoveredDevices.isEmpty && bluetooth.bluetoothReady {
                    Text("No paired earbuds found. Pair your earbuds in Mac Bluetooth settings.")
                }
            }
            Section {
                HStack {
                    Button("Refresh paired devices") { bluetooth.refreshPairedDevices() }
                    Button(LocalizedStringKey(bluetooth.isScanning ? "Stop discovery" : "Find nearby earbuds")) {
                        // 原生 inquiry 的開始與停止透過同一個服務管理生命週期。
                        if bluetooth.isScanning { bluetooth.stopScanning() } else { bluetooth.startScanning() }
                    }.disabled(!bluetooth.bluetoothReady || bluetooth.isConnecting)
                    Button("Open Mac Bluetooth settings") {
                        // 使用公開系統設定入口，配對與授權保留系統介面。
                        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                // 連線失敗只呈現服務提供的錯誤，維持可重試入口。
                if let error = bluetooth.connectionError {
                    Text(verbatim: error).foregroundStyle(.red)
                }
            }
            PermissionsView(bluetooth: bluetooth, audio: spatialAudio)
        }.formStyle(.grouped).navigationTitle("Connect earbuds")
            .task { bluetooth.refreshPairedDevices() }
            .onDisappear { bluetooth.stopScanning() }
    }
}

/// 小彈窗與設定視窗共用的裝置列，未知自訂名稱可指定機型。
struct ConnectionDeviceRow: View {
    @Bindable var bluetooth: BluetoothManager
    let device: BluetoothManager.DiscoveredDevice
    @State private var selectedModelID = ""
    private var model: BudsModel? {
        BudsModel.allCases.first { $0.id == selectedModelID } ?? device.model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "earbuds").foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text(verbatim: device.name)
                    Text(model?.name ?? String(localized: "Specify an earbud model"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Connect") {
                    // 型號必須從已驗證配置解析或由使用者指定，未知型號不連線。
                    if let model { bluetooth.connect(to: device, model: model) }
                }.disabled(model == nil || bluetooth.isConnecting)
            }
            // 自訂名稱無法辨識時才提供模型選擇，選擇項目來自配置目錄。
            if BudsModel.detect(from: device.name) == nil {
                Picker(
                    "Earbud model",
                    selection: Binding(
                        get: { selectedModelID.isEmpty ? device.model?.id ?? "" : selectedModelID },
                        set: { selectedModelID = $0 })
                ) {
                    Text("Choose a model").tag("")
                    // 手動辨識僅提供已驗證的機型配置。
                    ForEach(BudsModel.allCases) { Text($0.name).tag($0.id) }
                }.disabled(bluetooth.isConnecting)
            }
        }
    }
}
