import Foundation

struct FirmwareTests {
    /// 固定 CRC 向量與映像區段檢查，錯誤機型、截斷及被修改的資料須拒絕。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testImageValidation() throws {
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        let profile = try require(catalog.profiles.first { $0.id == "buds4Pro" })
        try check(FirmwareBinary.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
        let data = image(model: "SM-R640")
        let binary = try FirmwareBinary(data: data, buildName: "R640XXU0AZD2", profile: profile)
        try check(binary.segments.count == 1 && binary.segments[0].id == 6)
        try check(binary.serializeTable().prefix(5) == Data([0x44, 0x33, 0x22, 0x11, 1]))
        try rejects { _ = try FirmwareBinary(data: data.dropLast(), buildName: "R640XXU0AZD2", profile: profile) }
        try rejects {
            _ = try FirmwareBinary(data: image(model: "SM-R630"), buildName: "R630XXU0AZD2", profile: profile)
        }
        try rejects { _ = try FirmwareBinary(data: data, buildName: "R640XXU0AZG2", profile: profile) }
        var corrupted = data
        corrupted[corrupted.count - 5] ^= 1
        try rejects { _ = try FirmwareBinary(data: corrupted, buildName: "R640XXU0AZD2", profile: profile) }
    }

    /// 裝置請求決定分段與重傳，驗證完成後必須等到版本回報才宣告成功。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testTransferAndRestartConfirmation() throws {
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        let profile = try require(catalog.profiles.first { $0.id == "buds4Pro" })
        let binary = try FirmwareBinary(data: image(model: "SM-R640"), buildName: "R640XXU0AZD2", profile: profile)
        try MainActor.assumeIsolated {
            let updater = FirmwareUpdater()
            var sent: [SppMessage] = []
            updater.send = {
                sent.append($0)
                return true
            }
            updater.start(binary: binary, channelMtu: 100)
            try check(sent[0].messageID == .fotaOpen)
            updater.handle(SppMessage(messageID: .fotaOpen, payload: Data([0])))
            updater.handle(SppMessage(messageID: .fotaControl, payload: Data([0, 4, 0])))
            updater.handle(SppMessage(messageID: .fotaControl, payload: Data([1, 6, 0])))
            updater.handle(SppMessage(messageID: .fotaDownloadData, payload: Data([0, 0, 0, 0, 2])))
            let chunks = sent.filter { $0.messageID == .fotaDownloadData }
            try check(chunks.count == 2 && chunks.allSatisfy { $0.isFragment && $0.isResponse })
            try check(chunks[0].payload.prefix(4) == Data([0, 0, 0, 128]))
            try check(chunks[1].payload.prefix(4) == Data([4, 0, 0, 128]))
            updater.handle(SppMessage(messageID: .fotaDownloadData, payload: Data([0, 0, 0, 128, 1])))
            try check(sent.last?.payload == chunks[0].payload)
            updater.handle(SppMessage(messageID: .fotaResult, payload: Data([0, 0])))
            try check(updater.phase == .awaitingRestart && !updater.canCancel)
            updater.connectionLost()
            updater.confirmInstalledVersion("R640XXU0AZC1")
            try check(updater.phase == .awaitingRestart)
            updater.confirmInstalledVersion("R640XXU0AZD2")
            try check(updater.phase == .finished && !updater.isRunning)
        }
    }

    /// 排入傳輸失敗及未知區段要求都結束本機作業，避免宣告更新成功。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testRejectTransportAndUnknownSegments() throws {
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        let profile = try require(catalog.profiles.first { $0.id == "buds4Pro" })
        let binary = try FirmwareBinary(data: image(model: "SM-R640"), buildName: "R640XXU0AZD2", profile: profile)
        try MainActor.assumeIsolated {
            let updater = FirmwareUpdater()
            updater.send = { _ in false }
            updater.start(binary: binary, channelMtu: 100)
            try check(!updater.isRunning)
            updater.send = { _ in true }
            updater.start(binary: binary, channelMtu: 100)
            updater.handle(SppMessage(messageID: .fotaControl, payload: Data([1, 255, 0])))
            try check(!updater.isRunning)
        }
    }

    /// 升級比較包含 bootloader 版本，拒絕跨機型與跨版本系列映像。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testVersionOrdering() throws {
        try check(FirmwareVersion.isNewer("R640XXU0AZG2", than: "R640XXU0AZD2"))
        try check(FirmwareVersion.isNewer("R640XXU1AZC1", than: "R640XXU0AZD2"))
        try check(!FirmwareVersion.isNewer("R640XXU0AZG2", than: "R640XXU1AZD2"))
        try check(!FirmwareVersion.isNewer("R630XXU0AZG2", than: "R640XXU0AZD2"))
        try check(!FirmwareVersion.isNewer("R640TNU0AZG2", than: "R640XXU0AZD2"))
    }

    /// 建立合成 CAFE 映像與正確區段 CRC，模型及版本標記由測試輸入決定。
    ///
    /// - Parameters:
    ///   - model: 合成映像內嵌的機型識別，用於驗證機型比對。
    /// - Returns: 含指定機型與版本標記、有效區段 CRC 的合成測試映像。
    private func image(model: String) -> Data {
        let contents = Data(
            (model + " " + model.replacingOccurrences(of: "SM-", with: "") + "XXU0AZD2 synthetic firmware").utf8)
        var data = Data()
        // 合成映像以有效表頭與區段資料建立，末端 CRC 保留裝置驗證語意。
        for word in [
            UInt32(0xCAFE_CAFE), UInt32(28 + contents.count + 4), 1, 6, FirmwareBinary.checksum(contents), 28,
            UInt32(contents.count),
        ] { data.append(littleEndian: word) }
        data.append(contents)
        data.append(littleEndian: UInt32(0x1122_3344))
        return data
    }
}
