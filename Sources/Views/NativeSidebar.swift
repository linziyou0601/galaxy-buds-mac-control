import AppKit
import SwiftUI

/// 原生 source list 提供灰色選取、鍵盤導覽及系統捲軸。
struct NativeSidebar: NSViewRepresentable {
    let pages: [SettingsCategory]
    @Binding var selection: SettingsCategory

    /// 建立回呼橋接，協調員持有最新 binding 與分類快照。
    ///
    /// - Returns: 保存此 View binding 與原生回呼的 coordinator。
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    /// 建立原生 source list，38 pt 列高與內距遵循 App Store 參考版面。
    ///
    /// - Parameters:
    ///   - context: SwiftUI 提供的橋接環境，包含此 View 的 coordinator。
    /// - Returns: 已配置資料來源的側欄捲動容器。
    func makeNSView(context: Context) -> NSScrollView {
        // 系統 source list 管理選取、鍵盤、背景與資料列重用。
        // 原生 sourceList 管理選取與列高，資料與事件由 coordinator 提供。
        let table = NSTableView()
        table.style = .sourceList
        table.headerView = nil
        table.rowHeight = 38
        table.intercellSpacing = .zero
        table.allowsEmptySelection = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Category"))
        table.addTableColumn(column)
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        // 原生捲軸依系統偏好顯示，內容內距保留分隔線旁的空間。
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 10, bottom: 10, right: 10)
        scroll.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 4)
        scroll.documentView = table
        return scroll
    }
    /// 同步分類與選取，程式更新期間抑制 delegate 回寫，避免重入。
    ///
    /// - Parameters:
    ///   - scroll: 承載原生側欄資料表的捲動容器。
    ///   - context: SwiftUI 提供的橋接環境，包含此 View 的 coordinator。
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        // 由 makeNSView 建立的表格才接收 SwiftUI 快照。
        guard let table = scroll.documentView as? NSTableView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.updating = true
        // 搜尋或機型能力改變時才重載資料列。
        if coordinator.pages != pages {
            coordinator.pages = pages
            table.reloadData()
        }
        // 側欄與歷史導覽使用同一份選取，保持原生鍵盤游標同步。
        if let row = pages.firstIndex(of: selection), table.selectedRow != row {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        coordinator.updating = false
    }
    /// NSViewRepresentable 的原生資料來源、選取與可重用資料列橋接。
    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: NativeSidebar
        var pages: [SettingsCategory] = []
        var updating = false
        /// 保存建立時的 binding，updateNSView 會更新最新 View 快照。
        ///
        /// - Parameters:
        ///   - parent: 目前 View 與 binding 快照，由原生 coordinator 保存。
        init(_ parent: NativeSidebar) { self.parent = parent }
        /// 使用系統資料列的非強調選取，深淺背景由 AppKit 繪製。
        ///
        /// - Parameters:
        ///   - tableView: AppKit 要求讀取資料或處理選取的側欄資料表。
        ///   - row: 以 0 起算的資料列索引，對應目前篩選後的分類清單。
        /// - Returns: 系統資料列的非強調選取樣式。
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            UnemphasizedRow()
        }
        /// App Store 參考要求選取保持灰色，覆寫狀態而沿用原生繪製。
        private final class UnemphasizedRow: NSTableRowView {
            override var isEmphasized: Bool {
                get { false }
                set {}
            }
        }
        /// 原生資料來源取得目前搜尋及能力篩選後的分類數量。
        ///
        /// - Parameters:
        ///   - tableView: AppKit 要求讀取資料或處理選取的側欄資料表。
        /// - Returns: 目前已篩選分類的數量。
        func numberOfRows(in tableView: NSTableView) -> Int { pages.count }
        /// 使用者選取有效資料列時回寫 binding，程式同步期間保留快照。
        ///
        /// - Parameters:
        ///   - notification: 系統送出的生命週期或選取通知，事件內容由框架提供。
        func tableViewSelectionDidChange(_ notification: Notification) {
            // 空清單、失效列索引及重載期間的通知不代表新的使用者選取。
            guard !updating, let table = notification.object as? NSTableView,
                pages.indices.contains(table.selectedRow)
            else { return }
            parent.selection = pages[table.selectedRow]
        }
        /// 重用原生資料列並填入翻譯與 SF Symbol，圖示維持自然比例。
        ///
        /// - Parameters:
        ///   - tableView: AppKit 要求讀取資料或處理選取的側欄資料表。
        ///   - tableColumn: AppKit 提供的欄位，此側欄使用單欄分類資料。
        ///   - row: 以 0 起算的資料列索引，對應目前篩選後的分類清單。
        /// - Returns: 填入分類名稱與 SF Symbol 的可重用側欄資料列。
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("CategoryCell")
            let cell: NSTableCellView
            // 原生表格重用可見資料列，只有首次出現時建立控制項。
            if let existing = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
                cell = existing
            } else {
                // 系統沒有可重用資料列時，建立自然比例圖示與文字元件。
                cell = NSTableCellView()
                cell.identifier = identifier
                // 圖示與標題使用原生元件，建立後交給資料列持有。
                let image = NSImageView()
                let text = NSTextField(labelWithString: "")
                image.imageScaling = .scaleNone
                image.translatesAutoresizingMaskIntoConstraints = false
                text.translatesAutoresizingMaskIntoConstraints = false
                text.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
                text.lineBreakMode = .byTruncatingTail
                cell.addSubview(image)
                cell.addSubview(text)
                cell.imageView = image
                cell.textField = text
                // 固定圖示槽及文字起點，長文字以原生截斷呈現。
                // 圖示區域維持自然比例，標題與圖示對齊且保留捲軸內距。
                NSLayoutConstraint.activate([
                    image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                    image.centerYAnchor.constraint(equalTo: text.centerYAnchor),
                    image.widthAnchor.constraint(equalToConstant: 24),
                    image.heightAnchor.constraint(equalToConstant: 28),
                    text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
                    text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
                ])
            }
            let page = pages[row]
            cell.textField?.stringValue = String(localized: String.LocalizationValue(page.titleKey))
            // 配置符號字級而保留自然尺寸，高形符號不縮入正方形。
            if let image = NSImage(systemSymbolName: page.icon, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))
            {
                // SF Symbols 的字型對齊框適合文字基線，圖示槽使用完整影像範圍保持比例。
                image.alignmentRect = NSRect(origin: .zero, size: image.size)
                cell.imageView?.image = image
            }
            cell.imageView?.contentTintColor = .controlAccentColor
            return cell
        }
    }
}
