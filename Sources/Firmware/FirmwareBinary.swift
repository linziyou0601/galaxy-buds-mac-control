import Foundation

/// 韌體映像區段，包含裝置要求的識別、CRC 與完整資料。
struct FirmwareSegment: Sendable {
    let id: Int
    let crc32: UInt32
    let size: Int
    let data: Data
}

/// 韌體結構、機型、版本與區段完整性驗證錯誤。
enum FirmwareParseError: LocalizedError {
    case tooShort
    case badMagic
    case modelMismatch
    case versionMismatch
    case checksumMismatch
    case emptyImage
    case noSegments
    case truncatedSegment(id: Int)

    var errorDescription: String? {
        // 不同解析錯誤對應使用者能判讀的檔案、機型或校驗原因。
        switch self {
        // 資料截斷或區段內容不足時，顯示檔案不完整。
        case .tooShort, .truncatedSegment:
            return String(localized: "The firmware file is incomplete.")
        // 映像識別與機型不符時，阻止跨機型安裝。
        case .modelMismatch:
            return String(localized: "Firmware model does not match the connected earbuds.")
        // 檔名與內嵌版本不一致時，顯示版本標記錯誤。
        case .versionMismatch:
            return String(localized: "The firmware version does not match the filename.")
        // 區段 CRC 不符時，顯示校驗失敗。
        case .checksumMismatch:
            return String(localized: "Firmware checksum failed.")
        // 映像 magic 不符時，拒絕未知韌體格式。
        case .badMagic:
            return String(localized: "This file isn't Galaxy Buds firmware.")
        // 空映像或缺少區段時，顯示沒有可傳輸內容。
        case .emptyImage, .noSegments:
            return String(localized: "The firmware file contains no data.")
        }
    }
}

/// little-endian 映像：magic、總長、16-byte 區段表及末端映像 CRC。
struct FirmwareBinary: Sendable {
    static let magic: UInt32 = 0xCAFE_CAFE

    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        // 每個表項逐位計算八個位元的 IEEE 多項式餘數。
        for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        return crc
    }

    let buildName: String
    let totalSize: Int
    let crc32: UInt32
    let segments: [FirmwareSegment]

    /// 驗證完整映像與內嵌型號、版本，解析區段並逐段核對 CRC。
    /// - Parameters:
    ///   - data: 包含表頭、區段表、內容與末端 CRC 的完整檔案。
    ///   - buildName: 來源回報或檔名中的 Samsung 12 字元版本碼。
    ///   - profile: 注入的機型識別與韌體圖樣。
    /// - Throws: 結構、識別或區段 CRC 不一致時拋出 FirmwareParseError。
    init(data: Data, buildName: String, profile: DeviceProfile) throws {
        // 完整表頭與末端 CRC 至少佔 16 bytes，先限制後續讀取邊界。
        guard data.count >= 16 else { throw FirmwareParseError.tooShort }
        // 型號與版本圖樣從機型配置取得，拒絕跨機型檔案。
        guard
            let version = buildName.range(
                of: NSRegularExpression.escapedPattern(for: profile.firmware.buildPrefix) + "[A-Z0-9]{8}",
                options: .regularExpression),
            data.range(of: Data(profile.firmware.imagePattern.utf8)) != nil
        else { throw FirmwareParseError.modelMismatch }
        self.buildName = String(buildName[version])
        // 檔名宣告的版本必須實際存在於映像，避免錯誤標記更新。
        guard data.range(of: Data(self.buildName.utf8)) != nil else { throw FirmwareParseError.versionMismatch }

        var cursor = 0
        /// 在已驗證的範圍讀取 little-endian UInt32，游標前進 4 bytes。
        ///
        /// - Returns: 目前游標位置的 32-bit little-endian 整數，讀取後游標前進 4 bytes。
        func readUInt32() -> UInt32 {
            defer { cursor += 4 }
            return data.withUnsafeBytes { raw -> UInt32 in
                var value: UInt32 = 0
                // 從高位元組開始組合整數，維持 little-endian 與未對齊讀取安全。
                for offset in (0..<4).reversed() {
                    value = (value << 8) | UInt32(raw[cursor + offset])
                }
                return value
            }
        }

        // 只接受正式 CAFE 映像，其他 magic 包含除錯格式都拒絕。
        let magic = readUInt32()
        // 只接受正式映像 magic，其他格式交由錯誤處理。
        guard magic == Self.magic else { throw FirmwareParseError.badMagic }

        // 檔案總長必須相符，截斷與額外資料都不能交給更新服務。
        totalSize = Int(readUInt32())
        // 總長必須非零，空映像不能進入傳輸。
        guard totalSize > 0 else { throw FirmwareParseError.emptyImage }
        // 宣告長度必須與檔案一致，截斷或額外內容都視為無效。
        guard totalSize == data.count else { throw FirmwareParseError.tooShort }

        // 每個區段表項目佔 16 bytes，完整表格後還須保留末端 CRC。
        let segmentCount = Int(readUInt32())
        // 區段數限制為 1...255，確保可編碼成裝置協定欄位。
        guard segmentCount > 0, segmentCount <= 255 else { throw FirmwareParseError.noSegments }
        // 完整表頭與末端 CRC 至少佔 16 bytes，先限制後續讀取邊界。
        guard data.count >= 12 + segmentCount * 16 + 4 else { throw FirmwareParseError.tooShort }

        var parsed: [FirmwareSegment] = []
        parsed.reserveCapacity(segmentCount)
        // 每個區段獨立驗證識別、內容範圍與 CRC。
        for _ in 0..<segmentCount {
            let id = Int(readUInt32())
            let segmentCrc = readUInt32()
            let position = Int(readUInt32())
            let size = Int(readUInt32())
            // 區段 ID 唯一，內容範圍位於表格與末端 CRC 之間。
            guard (0...255).contains(id), !parsed.contains(where: { $0.id == id }), size > 0,
                position >= 12 + segmentCount * 16, position + size <= data.count - 4
            else {
                throw FirmwareParseError.truncatedSegment(id: id)
            }
            let start = data.startIndex + position
            let contents = Data(data[start..<(start + size)])
            // 內容 CRC 通過後才納入可傳輸區段。
            guard Self.checksum(contents) == segmentCrc else { throw FirmwareParseError.checksumMismatch }
            parsed.append(
                FirmwareSegment(
                    id: id,
                    crc32: segmentCrc,
                    size: size,
                    data: contents
                ))
        }
        // 全部區段通過範圍與 CRC 檢查後，才保存可傳輸的區段表。
        segments = parsed

        // 末端映像 CRC 原值交給耳機驗證，區段 CRC 已在本機核對。
        cursor = data.count - 4
        crc32 = readUInt32()
    }

    /// 計算 CRC-32/IEEE，初始值與最終 XOR 使用 UInt32.max。
    ///
    /// - Parameter data: 完整的待校驗資料，韌體解析使用區段內容。
    /// - Returns: 32-bit 校驗值，空資料回傳 0。
    static func checksum(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        // 每個位元組使用查表更新 CRC，最後再執行 XOR。
        for byte in data { crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 255)] }
        return crc ^ UInt32.max
    }

    /// 依耳機要求的區段 ID 查詢已驗證的內容。
    ///
    /// - Parameter id: 區段識別碼，已解析的有效 ID 範圍為 0...255。
    /// - Returns: 對應區段；映像未包含該 ID 時回傳 nil。
    func segment(id: Int) -> FirmwareSegment? {
        segments.first { $0.id == id }
    }

    /// 編碼 FOTA 開啟命令使用的映像與區段資料。
    ///
    /// - Returns: 映像 CRC、區段數與各區段 ID、長度、CRC，整數使用 little-endian。
    func serializeTable() -> Data {
        // FOTA 開啟資料先放映像 CRC 與區段數，再依原順序加入各區段。
        var payload = Data()
        payload.append(littleEndian: crc32)
        payload.append(UInt8(segments.count))
        // 區段表依映像順序加入 ID、大小與校驗值。
        for segment in segments {
            payload.append(UInt8(segment.id))
            payload.append(littleEndian: UInt32(segment.size))
            payload.append(littleEndian: segment.crc32)
        }
        return payload
    }
}

extension Data {
    /// 在資料尾端追加 4 bytes little-endian 整數。
    ///
    /// - Parameter value: 要序列化的 32-bit 無號整數，呼叫後資料增加 4 bytes。
    mutating func append(littleEndian value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    /// 在資料尾端追加 2 bytes little-endian 整數，供 FOTA 控制參數使用。
    ///
    /// - Parameter value: 要序列化的 16-bit 無號整數，呼叫後資料增加 2 bytes。
    mutating func append(littleEndian value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }
}
