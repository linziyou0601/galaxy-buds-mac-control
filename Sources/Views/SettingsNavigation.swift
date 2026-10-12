import SwiftUI

/// AppKit 工具列與 SwiftUI 側欄共用的視窗呈現狀態。
@Observable @MainActor
final class SettingsNavigation {
    // 視窗持有的導覽快照與回呼，工具列和側欄共用同一個游標。
    private var history: [SettingsCategory] = [.general]
    private var historyIndex = 0
    private var availableCategories: Set<SettingsCategory> = [.general, .about]
    var columnVisibility: NavigationSplitViewVisibility = .all
    @ObservationIgnored var onChange: (() -> Void)?

    /// 切換分類時截斷前進路徑，歷史操作保留游標指定的快照。
    var selection: SettingsCategory = .general {
        didSet {
            // 未配置的頁面不能由側欄、頁內連結或歷史導覽打開。
            guard availableCategories.contains(selection) else {
                selection = oldValue
                return
            }
            // 相同分類不產生歷史項目或工具列刷新。
            guard selection != oldValue else { return }
            // 游標未指向新分類時，這是側欄或頁內連結的新導覽。
            if history[historyIndex] != selection {
                history = Array(history.prefix(historyIndex + 1)) + [selection]
                historyIndex = history.count - 1
            }
            onChange?()
        }
    }
    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex + 1 < history.count }
    /// 注入當前機型的頁面集合，移除跨機型歷史並保留有效游標。
    ///
    /// - Parameters:
    ///   - categories: 目前機型配置的有效分類順序。
    func updateAvailableCategories(_ categories: [SettingsCategory]) {
        availableCategories = Set(categories)
        // 計算原游標之前仍有效的歷史數量，保留相同閱讀位置。
        let validPrefixCount = history.prefix(historyIndex + 1).filter { availableCategories.contains($0) }.count
        history = history.filter { availableCategories.contains($0) }
        // JSON 配置保證包含一般頁，空歷史使用該共同入口。
        if history.isEmpty { history = [.general] }
        historyIndex = max(0, min(history.count - 1, validPrefixCount - 1))
        // 目前分類不再可用時，回到已保留的有效歷史項目。
        if !availableCategories.contains(selection) { selection = history[historyIndex] }
        onChange?()
    }

    /// 返回歷史中的上一個分類，游標在邊界時保留現況。
    func goBack() {
        // 原生按鈕的停用狀態與服務邊界使用相同判定。
        guard canGoBack else { return }
        historyIndex -= 1
        selection = history[historyIndex]
    }
    /// 前進到保留的下一個分類，游標在邊界時保留現況。
    func goForward() {
        // 新導覽已截斷前進快照，無下一筆時不移動游標。
        guard canGoForward else { return }
        historyIndex += 1
        selection = history[historyIndex]
    }
}
