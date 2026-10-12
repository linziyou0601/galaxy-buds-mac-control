import Foundation

/// 跨機型頁面與前進、返回歷史的狀態驗證。
@MainActor struct NavigationTests {
    /// 換機型清除不支援分類，新導覽截斷前進路徑，直接指定未知頁面維持現況。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testHistoryFollowsModelCategories() throws {
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        let withHead = try require(catalog.profiles.first { $0.features.contains(.headGestures) })
        let withoutHead = try require(catalog.profiles.first { !$0.features.contains(.headGestures) })
        let navigation = SettingsNavigation()
        // 具頭部動作能力的機型建立包含該頁面的歷史。
        navigation.updateAvailableCategories(withHead.settingsCategories)
        navigation.selection = .head
        navigation.selection = .voice
        navigation.goBack()
        try check(navigation.selection == .head && navigation.canGoForward)
        // 換到另一個機型時移除頭部頁，保留仍有效的前進路徑。
        navigation.updateAvailableCategories(withoutHead.settingsCategories)
        try check(navigation.selection == .general && navigation.canGoForward)
        navigation.goForward()
        try check(navigation.selection == .voice)
        navigation.goBack()
        navigation.selection = .quality
        try check(!navigation.canGoForward && navigation.canGoBack)
        // 側欄、頁內連結或外部指定都不能繞過配置的頁面集合。
        navigation.selection = .head
        try check(navigation.selection == .quality)
        navigation.goBack()
        try check(navigation.selection == .general && !navigation.canGoBack)
    }
}
