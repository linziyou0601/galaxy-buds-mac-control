import Foundation

struct ProtocolTests {
    /// 分片與 payload 內結尾符號不改變完整封包邊界，後續封包仍可解碼。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testFragmentedFramesAndEmbeddedDelimiter() throws {
        let first = SppMessage(messageID: .noiseControls, payload: Data([0xDD, 1]))
        let second = SppMessage(messageID: .noiseReductionLevel, payload: Data([4]))
        let a = first.encode()!
        let b = second.encode()!
        var decoder = SppStreamDecoder()
        try check(decoder.append(Data(a.prefix(3))).isEmpty)
        let received = decoder.append(Data(a.dropFirst(3)) + b)
        try check(received.count == 2)
        try check(received.first?.payload == first.payload)
        try check(received.last?.payload == Data([4]))
    }
    /// CRC 損毀、虛假長度及前置雜訊被拒絕，串流恢復後取得有效訊息。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testCorruptionAndMalformedLength() throws {
        var packet = SppMessage(messageID: .noiseControls, payload: Data([1])).encode()!
        packet[4] ^= 0x01
        try check(SppMessage.decode(packet) == nil)
        try check(SppMessage.decode(Data([0xFD, 0xFF, 0x03, 120, 0, 0, 0xDD])) == nil)
        var decoder = SppStreamDecoder()
        let valid = SppMessage(messageID: .noiseControls, payload: Data([2])).encode()!
        try check(decoder.append(Data([0, 1, 2]) + packet + valid).last?.payload == Data([2]))
    }
    /// response 與 fragment 旗標互相獨立，非零起點 Data slice 保持 payload。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testResponseAndFragmentFlagsAndSlice() throws {
        let message = SppMessage(messageID: .resp, payload: Data([120, 0]), isResponse: true, isFragment: true)
        let framed = Data([0]) + message.encode()!
        let decoded = try require(SppMessage.decode(framed.dropFirst()))
        try check(decoded.isResponse)
        try check(decoded.isFragment)
        try check(decoded.payload == message.payload)
    }
    /// CCITT 初始值 0 的固定測試向量，獨立於本專案的編解碼往返。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testCRCReferenceVector() throws {
        try check(CRC16.ccitt(Data("123456789".utf8)) == 0x31C3)
    }

    /// 未支援事件中的 FD 位元組不能吞掉下一個有效封包。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testUnknownEventKeepsNextFrame() throws {
        var unknown = try require(
            SppMessage(
                messageID: .statusUpdated,
                payload: Data([0xFD, 0xFF, 0x03, 0, 1, 2])
            ).encode())
        unknown[3] = 0
        let crc = CRC16.ccitt(Data(unknown[3..<(unknown.count - 3)]))
        unknown[unknown.count - 3] = UInt8(crc & 0xFF)
        unknown[unknown.count - 2] = UInt8(crc >> 8)
        let known = try require(SppMessage(messageID: .noiseControls, payload: Data([2])).encode())
        var decoder = SppStreamDecoder()
        let messages = decoder.append(unknown + known)
        try check(messages.count == 1 && messages[0].payload == Data([2]))
    }

    /// 長度欄位只接受 10-bit 可表示的完整封包。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testFrameSizeBoundary() throws {
        let packet = try require(
            SppMessage(messageID: .statusUpdated, payload: Data(repeating: 0, count: 1020)).encode())
        try check(SppMessage.decode(packet)?.payload.count == 1020)
        try check(SppMessage(messageID: .statusUpdated, payload: Data(repeating: 0, count: 1021)).encode() == nil)
    }

    /// 固定 UTC 時間與 GMT+8 offset 產出官方 12-byte little-endian 時間格式。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testClockUpdateLayout() throws {
        let packet = SppMessage.timeUpdate(
            at: Date(timeIntervalSince1970: 1), timeZone: TimeZone(secondsFromGMT: 8 * 3600)!)
        try check(packet.messageID == .updateTime)
        try check(packet.payload == Data([0xE8, 3, 0, 0, 0, 0, 0, 0, 0, 0x74, 0xB7, 1]))
    }

}
