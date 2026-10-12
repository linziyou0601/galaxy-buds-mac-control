import Foundation

/// 第三方封存目錄的型號與 build 欄位，年月表示版本建置月份。
struct FirmwareRelease: Decodable, Identifiable, Sendable {
    let buildName: String
    let model: String
    let year: Int?
    let month: Int?
    let revision: Int?

    var id: String { buildName }

    /// 依使用者語系格式化建置年月與修訂碼，保留來源未提供的欄位。
    var releaseDescription: String {
        var parts: [String] = []
        // 來源年月有效時交由 Gregorian Calendar 與原生 formatter 顯示。
        if let year, let month, (1...12).contains(month) {
            var components = DateComponents()
            components.year = year
            components.month = month
            // 日期可由來源欄位構成才顯示，未提供時只保留修訂資訊。
            if let date = Calendar(identifier: .gregorian).date(from: components) {
                let formatter = DateFormatter()
                formatter.setLocalizedDateFormatFromTemplate("yMMMM")
                parts.append(formatter.string(from: date))
            }
        }
        // 修訂碼是版本後綴，與官方發佈日期分開判讀。
        if let revision {
            parts.append(String(localized: "revision") + " \(revision)")
        }
        return parts.joined(separator: " · ")
    }
}

/// 封存查詢的型號、HTTP 與下載內容錯誤。
enum FirmwareCatalogError: LocalizedError {
    case unsupportedModel
    case server(status: Int)
    case notFirmware

    var errorDescription: String? {
        // 來源錯誤區分機型、HTTP 回覆與空內容，供下載介面顯示。
        switch self {
        // 來源不符合目前機型時，拒絕下載。
        case .unsupportedModel:
            return String(localized: "No firmware is published for this model.")
        // HTTP 來源錯誤保留狀態碼，供使用者排查。
        case .server(let status):
            return String(localized: "The firmware archive couldn't be reached.") + " (\(status))"
        // 空下載內容不能作為韌體映像。
        case .notFirmware:
            return String(localized: "The download wasn't a firmware image.")
        }
    }
}

/// 依注入的機型與來源查詢韌體，只接受來源回報的相符機型。
struct FirmwareCatalog: Sendable {

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    /// 以注入來源讀取目錄，過濾相符機型及版本系列後由新至舊排序。
    /// HTTP 或解碼失敗向呼叫者拋出，網路取消由 URLSession 傳遞。
    ///
    /// - Parameters:
    ///   - model: 目前操作的機型，能力、命令與來源由其配置提供。
    /// - Returns: 符合機型與版本系列的封存項目，依新至舊排序。
    /// - Throws: 目錄來源、HTTP、JSON 解碼失敗或網路取消時傳遞錯誤。
    func releases(for model: BudsModel) async throws -> [FirmwareRelease] {
        let name = model.profile.firmware.archiveModel
        let url = model.profile.firmware.archiveBaseURL.appending(path: "firmware").appending(path: name)
        let (data, response) = try await Self.session.data(from: url)
        try Self.check(response)
        let releases = try JSONDecoder().decode([FirmwareRelease].self, from: data)
        return releases.filter { $0.model == name && $0.buildName.hasPrefix(model.profile.firmware.buildPrefix) }.sorted
        { FirmwareVersion.isNewer($0.buildName, than: $1.buildName) }
    }

    /// 下載注入機型的封存映像，回傳完整 Data，結構驗證由 FirmwareBinary 執行。
    /// - Throws: 型號不符、HTTP 錯誤、空內容或網路取消。
    ///
    /// - Parameters:
    ///   - release: 來源目錄中選取的韌體項目，包含機型、版本與下載識別。
    ///   - profile: 目前裝置的已驗證機型配置，決定欄位位置、能力與範圍。
    /// - Returns: 來源提供的完整映像資料，結構與 CRC 由 FirmwareBinary 另行驗證。
    func download(_ release: FirmwareRelease, profile: DeviceProfile) async throws -> Data {
        // 來源項目必須符合已注入的模型，拒絕跨機型下載。
        guard release.model == profile.firmware.archiveModel, release.buildName.hasPrefix(profile.firmware.buildPrefix)
        else { throw FirmwareCatalogError.unsupportedModel }
        let url = profile.firmware.archiveBaseURL
            .appending(path: "firmware")
            .appending(path: "download")
            .appending(path: release.buildName)
        let (data, response) = try await Self.session.data(from: url)
        try Self.check(response)
        // 最小映像表頭不足時先回報下載內容錯誤。
        guard data.count > 16 else { throw FirmwareCatalogError.notFirmware }
        return data
    }

    /// 2xx 表示來源回應成功，HTTP 失敗保留狀態碼供 UI 排查。
    ///
    /// - Parameters:
    ///   - response: URLSession 提供的來源回覆，HTTP 狀態碼需為 2xx。
    /// - Throws: 底層錯誤碼或 HTTP 回覆未通過檢查時拋出錯誤。
    private static func check(_ response: URLResponse) throws {
        // URLSession 的 HTTP 來源回應使用標準 HTTPURLResponse。
        guard let http = response as? HTTPURLResponse else { return }
        // HTTP 錯誤本文不能視為韌體或目錄。
        guard (200..<300).contains(http.statusCode) else {
            throw FirmwareCatalogError.server(status: http.statusCode)
        }
    }
}

/// 同機型、同版本系列的版本比較，先比較 bootloader，再比較年月與修訂。
enum FirmwareVersion {
    private static let order = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    /// 比較相同型號版本系列的 12 字元碼，未知格式或相同版本回傳 false。
    ///
    /// - Parameters:
    ///   - candidate: 欲比較的 Samsung 韌體版本碼。
    ///   - current: 目前已安裝的 Samsung 韌體版本碼。
    /// - Returns: 同機型、同系列且候選較新時為 true，未知格式、相同或較舊版本為 false。
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        // 型號與系列不符時，單純字串排序無法判斷更新資格。
        guard current.count == 12, candidate.count == 12, current.prefix(6) == candidate.prefix(6) else { return false }
        let currentSuffix = Array(current)
        let candidateSuffix = Array(candidate)
        // 韌體排序依已確認的版本欄位逐位比較，未知格式先由入口拒絕。
        for index in [7, 9, 10, 11] {
            // bootloader、年份、月份與修訂只接受已知 Samsung 編碼字元。
            guard let currentRank = order.firstIndex(of: currentSuffix[index]),
                let candidateRank = order.firstIndex(of: candidateSuffix[index])
            else { return false }
            // 第一個不同的語意欄位決定先後，其餘欄位只在相同時繼續。
            if currentRank != candidateRank { return currentRank < candidateRank }
        }
        return false
    }
}
