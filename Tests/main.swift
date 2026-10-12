import Foundation

struct CheckFailure: Error { let description: String }

/// 斷言失敗時中止測試程序，提供檔案與行號。
///
/// - Parameters:
///   - condition: 延後執行的測試斷言，可拋出被測試方法的錯誤。
///   - file: 斷言呼叫端的來源檔案，預設由編譯器提供。
///   - line: 斷言呼叫端行號，預設由編譯器提供。
/// - Throws: 斷言不成立時拋出含檔案與行號的 CheckFailure，條件錯誤繼續傳遞。
func check(
    _ condition: @autoclosure () throws -> Bool,
    file: StaticString = #filePath, line: UInt = #line
) throws {
    // 條件失敗時保留呼叫端檔案與行號，讓測試定位原斷言。
    guard try condition() else { throw CheckFailure(description: "\(file):\(line)") }
}

/// 將必要的解析結果解開，缺值視為測試失敗。
///
/// - Parameters:
///   - value: 必要解析結果，nil 表示測試前置條件不成立。
/// - Returns: 已存在的必要解析結果。
/// - Throws: 必要結果為 nil 時拋出 CheckFailure。
func require<T>(_ value: T?) throws -> T {
    // 解析結果缺值時結束該項測試，避免後續使用不存在的資料。
    guard let value else { throw CheckFailure(description: "Expected a decoded value") }
    return value
}

/// 驗證無效輸入會被拒絕。
///
/// - Parameters:
///   - operation: 預期拋出錯誤的被測試操作。
/// - Throws: 操作未拋出預期錯誤時，以測試斷言回報失敗。
func rejects(_ operation: () throws -> Void) throws {
    do { try operation() } catch { return }
    throw CheckFailure(description: "Expected invalid input to be rejected")
}

// 依功能群執行全部核心測試，任一斷言失敗即返回非零結果。
do {
    let profiles = ProfileTests()
    try profiles.testBundledModelsAndNames()
    try profiles.testProfileDrivenInterface()
    try profiles.testRejectInvalidProfileAndUnsupportedAdapter()
    try profiles.testColorResolutionAndOverrides()
    try profiles.testRejectEmptyColorCatalog()
    try profiles.testQuickControlsRejectUnsupportedAndDuplicate()
    try profiles.testRejectIncompleteStatusLayout()
    // 協定測試檢查組框、CRC、未知命令與邊界資料。
    let protocolTests = ProtocolTests()
    try protocolTests.testFragmentedFramesAndEmbeddedDelimiter()
    try protocolTests.testCorruptionAndMalformedLength()
    try protocolTests.testResponseAndFragmentFlagsAndSlice()
    try protocolTests.testCRCReferenceVector()
    try protocolTests.testUnknownEventKeepsNextFrame()
    try protocolTests.testFrameSizeBoundary()
    try protocolTests.testClockUpdateLayout()
    // 狀態測試驗證機型欄位、未知值與完整回報的更新語意。
    let statuses = StatusTests()
    try statuses.testCustomAmbientTail()
    try statuses.testConfiguredAmbientRange()
    try statuses.testZeroAndUnknownBattery()
    try statuses.testExtendedStatus()
    try statuses.testMalformedStatusPreservesKnownValues()
    try statuses.testEqualizerCurveCompleteness()
    try statuses.testCaseBatteryAvailability()
    try statuses.testAcknowledgementValues()
    try statuses.testAdvancedControlsAndGestureFlags()
    try statuses.testCaseIdentityCompleteness()
    try statuses.testConfiguredModernControls()
    try statuses.testDigitalAssistantTouchActions()
    try statuses.testBuds3AssistantRevision()
    try statuses.testDiagnosticsAndSpatialData()
    // 韌體測試涵蓋映像、傳輸失敗與重啟後版本確認。
    let firmware = FirmwareTests()
    try firmware.testImageValidation()
    try firmware.testTransferAndRestartConfirmation()
    try firmware.testRejectTransportAndUnknownSegments()
    try firmware.testVersionOrdering()
    try MainActor.assumeIsolated { try NavigationTests().testHistoryFollowsModelCategories() }
    let audio = AudioTests()
    try audio.testSensorWorldCoordinates()
    try audio.testStereoPCMLayouts()
    try audio.testEmptyLeadingPCMBuffer()
    print("PASS: 36 tests (profiles, colors, shortcuts, validation, fragmented frames, corruption, flags)")
} catch {
    // 首個失敗結果結束測試並寫入 stderr，供本機與 CI 判讀。
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
