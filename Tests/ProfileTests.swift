import Foundation

struct ProfileTests {
    /// 發佈配置辨識兩款目標機型及五段 ANC，其他名稱保持未知。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testBundledModelsAndNames() throws {
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        try check(Set(catalog.profiles.map(\.id)) == ["buds3Pro", "buds4Pro"])
        try check(catalog.detect("自訂名稱 Buds3 Pro")?.modelNumber == "SM-R630")
        try check(catalog.detect("Galaxy Buds4 Pro (ABCD)")?.id == "buds4Pro")
        try check(catalog.detect("Galaxy Buds2") == nil)
        try check(catalog.detect("Headphones") == nil)
        try check(catalog.profiles.allSatisfy { $0.ancSteps == 5 })
    }
    /// 未提供的協定 adapter、無效最低電量及 ANC 範圍在載入邊界被拒絕。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testRejectInvalidProfileAndUnsupportedAdapter() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        let original = try JSONEncoder().encode(catalog.profiles[0])
        var object = try require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        object["protocolAdapter"] = "unknown"
        try JSONSerialization.data(withJSONObject: object).write(to: folder.appendingPathComponent("invalid.json"))
        try rejects { _ = try ProfileCatalog(directory: folder) }
        object["protocolAdapter"] = "spp-modern"
        var firmware = try require(object["firmware"] as? [String: Any])
        firmware["minimumBatteryPercent"] = 101
        object["firmware"] = firmware
        try JSONSerialization.data(withJSONObject: object).write(to: folder.appendingPathComponent("invalid.json"))
        try rejects { _ = try ProfileCatalog(directory: folder) }
        firmware["minimumBatteryPercent"] = 30
        object["firmware"] = firmware
        object["ancSteps"] = 0
        try JSONSerialization.data(withJSONObject: object).write(to: folder.appendingPathComponent("invalid.json"))
        try rejects { _ = try ProfileCatalog(directory: folder) }
    }
    /// 已知色碼與手動覆寫應選出同一組耳機及盒子素材。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testColorResolutionAndOverrides() throws {
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        let expected: [String: [Int: String]] = [
            "buds3Pro": [340: "silver", 341: "white"],
            "buds4Pro": [359: "black", 360: "white", 361: "pinkGold"],
        ]
        // 兩款機型都需符合各自的產品配色目錄。
        for profile in catalog.profiles {
            let mappings = try require(expected[profile.id])
            try check(profile.colors.count == mappings.count)
            // 每個實際產品色碼都對應預期圖片組。
            for (deviceID, color) in mappings {
                let variant = profile.variant(reportedID: deviceID, overrideID: nil)
                try check(variant.id == color)
                try check(variant.earbuds.name.contains("-" + color + "-"))
                try check(variant.chargingCase.name.contains("-" + color + "-"))
                try check(profile.variant(reportedID: -1, overrideID: color).id == color)
            }
            try check(profile.variant(reportedID: nil, overrideID: nil).id == profile.defaultColor)
            try check(profile.variant(reportedID: 65535, overrideID: "missing").id == profile.defaultColor)
            let override = try require(profile.colors.last)
            try check(
                profile.variant(reportedID: profile.colors[0].deviceIDs[0], overrideID: override.id).id == override.id)
        }
    }

    /// 缺少顏色素材的配置須在載入邊界被拒絕。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testRejectEmptyColorCatalog() throws {
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        let data = try JSONEncoder().encode(catalog.profiles[0])
        var object = try require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["colors"] = []
        let invalid = try JSONDecoder().decode(DeviceProfile.self, from: JSONSerialization.data(withJSONObject: object))
        try rejects { try invalid.validate() }
    }

    /// 配置中的快捷項目須有實作，重複項目會破壞 UI 識別。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testQuickControlsRejectUnsupportedAndDuplicate() throws {
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        let encoded = try JSONEncoder().encode(catalog.profiles[0])
        var object = try require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["quickControls"] = ["unimplemented"]
        let unknown = try JSONSerialization.data(withJSONObject: object)
        try rejects { _ = try JSONDecoder().decode(DeviceProfile.self, from: unknown) }
        object["quickControls"] = ["touchpadLock", "touchpadLock"]
        let repeated = try JSONDecoder().decode(
            DeviceProfile.self, from: JSONSerialization.data(withJSONObject: object))
        try rejects { try repeated.validate() }
    }

    /// 配置缺少必要欄位、超出封包範圍或使用無效識別長度時拒絕載入。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testRejectIncompleteStatusLayout() throws {
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        let encoded = try JSONEncoder().encode(catalog.profiles[0])
        let original = try require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var incomplete = original
        var offsets = try require(incomplete["additionalStatusOffsets"] as? [String: Int])
        offsets.removeValue(forKey: "sirenDetection")
        incomplete["additionalStatusOffsets"] = offsets
        var badLength = original
        badLength["cradleVersionLength"] = 0
        var badOffset = original
        badOffset["touchTailOffsets"] = [NSNull(), 1024]
        // 缺少欄位、識別長度錯誤與越界 offset 都必須在載入時拒絕。
        for object in [incomplete, badLength, badOffset] {
            let profile = try JSONDecoder().decode(
                DeviceProfile.self, from: JSONSerialization.data(withJSONObject: object))
            try rejects { try profile.validate() }
        }
    }

    /// 頁面與開發狀態依注入配置載入，機型能力矛盾及未知分類會被拒絕。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testProfileDrivenInterface() throws {
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        let buds3 = try require(catalog.profiles.first { $0.id == "buds3Pro" })
        let buds4 = try require(catalog.profiles.first { $0.id == "buds4Pro" })
        try check(!buds3.settingsCategories.contains(.head) && buds4.settingsCategories.contains(.head))
        try check(!buds3.developmentFeatures.contains { $0.id == "headCallIntegration" })
        try check(buds4.developmentFeatures.contains { $0.id == "headCallIntegration" })
        var object = try require(JSONSerialization.jsonObject(with: JSONEncoder().encode(buds4)) as? [String: Any])
        object["settingsCategories"] = buds4.settingsCategories.filter { $0 != .voice }.map(\.rawValue)
        let injected = try JSONDecoder().decode(
            DeviceProfile.self, from: JSONSerialization.data(withJSONObject: object))
        try injected.validate()
        try check(!injected.settingsCategories.contains(.voice))
        try check(injected.developmentFeatures == buds4.developmentFeatures)
        object["settingsCategories"] = ["general", "about"]
        let inconsistent = try JSONDecoder().decode(
            DeviceProfile.self, from: JSONSerialization.data(withJSONObject: object))
        try rejects { try inconsistent.validate() }
        object["settingsCategories"] = ["general", "about", "invented"]
        try rejects {
            _ = try JSONDecoder().decode(DeviceProfile.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

}
