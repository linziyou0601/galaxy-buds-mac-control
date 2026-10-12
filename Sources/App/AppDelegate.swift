import AppKit

/// 協調 App 啟動、系統服務與選單列更新。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - 識別、服務與生命週期狀態

    private static let reopenNotification = Notification.Name("dev.local.galaxybudscontrol.showPanel")
    private let bluetooth = BluetoothManager()
    private let audio = AudioOutputController()
    private let spatialAudio = SpatialAudioController()
    private var statusBarController: StatusBarController?
    private var statusTimer: Timer?
    private var reopenObserver: NSObjectProtocol?
    private var terminationTask: Task<Void, Never>?

    // MARK: - 程序生命週期

    /// 單一程序持有控制通道，預覽與實機服務分開啟動。
    ///
    /// - Parameters:
    ///   - notification: 系統送出的生命週期或選取通知，事件內容由框架提供。
    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        let me = NSRunningApplication.current
        // 第二次啟動將入口交給既有程序，控制通道只有一個擁有者。
        if let identifier = me.bundleIdentifier,
            let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: {
                $0 != me
            })
        {
            existing.activate(options: [])
            DistributedNotificationCenter.default().postNotificationName(
                Self.reopenNotification,
                object: arguments.contains("--settings") ? "settings" : nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        reopenObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.reopenNotification, object: nil, queue: .main
        ) { [weak self] notice in
            let showSettings = notice.object as? String == "settings"
            MainActor.assumeIsolated {
                // 分散式通知保留明確的設定入口，其他啟動顯示快捷面板。
                if showSettings {
                    self?.statusBarController?.openDetailWindow()
                } else {
                    // 未要求設定視窗時，以快捷面板承接重新開啟事件。
                    self?.statusBarController?.showPanel()
                }
            }
        }
        let controller = StatusBarController(bluetooth: bluetooth, audio: audio, spatialAudio: spatialAudio)
        statusBarController = controller
        setupMainMenu()
        bluetooth.onAutoConnected = { [weak controller] in controller?.showPanel() }
        // 感測器直接更新原生音場，頭部追蹤不等待 SwiftUI 重繪。
        bluetooth.onSpatialQuaternion = { [weak spatialAudio = self.spatialAudio] values in
            spatialAudio?.updateOrientation(values)
        }

        // 預覽資料與真實系統服務分開，防止示範操作寫入耳機。
        if arguments.contains("--demo") {
            var model = BudsModel.defaultModel
            // 預覽機型識別必須命中已驗證的 JSON 配置。
            if let index = arguments.firstIndex(of: "--preview-model"), arguments.indices.contains(index + 1),
                let requested = BudsModel.allCases.first(where: { $0.id == arguments[index + 1] })
            {
                model = requested
            }
            bluetooth.configureDemo(model)
            // 顏色識別由同一個模型配置驗證，未知顏色保留預設。
            if let index = arguments.firstIndex(of: "--preview-color"), arguments.indices.contains(index + 1) {
                bluetooth.setAppearanceColor(arguments[index + 1])
            }
            bluetooth.previewDark = arguments.contains("--preview-dark")
        } else {
            // 實機模式才啟動系統音量監聽與藍牙自動連線。
            audio.startObserving()
            bluetooth.preferredAudioDeviceName = audio.outputName
            bluetooth.startAutoConnect()
        }
        // 選單列完成配置後才顯示入口，避免錨點尚未就緒。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            // 明確命令列入口開啟設定窗，通常啟動保持快捷面板流程。
            if arguments.contains("--settings") {
                self?.statusBarController?.openDetailWindow()
            } else {
                // 一般啟動顯示快捷面板，避免直接展開完整設定。
                self?.statusBarController?.showPanel()
            }
        }
        startObservingStatus()
    }

    /// 結束時停止背景操作，保留 macOS 管理的音訊連線。
    ///
    /// - Parameters:
    ///   - notification: 系統送出的生命週期或選取通知，事件內容由框架提供。
    func applicationWillTerminate(_ notification: Notification) {
        statusTimer?.invalidate()
        terminationTask?.cancel()
        terminationTask = nil
        spatialAudio.stop()
        bluetooth.setSpatialTracking(false)
        audio.stopObserving()
        // 移除跨程序觀察，停止後續喚起已釋放的視窗控制器。
        if let reopenObserver { DistributedNotificationCenter.default().removeObserver(reopenObserver) }
        bluetooth.stopAutoConnect()
        bluetooth.stopScanning()
        bluetooth.disconnect(deviceLink: false)
    }

    /// 原生延後結束讓還原命令完成，逾時後仍可結束 App。
    ///
    /// - Parameters:
    ///   - sender: AppKit 提供的 App 實體。
    /// - Returns: 韌體更新時取消結束，待寫入還原時延後結束，其餘允許立即結束。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 韌體寫入期間中斷會影響裝置，原生結束流程保留更新服務。
        if bluetooth.firmware.isRunning {
            let alert = NSAlert()
            alert.messageText = String(localized: "Wait for firmware installation to finish.")
            alert.runModal()
            return .terminateCancel
        }
        // 重複結束要求共用既有還原作業。
        guard terminationTask == nil else { return .terminateLater }
        spatialAudio.stop()
        bluetooth.setSpatialTracking(false)
        // 無待送還原命令即可正常退出，其餘等待 RFCOMM 完成。
        guard bluetooth.isWriting else { return .terminateNow }
        terminationTask = Task { @MainActor [weak self] in
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            // 以短間隔等待已排入的還原寫入，兩秒後允許結束。
            while self?.bluetooth.isWriting == true && ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(20))
                // 系統終止取消了等待時，作業不再回覆結束要求。
                guard !Task.isCancelled else { return }
            }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Finder 重新開啟 App 時顯示快捷面板，設定視窗由明確入口開啟。
    ///
    /// - Parameters:
    ///   - sender: AppKit 提供的 App 實體。
    ///   - hasVisibleWindows: AppKit 回報的視窗可見狀態，此入口仍統一顯示快捷面板。
    /// - Returns: true，保留 AppKit 的重新開啟處理並顯示快捷面板。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        statusBarController?.showPanel()
        return true
    }

    // MARK: - 選單與狀態同步

    /// 配件型 App 保留標準結束快捷鍵。
    private func setupMainMenu() {
        // 建立標準 App 選單與快捷鍵，項目動作由 AppKit 派送。
        let menu = NSMenu()
        let item = NSMenuItem()
        let application = NSMenu()
        let settings = application.addItem(
            withTitle: String(localized: "Settings…"),
            action: #selector(StatusBarController.openDetailWindow), keyEquivalent: ",")
        settings.target = statusBarController
        application.addItem(.separator())
        application.addItem(
            withTitle: String(localized: "Quit Galaxy Buds"),
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        // 完整選單交給 NSApp，避免快捷鍵與自製事件路徑並存。
        item.submenu = application
        menu.addItem(item)
        NSApp.mainMenu = menu
    }

    /// 每兩秒同步系統輸出、重新連線條件與電量文字。
    private func startObservingStatus() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                // 程序釋放後的 Timer 回呼停止存取服務。
                guard let self else { return }
                // 真實模式同步 CoreAudio，預覽保留示範資料且不改系統音量。
                if !self.bluetooth.isDemo {
                    self.audio.refresh()
                    self.bluetooth.preferredAudioDeviceName = self.audio.outputName
                }
                self.bluetooth.pollAutoConnect()
                self.statusBarController?.updateIcon(
                    connected: self.bluetooth.isConnected,
                    batteryLeft: self.bluetooth.status.batteryLeft, batteryRight: self.bluetooth.status.batteryRight)
            }
        }
    }
}
