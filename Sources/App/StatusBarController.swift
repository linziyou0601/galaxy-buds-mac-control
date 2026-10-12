import AppKit
import SwiftUI

/// 選單列入口、系統 popover 與詳細設定視窗的生命週期。
@MainActor
final class StatusBarController: NSObject {
    // 服務與視窗由同一控制器持有，選單列與設定視窗共用狀態。
    private let bluetooth: BluetoothManager
    private let audio: AudioOutputController
    private let spatialAudio: SpatialAudioController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var detailWindow: NSWindow?
    private let settingsNavigation = SettingsNavigation()
    private var navigationControl: NSSegmentedControl?
    private var panelConnectionState: Bool?

    /// 注入藍牙、系統音量與空間音訊服務，建立原生選單列入口。
    ///
    /// - Parameters:
    ///   - bluetooth: 共享耳機連線與設定服務，控制操作與狀態回報共用此實體。
    ///   - audio: 共享 Mac 輸出音量服務。
    ///   - spatialAudio: 共享音訊擷取與空間渲染服務。
    init(bluetooth: BluetoothManager, audio: AudioOutputController, spatialAudio: SpatialAudioController) {
        self.bluetooth = bluetooth
        self.audio = audio
        self.spatialAudio = spatialAudio
        super.init()
        statusItem.autosaveName = "GalaxyBudsStatusItem"
        // 系統提供選單列按鈕後才安裝符號與動作。
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "earbuds", accessibilityDescription: "Galaxy Buds")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePanel)
        }
        popover.behavior = .transient
    }

    /// 開啟時量測可見內容並固定 viewport，資料回報不重新配置視窗位置。
    func showPanel() {
        // 原生選單列錨點或按鈕尚未建立時保留現況。
        guard let button = statusItem.button, button.window != nil else { return }
        popover.appearance = bluetooth.isDemo ? NSAppearance(named: bluetooth.previewDark ? .darkAqua : .aqua) : nil
        NSApp.activate(ignoringOtherApps: true)
        let wasShown = popover.isShown
        // 已顯示的面板只有連線版面切換時需要重新量測。
        guard !wasShown || panelConnectionState != bluetooth.isConnected else { return }
        panelConnectionState = bluetooth.isConnected
        let screen = button.window?.screen
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 700, height: 700)
        let anchor = button.window!.convertToScreen(button.convert(button.bounds, to: nil))
        let available = max(120, min(visible.height, anchor.minY - visible.minY) - 24)
        // 使用相同 View 量測內容高度，再以螢幕可見範圍限制 viewport。
        let measurement = NSHostingController(rootView: panelContent.fixedSize(horizontal: false, vertical: true))
        let fitted = measurement.sizeThatFits(
            in: NSSize(width: InterfaceMetrics.popoverWidth, height: CGFloat.greatestFiniteMagnitude))
        let height = min(available, max(1, fitted.height))
        let content = MenuPopoverView(content: panelContent, viewportHeight: height)
        let hosting: NSHostingController<MenuPopoverView>
        // 連線狀態變動保留同一個原生 popover，避免首次定位與重開結果不同。
        if wasShown, let existing = popover.contentViewController as? NSHostingController<MenuPopoverView> {
            existing.rootView = content
            hosting = existing
        } else {
            // 首次開啟尚無 hosting controller，建立後交由 popover 持有。
            hosting = NSHostingController(rootView: content)
            popover.contentViewController = hosting
        }
        // 量測結果作為唯一尺寸來源，HostingController 不再次改動視窗。
        hosting.sizingOptions = []
        let size = NSSize(width: InterfaceMetrics.popoverWidth, height: height)
        hosting.preferredContentSize = size
        hosting.view.setFrameSize(size)
        hosting.view.layoutSubtreeIfNeeded()
        popover.contentSize = size
        // 尚未開啟時才向系統要求顯示及鍵盤焦點。
        if !wasShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// 相同內容用於量測及呈現，設定入口共用既有視窗。
    private var panelContent: MenuPopoverContent {
        MenuPopoverContent(bluetooth: bluetooth, audio: audio) { [weak self] in self?.openDetailWindow() }
    }

    /// 選單列點按切換原生 popover 的顯示狀態。
    @objc private func togglePanel() {
        // 開啟中的面板關閉，其餘點按走共用量測與顯示流程。
        if popover.isShown { popover.performClose(nil) } else { showPanel() }
    }

    /// 設定視窗使用原生標題列、側欄與可調整的內容尺寸。
    @objc func openDetailWindow() {
        popover.performClose(nil)
        // 設定視窗只建立一次，重新開啟保留分類與原生視窗狀態。
        if detailWindow == nil {
            let hosting = NSHostingController(
                rootView: SettingsRootView(
                    bluetooth: bluetooth, navigation: settingsNavigation, spatialAudio: spatialAudio
                )
                .frame(
                    minWidth: InterfaceMetrics.minimumSettingsSize.width,
                    minHeight: InterfaceMetrics.minimumSettingsSize.height))
            // 量測結果作為唯一尺寸來源，HostingController 不再次改動視窗。
            hosting.sizingOptions = []
            let window = NSWindow(contentViewController: hosting)
            window.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Galaxy Buds"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            // 原生 tracking separator 讓標題與歷史導覽限制在右面板。
            // 工具列使用原生項目與側欄分隔線，delegate 只提供歷史控制。
            let toolbar = NSToolbar(identifier: "BudsControlSettings")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
            window.toolbarStyle = .unified
            settingsNavigation.onChange = { [weak self] in self?.refreshNavigation() }
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 780, height: 580))
            window.contentMinSize = InterfaceMetrics.minimumSettingsSize
            window.center()
            detailWindow = window
            refreshNavigation()
        }
        NSApp.activate(ignoringOtherApps: true)
        // 視窗建立或重用後，交給 AppKit 管理前景與鍵盤焦點。
        detailWindow?.makeKeyAndOrderFront(nil)
    }

    /// 未回報電量時保留圖示；數字基準線下移 1 pt 與圖示對齊。
    ///
    /// - Parameters:
    ///   - connected: 耳機控制通道是否已連線。
    ///   - batteryLeft: 左耳有效電量百分比，nil 表示尚未回報。
    ///   - batteryRight: 右耳有效電量百分比，nil 表示尚未回報。
    func updateIcon(connected: Bool, batteryLeft: Int?, batteryRight: Int?) {
        // 原生選單列錨點或按鈕尚未建立時保留現況。
        guard let button = statusItem.button else { return }
        let charge = [batteryLeft, batteryRight].compactMap { $0 }.min()
        let text = connected ? charge.map { " \($0)%" } ?? "" : ""
        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .baselineOffset: -1,
            ])
        // 跨越連線狀態才更新面板版面，電量通知只改選單列文字。
        if popover.isShown && panelConnectionState != connected { showPanel() }
        popover.appearance =
            bluetooth.isDemo
            ? NSAppearance(named: bluetooth.previewDark ? .darkAqua : .aqua) : nil
    }
}

/// 原生工具列管理側欄切換、分隔線與共用導覽歷史。
extension StatusBarController: NSToolbarDelegate {
    private static let navigationIdentifier = NSToolbarItem.Identifier("SettingsHistory")
    /// 宣告原生項目與歷史控制，排列跟隨側欄分隔線。
    ///
    /// - Parameters:
    ///   - toolbar: 由 AppKit 管理的設定視窗工具列。
    /// - Returns: 原生側欄、分隔線與歷史導覽的可用工具列項目。
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, Self.navigationIdentifier, .flexibleSpace]
    }
    /// 初始配置沿用可用項目的閱讀順序。
    ///
    /// - Parameters:
    ///   - toolbar: 由 AppKit 管理的設定視窗工具列。
    /// - Returns: 依初始閱讀順序排列的工具列項目。
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }
    /// 建立有真實導覽動作的原生分段控制，其餘項目交回 AppKit。
    ///
    /// - Parameters:
    ///   - toolbar: 由 AppKit 管理的設定視窗工具列。
    ///   - identifier: AppKit 要求建立的工具列項目識別。
    ///   - flag: AppKit 回報項目是否將加入工具列，此方法依識別決定內容。
    /// - Returns: 歷史導覽工具列項目；其他原生項目回傳 nil，由 AppKit 建立。
    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        // 側欄切換與 tracking separator 是系統項目，保留預設建立流程。
        guard identifier == Self.navigationIdentifier else { return nil }
        let control = NSSegmentedControl(
            labels: [String(localized: "Back"), String(localized: "Forward")],
            trackingMode: .momentary, target: self, action: #selector(navigateHistory(_:)))
        // 使用系統符號及原生分段材質，輔助使用名稱走翻譯資源。
        // 返回與前進使用原生分段控制，圖示描述供輔助使用辨識。
        control.setImage(
            NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: String(localized: "Back")),
            forSegment: 0)
        control.setImage(
            NSImage(systemSymbolName: "chevron.forward", accessibilityDescription: String(localized: "Forward")),
            forSegment: 1)
        control.setLabel("", forSegment: 0)
        control.setLabel("", forSegment: 1)
        navigationControl = control
        refreshNavigation()
        // navigational 將控制放在右面板標題之前。
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.isNavigational = true
        item.label = String(localized: "Back")
        item.view = control
        return item
    }
    /// 分段索引 0 返回、1 前進，歷史邊界由共享模型驗證。
    ///
    /// - Parameters:
    ///   - sender: 原生歷史導覽控制，索引 0 返回、1 前進。
    @objc private func navigateHistory(_ sender: NSSegmentedControl) {
        // momentary 控制只回報被點按的方向，完成後由 AppKit 解除按下狀態。
        if sender.selectedSegment == 0 { settingsNavigation.goBack() } else { settingsNavigation.goForward() }
    }
    /// 同步視窗標題與原生按鈕可用狀態，不建立第二份選取快照。
    private func refreshNavigation() {
        detailWindow?.title = String(localized: String.LocalizationValue(settingsNavigation.selection.titleKey))
        navigationControl?.setEnabled(settingsNavigation.canGoBack, forSegment: 0)
        navigationControl?.setEnabled(settingsNavigation.canGoForward, forSegment: 1)
    }
}

/// 關閉設定窗即停止音訊 tap，避免隱藏視窗繼續改變其他 App 的播放。
extension StatusBarController: NSWindowDelegate {
    /// 設定視窗關閉停止音訊 tap 並還原耳機追蹤設定，選單列服務持續。
    ///
    /// - Parameters:
    ///   - notification: 系統送出的生命週期或選取通知，事件內容由框架提供。
    func windowWillClose(_ notification: Notification) {
        // 只處理本控制器持有的設定視窗，popover 保留自己的生命週期。
        guard let window = notification.object as? NSWindow, window === detailWindow else { return }
        spatialAudio.stop()
        bluetooth.setSpatialTracking(false)
    }
}
