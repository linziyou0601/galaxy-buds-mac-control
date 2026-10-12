import Foundation

/// 機型能力、服務識別與畫面數值範圍的發佈配置。
struct DeviceProfile: Codable, Sendable, Equatable {
    // 配置識別與協定來源用於載入驗證，名稱圖樣用於裝置辨識。
    let schemaVersion: Int
    let id: String
    let name: String
    let modelNumber: String
    let namePatterns: [String]
    let serviceUUIDs: [String]
    let protocolAdapter: String
    let defaultColor: String
    let colors: [ProductVariant]
    /// ANC 可選段數，傳輸值為 0 起算的索引。
    let ancSteps: Int
    /// 環境音傳輸值上限，控制範圍為 0...ambientMax。
    // 噪音與環境音範圍由機型提供，索引採 0 起算。
    let ambientMax: Int
    let ambientCustomMax: Int
    let ambientCommandTailOffsets: [Int]
    // 能力與分類共同決定可見功能，動作碼與欄位位置用於協定解析。
    let features: [DeviceFeature]
    let settingsCategories: [SettingsCategory]
    let quickControls: [QuickControl]
    let developmentFeatures: [FeatureDevelopment]
    let additionalSettings: [AdditionalSetting]
    let additionalStatusOffsets: [String: Int]
    let touchActionCodes: [String: Int]
    let assistantStatusOffset: Int?
    let assistantMinimumRevision: Int
    let assistantOverridesAction: Bool
    let assistantProviders: [String: UInt8]
    let touchTailOffsets: [Int?]
    // 韌體來源、診斷旗標與盒子識別長度也依機型注入。
    let firmware: FirmwareProfile
    let diagnosticChecks: [DiagnosticCheck]
    let cradleVersionLength: Int
    let cradleSerialLength: Int

    /// 拒絕未知 schema、協定版本與超出控制項範圍的數值。
    ///
    /// - Throws: schema、能力、來源與數值範圍不符合配置規則時拋出 ProfileError。
    func validate() throws {
        let deviceIDs = colors.flatMap(\.deviceIDs)
        // 來源配置需同時通過值域、HTTPS 來源、能力與欄位一致性檢查。
        guard (0...10).contains(ambientCustomMax), ambientCommandTailOffsets.count == 3,
            ambientCommandTailOffsets.allSatisfy({ (0...1020).contains($0) }),
            // 韌體資訊與封存來源使用 HTTPS，最低電量限制為有效百分比。
            firmware.officialInformationURL.scheme == "https", firmware.officialInformationURL.host != nil,
            (1...100).contains(firmware.minimumBatteryPercent),
            firmware.archiveBaseURL.scheme == "https", firmware.archiveBaseURL.host != nil,
            !firmware.archiveModel.isEmpty,
            !firmware.buildPrefix.isEmpty, !firmware.imagePattern.isEmpty,
            Set(diagnosticChecks.map(\.bit)).count == diagnosticChecks.count,
            diagnosticChecks.allSatisfy({ (0..<32).contains($0.bit) && !$0.labelKey.isEmpty }),
            // 分類不可重複，且功能頁與對應能力保持一致。
            Set(settingsCategories).count == settingsCategories.count,
            settingsCategories.contains(.general), settingsCategories.contains(.about),
            settingsCategories.contains(.head) == features.contains(.headGestures),
            settingsCategories.contains(.spatial) == features.contains(.spatialAudio),
            settingsCategories.contains(.firmware) == features.contains(.firmwareUpdate),
            // 開發狀態需有有效說明與 HTTPS 參考，避免介面缺少可追溯資訊。
            developmentFeatures.allSatisfy({
                !$0.reasonKey.isEmpty
                    && $0.references.allSatisfy({ $0.url.scheme == "https" && $0.url.host != nil && !$0.title.isEmpty })
            }),
            Set(developmentFeatures.map(\.id)).count == developmentFeatures.count,
            developmentFeatures.allSatisfy({ !$0.id.isEmpty }), !touchActionCodes.isEmpty,
            // 長按動作與助理提供者必須使用已知語意及可編碼範圍。
            touchActionCodes.keys.allSatisfy({ TouchHoldAction(rawValue: $0) != nil }),
            touchActionCodes.values.allSatisfy({ (0...15).contains($0) }),
            Set(touchActionCodes.values).count == touchActionCodes.count,
            assistantStatusOffset.map({ (0...1020).contains($0) }) ?? true,
            (0...255).contains(assistantMinimumRevision),
            assistantProviders.keys.allSatisfy({ TouchHoldAction(rawValue: $0) != nil }),
            assistantProviders.values.allSatisfy({ (1...2).contains($0) }),
            // 進階設定與 offset 一一對應，欄位不能超出協定封包範圍。
            Set(additionalStatusOffsets.keys) == Set(additionalSettings.map(\.rawValue)),
            additionalStatusOffsets.values.allSatisfy({ (0...1020).contains($0) }),
            touchTailOffsets.count == 2, touchTailOffsets.compactMap({ $0 }).allSatisfy({ (0...1020).contains($0) }),
            (1...32).contains(cradleVersionLength), (1...32).contains(cradleSerialLength),
            Set(additionalSettings.map(\.rawValue)).count == additionalSettings.count,
            Set(deviceIDs).count == deviceIDs.count,
            Set(quickControls.map(\.rawValue)).count == quickControls.count, !colors.isEmpty,
            colors.contains(where: { $0.id == defaultColor }),
            Set(colors.map(\.id)).count == colors.count,
            colors.allSatisfy({ $0.isValid }), schemaVersion == 1, !id.isEmpty, !name.isEmpty, !namePatterns.isEmpty,
            namePatterns.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
            !serviceUUIDs.isEmpty, serviceUUIDs.allSatisfy({ UUID(uuidString: $0) != nil }),
            protocolAdapter == "spp-modern", (2...10).contains(ancSteps),
            (0...10).contains(ambientMax)
        else {
            throw ProfileError.invalid(id)
        }
    }
}

/// 顏色對應的耳機與充電盒素材，deviceIDs 為耳機回報的 UInt16 型號色碼。
struct ProductVariant: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let deviceIDs: [Int]
    let earbuds: ProductAsset
    let chargingCase: ProductAsset
    var isValid: Bool {
        !id.isEmpty && !label.isEmpty && !deviceIDs.isEmpty
            && deviceIDs.allSatisfy { (0...65535).contains($0) } && earbuds.isValid && chargingCase.isValid
    }
}

/// PNG 素材與可見內容的像素矩形，依序為 x、y、寬、高。
struct ProductAsset: Codable, Equatable, Sendable {
    let name: String
    let bounds: [Double]
    var isValid: Bool {
        !name.isEmpty && !name.contains("/") && bounds.count == 4
            && bounds.allSatisfy { $0.isFinite && $0 >= 0 } && bounds[2] > 0 && bounds[3] > 0
    }
}

extension DeviceProfile {
    /// 手動選色優先，其次採用裝置色碼，未知色碼使用明確配置的示意色。
    ///
    /// - Parameters:
    ///   - reportedID: 耳機回報的產品色碼，nil 表示未回報。
    ///   - overrideID: 使用者保存的手動配色 ID，nil 表示沒有覆寫。
    /// - Returns: 有效手動覆寫、回報色碼或配置指定的預設產品配色。
    func variant(reportedID: Int?, overrideID: String?) -> ProductVariant {
        // 有效的手動配色優先於裝置回報。
        if let overrideID, let match = colors.first(where: { $0.id == overrideID }) { return match }
        // 沒有有效手動覆寫時，依裝置色碼查詢產品素材。
        if let reportedID, let match = colors.first(where: { $0.deviceIDs.contains(reportedID) }) { return match }
        return colors.first(where: { $0.id == defaultColor })!
    }
}

enum ProfileError: Error {
    case invalid(String)
    case duplicate(String)
    case empty
}

/// 依 JSON 檔案載入的機型集合。
struct ProfileCatalog: Sendable {
    let profiles: [DeviceProfile]

    /// 載入目錄內全部 JSON，遇到無效或重複機型時拋出錯誤。
    ///
    /// - Parameters:
    ///   - directory: 包含機型 JSON 的本機目錄。
    /// - Throws: 配置目錄無法讀取、JSON 解析失敗、無效或重複機型時傳遞錯誤。
    init(directory: URL) throws {
        // 先列舉機型 JSON，再逐份解析與驗證，檔名排序讓載入可重現。
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        var items: [DeviceProfile] = []
        // 檔名排序後逐份驗證，無效或重複配置立即停止載入。
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let profile = try JSONDecoder().decode(DeviceProfile.self, from: Data(contentsOf: url))
            try profile.validate()
            // 每個機型 ID 必須唯一，避免配置順序影響機型選擇。
            guard !items.contains(where: { $0.id == profile.id }) else {
                throw ProfileError.duplicate(profile.id)
            }
            items.append(profile)
        }
        // 至少一份有效機型配置才能建立資料庫。
        guard !items.isEmpty else { throw ProfileError.empty }
        profiles = items
    }

    static let bundled: ProfileCatalog = {
        let root: URL
        // App bundle 的資源位置有效時，從打包後的 Profiles 載入。
        if let resources = Bundle.main.resourceURL,
            FileManager.default.fileExists(atPath: resources.appendingPathComponent("Profiles").path)
        {
            root = resources
        } else {
            // 本機測試或套件執行使用對應資源位置，仍沿用相同驗證。
            #if SWIFT_PACKAGE
                root = Bundle.module.resourceURL!
            #else
                root = Bundle.main.resourceURL!
            #endif
        }
        do { return try ProfileCatalog(directory: root.appendingPathComponent("Profiles")) } catch {
            fatalError("Invalid bundled device profiles: \(error)")
        }
    }()

    /// 以配置中的名稱片段辨識機型，未知名稱回傳 nil。
    ///
    /// - Parameters:
    ///   - name: 系統回報的裝置名稱，依配置中的名稱圖樣辨識機型。
    /// - Returns: 符合名稱圖樣的機型；沒有匹配時回傳 nil。
    func detect(_ name: String) -> DeviceProfile? {
        let normalized = name.lowercased().filter { !$0.isWhitespace }
        return profiles.first { profile in
            profile.namePatterns.contains { normalized.contains($0.lowercased().filter { !$0.isWhitespace }) }
        }
    }
}

/// 發佈配置中的開發狀態，與耳機執行期能力回報分開。
struct FeatureDevelopment: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let status: DevelopmentStatus
    let reasonKey: String
    let references: [Reference]

    struct Reference: Codable, Sendable, Equatable, Identifiable {
        let title: String
        let url: URL
        var id: URL { url }
    }

    enum DevelopmentStatus: String, Codable, Sendable {
        case implemented, verified, partialSupport, platformUnavailable, protocolUnavailable, resourceUnavailable
        var displayName: String {
            // 功能分類對應固定語意標題，顯示範圍另由機型配置控制。
            switch self {
            // 程式已實作、硬體仍待驗收對應此翻譯鍵，顯示文字由語系資源提供。
            case .implemented: "Implemented; hardware validation pending"
            // 已完成驗證對應此翻譯鍵，顯示文字由語系資源提供。
            case .verified: "Verified"
            // 部分支援對應此翻譯鍵，顯示文字由語系資源提供。
            case .partialSupport: "Partially supported"
            // 平台 API 未提供對應此翻譯鍵，顯示文字由語系資源提供。
            case .platformUnavailable: "Unavailable on this platform"
            // 完整協定未確認對應此翻譯鍵，顯示文字由語系資源提供。
            case .protocolUnavailable: "Complete protocol unavailable"
            // 有效素材來源未確認對應此翻譯鍵，顯示文字由語系資源提供。
            case .resourceUnavailable: "Verified resource source unavailable"
            }
        }
    }

}

/// 設定分類由機型配置選取，共享標題鍵與符號識別保存在此領域型別。
enum SettingsCategory: String, Codable, Sendable, Identifiable {
    case general, sound, quality, equalizer, controls, voice, head, spatial, firmware, connections, advanced,
        accessibility, find, about
    var id: String { rawValue }

    /// App 維護頁面可在沒有控制通道時操作，其餘頁面依裝置回報提供。
    var availableWithoutConnection: Bool {
        [.general, .connections, .about].contains(self)
    }

    /// 分類標題的翻譯鍵，提供側欄、搜尋與視窗標題共用。
    var titleKey: String {
        // 分類圖示使用一致的 SF Symbols metadata。
        switch self {
        // 一般設定對應此翻譯鍵，顯示文字由語系資源提供。
        case .general: "General"
        // 聆聽模式對應此翻譯鍵，顯示文字由語系資源提供。
        case .sound: "Listening Mode"
        // 音質與音效對應此翻譯鍵，顯示文字由語系資源提供。
        case .quality: "Sound quality and effects"
        // 等化器對應此翻譯鍵，顯示文字由語系資源提供。
        case .equalizer: "Equalizer"
        // 耳機操作對應此翻譯鍵，顯示文字由語系資源提供。
        case .controls: "Earbud Controls"
        // 語音控制對應此翻譯鍵，顯示文字由語系資源提供。
        case .voice: "Voice controls"
        // 頭部動作對應此翻譯鍵，顯示文字由語系資源提供。
        case .head: "Head gestures"
        // 空間音訊對應此翻譯鍵，顯示文字由語系資源提供。
        case .spatial: "Spatial audio"
        // 韌體對應此翻譯鍵，顯示文字由語系資源提供。
        case .firmware: "Firmware"
        // 連線管理對應此翻譯鍵，顯示文字由語系資源提供。
        case .connections: "Manage connections"
        // 進階功能對應此翻譯鍵，顯示文字由語系資源提供。
        case .advanced: "Advanced features"
        // 協助工具對應此翻譯鍵，顯示文字由語系資源提供。
        case .accessibility: "Accessibility"
        // 尋找耳機對應此翻譯鍵，顯示文字由語系資源提供。
        case .find: "Find Earbuds"
        // 關於與診斷對應此翻譯鍵，顯示文字由語系資源提供。
        case .about: "About & Diagnostics"
        }
    }
    /// 分類使用的 SF Symbol 名稱，與機型能力選取分開。
    var icon: String {
        // 分類說明依功能責任提供搜尋與介面文字。
        switch self {
        // 一般設定對應此翻譯鍵，顯示文字由語系資源提供。
        case .general: "gearshape"
        // 聆聽模式使用 SF Symbol「ear.badge.waveform」。
        case .sound: "ear.badge.waveform"
        // 音質與音效使用 SF Symbol「speaker.wave.2」。
        case .quality: "speaker.wave.2"
        // 等化器使用 SF Symbol「slider.horizontal.3」。
        case .equalizer: "slider.horizontal.3"
        // 耳機操作使用 SF Symbol「hand.tap」。
        case .controls: "hand.tap"
        // 語音控制對應此翻譯鍵，顯示文字由語系資源提供。
        case .voice: "mic"
        // 頭部動作使用 SF Symbol「person.crop.circle」。
        case .head: "person.crop.circle"
        // 空間音訊對應此翻譯鍵，顯示文字由語系資源提供。
        case .spatial: "headphones"
        // 韌體使用 SF Symbol「arrow.down.circle」。
        case .firmware: "arrow.down.circle"
        // 連線管理使用 SF Symbol「arrow.triangle.2.circlepath」。
        case .connections: "arrow.triangle.2.circlepath"
        // 進階功能使用 SF Symbol「gearshape.2」。
        case .advanced: "gearshape.2"
        // 協助工具對應此翻譯鍵，顯示文字由語系資源提供。
        case .accessibility: "accessibility"
        // 尋找耳機對應此翻譯鍵，顯示文字由語系資源提供。
        case .find: "bell"
        // 關於與診斷使用 SF Symbol「info.circle」。
        case .about: "info.circle"
        }
    }
}

/// 已實作能力的配置識別，未知值在解碼邊界被拒絕。
enum DeviceFeature: String, Codable, Sendable {
    case anc, ambient, adaptive, customEQ, bladeLights, headGestures, spatialAudio, hardwareDiagnostics, firmwareUpdate
}

/// 韌體來源與映像識別由機型配置提供。
struct FirmwareProfile: Codable, Sendable, Equatable {
    let officialInformationURL: URL
    let minimumBatteryPercent: Int
    let archiveBaseURL: URL
    let archiveModel: String
    let buildPrefix: String
    let imagePattern: String
}

/// 自我測試的結果位元與名稱由機型配置提供。
struct DiagnosticCheck: Codable, Sendable, Equatable, Identifiable {
    let bit: Int
    let labelKey: String
    var id: Int { bit }
}
