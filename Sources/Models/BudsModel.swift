import Foundation

/// 機型能力與識別資料由隨 App 打包的 JSON 載入。
struct BudsModel: Hashable, Identifiable, Sendable, CaseIterable {
    let profile: DeviceProfile
    var id: String { profile.id }
    var name: String { profile.name }
    static var allCases: [BudsModel] { ProfileCatalog.bundled.profiles.map { BudsModel(profile: $0) } }
    static var defaultModel: BudsModel { allCases.last! }
    /// 依已驗證配置的名稱圖樣辨識機型，未知名稱回傳 nil。
    ///
    /// - Parameters:
    ///   - name: 系統回報的裝置名稱，依配置中的名稱圖樣辨識機型。
    /// - Returns: 符合名稱圖樣的機型；沒有匹配時回傳 nil。
    static func detect(from name: String) -> BudsModel? {
        ProfileCatalog.bundled.detect(name).map { BudsModel(profile: $0) }
    }
    /// 以完整配置判斷兩個機型是否相同。
    ///
    /// - Parameters:
    ///   - lhs: 等值比較的左側機型。
    ///   - rhs: 等值比較的右側機型。
    /// - Returns: 兩側完整機型配置相同時為 true。
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.profile == rhs.profile }
    /// 機型識別用於集合與原生選取，對應配置中唯一的 id。
    ///
    /// - Parameters:
    ///   - hasher: Swift 集合提供的雜湊累加器，將機型 ID 加入其中。
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    /// 查詢注入的能力集合，控制顯示與命令範圍共用配置。
    ///
    /// - Parameters:
    ///   - feature: 要查詢的機型能力。
    /// - Returns: 注入的機型配置包含該能力時為 true。
    private func supports(_ feature: DeviceFeature) -> Bool { profile.features.contains(feature) }
    // 便捷屬性只讀取機型配置，能力與數值上限維持單一來源。
    var serviceUUIDCandidates: [String] { profile.serviceUUIDs }
    var supportsANC: Bool { supports(.anc) }
    var supportsAdaptiveANC: Bool { supports(.adaptive) }
    var supportsCustomEqualizer: Bool { supports(.customEQ) }
    var ancLevelCount: Int { profile.ancSteps }
    var maxAmbientVolume: Int { profile.ambientMax }
    var listenModes: [NoiseControlMode] {
        [.off] + (supports(.ambient) ? [.ambient] : [])
            + (supportsAdaptiveANC ? [.adaptive] : []) + (supportsANC ? [.anc] : [])
    }
}
