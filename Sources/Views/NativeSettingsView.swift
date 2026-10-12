import AppKit
import SwiftUI

/// macOS 設定側欄，詳情以系統 Form 與原生控制項呈現。
struct NativeSettingsView: View {

    @Bindable var bluetooth: BluetoothManager
    @Bindable var navigation: SettingsNavigation
    let spatialAudio: SpatialAudioController
    private let login = LaunchAtLogin.shared
    @State private var searchText = ""
    @State private var loginError: String?
    @State private var showAmbient = false

    /// 右面板與頁內連結共用注入的導覽狀態。
    private var selection: SettingsCategory {
        get { navigation.selection }
        nonmutating set { navigation.selection = newValue }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $navigation.columnVisibility) {
            NativeSidebar(pages: filteredPages, selection: $navigation.selection)
                .searchable(text: $searchText, placement: .sidebar, prompt: "Search settings categories")
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } detail: {
            Group {
                // 分類路由是固定的 App 頁面，能否選取由注入的分類集合決定。
                switch selection {
                // 聆聽模式由對應頁面處理，沿用共享服務。
                case .sound: sound
                // 音質與音效由對應頁面處理，沿用共享服務。
                case .quality: quality
                // 語音控制由對應頁面處理，沿用共享服務。
                case .voice: voice
                // 韌體由對應頁面處理，沿用共享服務。
                case .firmware: FirmwareUpdateView(bluetooth: bluetooth)
                // 空間音訊由對應頁面處理，沿用共享服務。
                case .spatial: SpatialAudioView(bluetooth: bluetooth, audio: spatialAudio)
                // 頭部動作由對應頁面處理，沿用共享服務。
                case .head: HeadGesturesView(bluetooth: bluetooth)
                // 連線管理由對應頁面處理，沿用共享服務。
                case .connections:
                    // 連線頁始終留在右面板，原生分欄與工具列不切換宿主。
                    if bluetooth.isConnected {
                        connections
                    } else {
                        // 未連線時同一詳情面板提供配對清單與連線操作。
                        ConnectionView(bluetooth: bluetooth, spatialAudio: spatialAudio)
                    }
                // 進階功能由對應頁面處理，沿用共享服務。
                case .advanced: advanced
                // 協助工具由對應頁面處理，沿用共享服務。
                case .accessibility: accessibility
                // 等化器由對應頁面處理，沿用共享服務。
                case .equalizer: EqualizerView(bluetooth: bluetooth)
                // 耳機操作由對應頁面處理，沿用共享服務。
                case .controls: EarbudControlsView(bluetooth: bluetooth)
                // 尋找耳機由對應頁面處理，沿用共享服務。
                case .find: FindMyEarbudsView(bluetooth: bluetooth)
                // 關於與診斷由對應頁面處理，沿用共享服務。
                case .about: AboutView(bluetooth: bluetooth)
                // 預設分類顯示一般設定頁。
                default: general
                }
            }
            .disabled(
                (bluetooth.firmware.isRunning && selection != .firmware)
                    || !bluetooth.isDemo && !bluetooth.status.hasControlStatus && selection != .general
                        && selection != .about && selection != .firmware && selection != .connections
            )
            .navigationTitle(selection.title)
            .safeAreaInset(edge: .bottom) {
                // 只有示範或操作結果才保留原生底部訊息列。
                if bluetooth.isDemo || bluetooth.commandNotice != nil {
                    VStack(spacing: 4) {
                        // 訊息由服務區分送出、回覆與錯誤，View 只決定語意色。
                        if let notice = bluetooth.commandNotice {
                            Text(verbatim: notice.message).foregroundStyle(notice.isError ? .red : .secondary)
                        }
                        // 示範狀態始終可見，避免樣本資訊被誤當裝置回報。
                        if bluetooth.isDemo { Text("Preview mode with sample data").foregroundStyle(.secondary) }
                    }.font(.caption).frame(maxWidth: .infinity).padding(8).background(.bar)
                }
            }
        }
        .onAppear {
            navigation.updateAvailableCategories(availablePages)
            // 首次沒有控制通道時開啟連線入口，其他分類仍可由側欄操作。
            if !bluetooth.isConnected && bluetooth.firmware.phase == .idle { selection = .connections }
        }
        .onChange(of: bluetooth.connectedModel?.id) { _, _ in
            // 機型頁面由 JSON 決定，歷史與側欄使用同一份可用分類。
            navigation.updateAvailableCategories(availablePages)
        }
        .onChange(of: bluetooth.isConnected) { _, connected in
            navigation.updateAvailableCategories(availablePages)
            // 手動或意外斷線後移到連線頁，更新重啟期間保留韌體頁。
            if !connected && bluetooth.firmware.phase == .idle { selection = .connections }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            login.refresh()
            // 回到 App 且系統已允許時，解除前次待核准訊息。
            if login.isEnabled { loginError = nil }
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(bluetooth.isDemo ? (bluetooth.previewDark ? .dark : .light) : nil)
    }

    /// 當前機型注入的頁面集合，無機型時只提供一般與診斷入口。
    private var availablePages: [SettingsCategory] {
        let categories = bluetooth.connectedModel?.profile.settingsCategories ?? [.general, .connections, .about]
        // 未連線時只保留無需控制通道的頁面，韌體流程依原模型繼續。
        return bluetooth.isConnected || bluetooth.firmware.phase != .idle
            ? categories : categories.filter(\.availableWithoutConnection)
    }

    /// 原生語系與英文鍵名都使用 localizedStandardContains 搜尋。
    private var filteredPages: [SettingsCategory] {
        availablePages.filter {
            searchText.isEmpty || NSLocalizedString($0.titleKey, comment: "").localizedStandardContains(searchText)
                || $0.titleKey.localizedStandardContains(searchText)
        }
    }

    /// 固定圖片框維持跨機型的名稱、電量與設定位置。
    private var general: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    HStack(spacing: 24) {
                        BudsIllustration(model: bluetooth.connectedModel, variant: bluetooth.productVariant).frame(
                            width: InterfaceMetrics.productSize.width, height: InterfaceMetrics.productSize.height)
                        BudsIllustration(
                            model: bluetooth.connectedModel, variant: bluetooth.productVariant, showCase: true
                        ).frame(width: InterfaceMetrics.productSize.width, height: InterfaceMetrics.productSize.height)
                    }.frame(height: 90)
                    Text(verbatim: bluetooth.connectedName ?? "Galaxy Buds").font(.title3.weight(.semibold))
                    Text(verbatim: bluetooth.connectedModel?.profile.modelNumber ?? "")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
                // 配色選項依機型配置載入，空 ID 代表自動辨識。
                Picker(
                    "Appearance color",
                    selection: Binding(
                        get: { bluetooth.appearanceColorOverride ?? "" },
                        set: { bluetooth.setAppearanceColor($0.isEmpty ? nil : $0) })
                ) {
                    Text("Automatic").tag("")
                    // 只列目前機型提供的配色，標籤走翻譯資源。
                    ForEach(bluetooth.connectedModel?.profile.colors ?? []) { variant in
                        Text(LocalizedStringKey(variant.label)).tag(variant.id)
                    }
                }
                LabeledContent {
                    Text(LocalizedStringKey(bluetooth.productVariant?.label ?? "Not reported"))
                } label: {
                    Text("Current appearance")
                }
                // 未識別色碼時揭露示意圖來源，不宣稱為真實耳機顏色。
                if bluetooth.appearanceColorOverride == nil,
                    bluetooth.connectedModel?.profile.colors.contains(where: {
                        $0.deviceIDs.contains(bluetooth.status.deviceColorID ?? -1)
                    }) != true
                {
                    Text("Color has not been identified. Showing the default illustration; select a color manually.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                // 左右耳與充電盒各自顯示有效值，未回報以文字提示。
                LabeledContent("Left earbud battery", value: charge(bluetooth.status.batteryLeft))
                LabeledContent("Right earbud battery", value: charge(bluetooth.status.batteryRight))
                LabeledContent("Case battery", value: charge(bluetooth.status.batteryCase))
            }
            Section {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { login.isEnabled },
                        set: { requested in
                            do {
                                try login.set(requested)
                                loginError =
                                    requested && !login.isEnabled
                                    ? String(localized: "Allow the login item in System Settings.") : nil
                            } catch {
                                // 原生註冊錯誤保留可見資訊，開關仍以系統實際狀態顯示。
                                loginError = error.localizedDescription
                            }
                        })
                ).disabled(bluetooth.isDemo)
                // 系統操作失敗留在同一個設定區塊，便於重新操作。
                if let loginError { Text(verbatim: loginError).foregroundStyle(.red) }
            }
            PermissionsView(bluetooth: bluetooth, audio: spatialAudio)
            Section("Quick Panel") {
                // 快捷項目選擇由機型提供的清單限制。
                ForEach(bluetooth.connectedModel?.profile.quickControls ?? []) { control in
                    Toggle(
                        LocalizedStringKey(control.displayName),
                        isOn: Binding(
                            get: { bluetooth.selectedQuickControls.contains(control.rawValue) },
                            set: { bluetooth.setQuickControlVisible(control, visible: $0) }))
                }
                Text("Select the controls to show in the menu bar panel.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    /// 原生分組表單承載模式、數值範圍與對話設定。
    private var sound: some View {
        Form {
            Section {

                ListenModePicker(
                    modes: bluetooth.connectedModel?.listenModes ?? [],
                    selection: bluetooth.status.hasControlStatus ? bluetooth.status.noiseControlMode : nil
                ) { bluetooth.setNoiseControl($0) }
                .frame(maxWidth: .infinity)
                LabeledContent("ANC strength") {
                    DiscreteLevelSlider(
                        level: bluetooth.status.ancLevel,
                        count: bluetooth.connectedModel?.ancLevelCount
                    ) { bluetooth.setAncLevel($0) }
                    .frame(width: 200).disabled(bluetooth.status.noiseControlMode != .anc)
                }
                LabeledContent("Ambient volume") {
                    DiscreteLevelSlider(
                        label: "Ambient volume", level: bluetooth.status.ambientSoundVolume,
                        count: bluetooth.connectedModel.map { $0.maxAmbientVolume + 1 }
                    ) { bluetooth.setAmbientVolume($0) }
                    .frame(width: 200).disabled(bluetooth.status.noiseControlMode != .ambient)
                }
            }
            Section("Automatically switch to ambient sound") {
                settingRow(.sirenDetection)
                Toggle(
                    "Detect conversations",
                    isOn: Binding(
                        get: { bluetooth.status.detectConversations },
                        set: { bluetooth.setDetectConversations($0) }))
                Picker(
                    "Duration",
                    selection: Binding(
                        get: { bluetooth.status.detectConversationsDuration },
                        set: { bluetooth.setDetectConversationsDuration($0) })
                ) {
                    Text("5 seconds").tag(0)
                    Text("10 seconds").tag(1)
                    Text("15 seconds").tag(2)
                }.disabled(!bluetooth.status.detectConversations)
                Toggle(
                    "Ambient sound during calls",
                    isOn: Binding(
                        get: { bluetooth.status.ambientDuringCalls },
                        set: { bluetooth.setAmbientDuringCalls($0) }))
                Toggle(
                    "Hear your own voice",
                    isOn: Binding(
                        get: { bluetooth.status.sidetone },
                        set: { bluetooth.setSidetone($0) }))
            }
        }.formStyle(.grouped)
    }

    /// 音質設定依耳機回報呈現，EQ 使用獨立頁面承載九段曲線。
    private var quality: some View {
        Form {
            Section {
                settingRow(.fitAdjustment)
                settingRow(.adaptiveVolume)
                settingRow(.voiceBoost)
                settingRow(.volumeNormalization)
                // 頁內捷徑只導向當前配置提供的分類。
                if availablePages.contains(.equalizer) {
                    Button("Open equalizer") { selection = .equalizer }
                }
            }
            Section("Calls") { settingRow(.clearCalls) }
        }.formStyle(.grouped)
    }

    /// 語音開關依配置與回報提供，語言模型來源由開發狀態揭露。
    private var voice: some View {
        Form {
            Section("Voice commands") {
                settingRow(.voiceCommands)
                Text("Uses the voice language currently installed on the earbuds.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    /// 已連線裝置提供中斷與無縫連接設定，跨帳號接續由來源平台處理。
    private var connections: some View {
        Form {
            Section("Device") {
                LabeledContent("Name", value: bluetooth.connectedName ?? "Galaxy Buds")
                Button("Disconnect") { bluetooth.disconnect() }
            }
            Section("Manage connections") { settingRow(.seamlessConnection) }
            Text(
                "Seamless connection allows another paired device to take the earbuds. Samsung account auto-switch is managed by Galaxy devices."
            )
            .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }

    /// 配戴偵測進階功能由機型的 additionalSettings 集合提供。
    private var advanced: some View {
        Form {
            Section("In-ear detection") { settingRow(.pauseWhenRemoved) }
        }.formStyle(.grouped)
    }

    /// 原生平衡與單耳設定使用協定範圍，自訂環境音由共用表單承載。
    private var accessibility: some View {
        Form {
            Section("Left-right sound balance") {
                // 尚未取得有效平衡值時顯示等待，不以置中值冒充回報。
                if let balance = bluetooth.status.stereoBalance {
                    HStack {
                        Text("Left")
                        Slider(
                            value: Binding(
                                get: { Double(bluetooth.status.stereoBalance ?? balance) },
                                set: { bluetooth.setStereoBalance(Int($0.rounded())) }), in: 0...32, step: 1
                        )
                        .accessibilityLabel("Left-right sound balance")
                        Text("Right")
                    }
                    Button("Center balance") { bluetooth.setStereoBalance(16) }
                } else {
                    // 平衡尚未回報時保留未知，避免顯示可寫入的預設值。
                    Text("Waiting for earbud settings").foregroundStyle(.secondary)
                }
            }
            // 降噪與自訂環境音共用耳機服務，表單只保存本頁展示狀態。
            Section("Noise control") {
                Toggle(
                    "Noise control with one earbud",
                    isOn: Binding(
                        get: { bluetooth.status.ncWithOneEarbud }, set: { bluetooth.setNoiseControlWithOneEarbud($0) }))
            }
            Section("Ambient Sound") {
                Button("Custom ambient settings…") { showAmbient = true }
            }
        }.formStyle(.grouped)
            .sheet(isPresented: $showAmbient) {
                VStack {
                    AmbientSoundView(bluetooth: bluetooth)
                    HStack {
                        Spacer()
                        Button("Done") { showAmbient = false }.keyboardShortcut(.defaultAction)
                    }.padding()
                }.frame(width: 500, height: 360)
            }
    }

    /// 已回報值提供開關，缺值以未回報文字呈現，避免誤示為關閉。
    ///
    /// - Parameters:
    ///   - setting: 機型配置允許的進階設定項目。
    /// - Returns: 已回報設定的開關，或未回報狀態的資料列。
    @ViewBuilder private func settingRow(_ setting: AdditionalSetting) -> some View {
        // 未配置的功能不建立資料列，支援範圍由當前模型提供。
        if bluetooth.connectedModel?.profile.additionalSettings.contains(setting) == true {
            // 原生 Toggle 只接收已回報布林，缺值改用未知狀態文字。
            if let value = bluetooth.status.additionalSettings[setting] {
                Toggle(
                    isOn: Binding(
                        get: { bluetooth.status.additionalSettings[setting] ?? value },
                        set: { bluetooth.setAdditionalSetting(setting, enabled: $0) })
                ) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(LocalizedStringKey(setting.displayName))
                        Text(LocalizedStringKey(setting.descriptionKey)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(!bluetooth.canSetAdditionalSetting(setting))
            } else {
                // 進階值尚未回報時使用資料列提示，不把未知顯示為關閉。
                LabeledContent(LocalizedStringKey(setting.displayName)) {
                    Text("Not reported").foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 尚未收到的電量以文字表達。
    ///
    /// - Parameters:
    ///   - value: 有效電量百分比，nil 或超過 100 表示未回報。
    /// - Returns: 有效電量的百分比文字，nil 顯示未回報。
    private func charge(_ value: Int?) -> String { value.map { "\($0)%" } ?? String(localized: "Not reported") }

}

/// SwiftUI 標題使用領域分類提供的翻譯鍵。
extension SettingsCategory {
    fileprivate var title: LocalizedStringKey { LocalizedStringKey(titleKey) }
}
