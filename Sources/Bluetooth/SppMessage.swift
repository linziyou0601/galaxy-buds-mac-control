import Foundation

/// Samsung SPP 訊息，封包長度包含命令 ID、payload 與 CRC。
struct SppMessage: Sendable {
    let messageID: MessageID
    let payload: Data
    let isResponse: Bool
    let isFragment: Bool

    /// 建立未編碼的訊息，保留原始 payload 與協定旗標。
    ///
    /// - Parameters:
    ///   - messageID: 協定命令識別碼。
    ///   - payload: 命令內容，預設為空資料，長度於編碼時檢查。
    ///   - isResponse: 是否設定回覆旗標，預設為 false。
    ///   - isFragment: 是否設定分片旗標，預設為 false。
    init(messageID: MessageID, payload: Data = Data(), isResponse: Bool = false, isFragment: Bool = false) {
        self.messageID = messageID
        self.payload = payload
        self.isResponse = isResponse
        self.isFragment = isFragment
    }

    /// 建立時間同步命令，payload 包含 UTC 毫秒與當地時差，共 12 bytes。
    ///
    /// - Parameters:
    ///   - date: 要同步的時間，預設為目前時間，Unix epoch 之前的時間以 0 表示。
    ///   - timeZone: 計算指定時間的 UTC 時差，預設為系統時區。
    /// - Returns: 使用 little-endian UInt64 時間與 Int32 時差的 updateTime 訊息。
    static func timeUpdate(at date: Date = Date(), timeZone: TimeZone = .current) -> SppMessage {
        let timestamp = UInt64(max(0, date.timeIntervalSince1970 * 1000)).littleEndian
        let offset = Int32(timeZone.secondsFromGMT(for: date) * 1000).littleEndian
        var payload = withUnsafeBytes(of: timestamp) { Data($0) }
        payload.append(contentsOf: withUnsafeBytes(of: offset) { Array($0) })
        return SppMessage(messageID: .updateTime, payload: payload)
    }

    /// 編碼包含表頭、命令、payload、CRC 與結尾的完整封包。
    ///
    /// - Returns: 可傳送的封包；命令、payload 與 CRC 合計超過 1023 bytes 時回傳 nil。
    func encode() -> Data? {
        let size = 1 + payload.count + 2
        // 10-bit 長度不含外層表頭與結尾，超限交由呼叫者回報失敗。
        guard size <= 0x3FF else { return nil }
        var header = UInt16(size)
        // response 與 fragment 使用獨立旗標，不改變 payload 的長度語意。
        if isFragment { header |= 0x2000 }
        // 回覆旗標獨立於分片旗標，兩者可同時存在。
        if isResponse { header |= 0x1000 }
        var body = Data([messageID.rawValue])
        body.append(payload)
        // CRC 僅覆蓋命令 ID 與 payload，再以 little-endian 追加。
        let crc = CRC16.ccitt(body)
        var result = Data([0xFD, UInt8(header & 0xFF), UInt8(header >> 8)])
        result.append(body)
        result.append(UInt8(crc & 0xFF))
        result.append(UInt8(crc >> 8))
        result.append(0xDD)
        return result
    }

    /// 驗證完整封包的長度與 CRC，再解析已知訊息。
    ///
    /// - Parameter data: 單一完整封包，接受 FC／FD 起始碼與對應結尾。
    /// - Returns: 已知訊息；結構、CRC 無效或命令 ID 未定義時回傳 nil。
    static func decode(_ data: Data) -> SppMessage? {
        // 共用結構驗證後才解碼已知命令，未知 ID 保留串流邊界語意。
        guard let parts = frameParts(data), let id = MessageID(rawValue: parts.id) else { return nil }
        return SppMessage(
            messageID: id, payload: parts.payload,
            isResponse: parts.response, isFragment: parts.fragment)
    }

    /// 驗證封包結構與 CRC，保留未定義的命令 ID 供串流判斷邊界。
    ///
    /// - Parameter data: 單一完整封包，長度必須與表頭宣告一致。
    /// - Returns: 命令、內容與旗標；表頭、長度、結尾或 CRC 無效時回傳 nil。
    fileprivate static func frameParts(_ data: Data) -> (id: UInt8, payload: Data, response: Bool, fragment: Bool)? {
        let bytes = [UInt8](data)
        // 至少包含標頭、命令、CRC 與結尾，FC 與 FD 使用對應結尾碼。
        guard bytes.count >= 7, bytes[0] == 0xFD || bytes[0] == 0xFC else { return nil }
        let header = UInt16(bytes[1]) | UInt16(bytes[2]) << 8
        let size = Int(header & 0x3FF)
        let end: UInt8 = bytes[0] == 0xFD ? 0xDD : 0xCC
        // 長度欄包含 ID 與 CRC，實際封包總長另含 4 bytes 外層。
        guard size >= 3, bytes.count == size + 4, bytes.last == end else { return nil }
        let crcIndex = bytes.count - 3
        let expected = UInt16(bytes[crcIndex]) | UInt16(bytes[crcIndex + 1]) << 8
        // 損毀的 payload 不交給狀態解析器。
        guard CRC16.ccitt(Data(bytes[3..<crcIndex])) == expected else { return nil }
        return (bytes[3], Data(bytes[4..<crcIndex]), header & 0x1000 != 0, header & 0x2000 != 0)
    }
}

/// RFCOMM 組框器，保留未收齊尾端，損毀資料重新尋找起始位元組。
struct SppStreamDecoder {
    private var buffer = Data()

    /// 接收 RFCOMM 分片，更新內部緩衝並解析已知訊息。
    ///
    /// 未收齊的尾端保存至下次呼叫，損毀資料逐位元組略過，合法未知命令整包略過。
    /// - Parameter data: 依接收順序提供的位元組，可包含部分或多個封包。
    /// - Returns: 此次能完整解析且通過 CRC 的已知訊息，依接收順序排列。
    mutating func append(_ data: Data) -> [SppMessage] {
        buffer.append(data)
        var messages: [SppMessage] = []
        // 緩衝至少有完整表頭時才判斷封包長度，其餘留待下一次接收。
        while buffer.count >= 3 {
            let bytes = [UInt8](buffer.prefix(3))
            // 雜訊逐 byte 略過，避免未知前綴阻擋後續完整封包。
            guard bytes[0] == 0xFD || bytes[0] == 0xFC else {
                buffer.removeFirst()
                continue
            }
            let size = (Int(bytes[1]) | Int(bytes[2]) << 8) & 0x3FF
            // 長度欄包含 ID 與 CRC，實際封包總長另含 4 bytes 外層。
            guard size >= 3 else {
                buffer.removeFirst()
                continue
            }
            let count = size + 4
            // 合法但未收齊的尾端保留，等待下一次 RFCOMM callback。
            guard buffer.count >= count else { break }
            let frame = Data(buffer.prefix(count))
            // CRC 通過即消耗整包，未知命令不影響下一包定位。
            if let parts = SppMessage.frameParts(frame) {
                // 只產出有型別定義的命令，未知事件仍由外層消耗。
                if let id = MessageID(rawValue: parts.id) {
                    messages.append(
                        SppMessage(
                            messageID: id, payload: parts.payload,
                            isResponse: parts.response, isFragment: parts.fragment))
                }
                // 合法但未支援的事件整包略過，payload 中的 FD 不會干擾下一包。
                buffer = Data(buffer.dropFirst(count))
            } else {
                // 結構或 CRC 失敗時逐位元組重新尋找封包起點。
                buffer = Data(buffer.dropFirst())
            }
        }
        return messages
    }
}
