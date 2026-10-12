import Foundation

struct StatusTests {
    /// 現行環境音命令的附加欄位從機型配置讀取，完整 ACK 才能更新。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testCustomAmbientTail() throws {
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        // 各機型都需從自己的配置取得環境音尾端欄位。
        for profile in catalog.profiles {
            var state = BudsStatus()
            var extended = Data(repeating: 0, count: 64)
            // 依配置 offset 建立可辨識尾端值，驗證解析沒有固定位置。
            for (index, offset) in profile.ambientCommandTailOffsets.enumerated() {
                extended[offset] = UInt8(index + 1)
            }
            state.apply(SppMessage(messageID: .extendedStatusUpdated, payload: extended), profile: profile)
            try check(state.ambientCommandTail == [1, 2, 3])
            state.apply(
                SppMessage(
                    messageID: .acknowledgement,
                    payload: Data([MessageID.customizeAmbientSound.rawValue, 1, 2, 1, 0, 1, 2])),
                profile: profile)
            try check(state.ambientCustomEnabled && state.ambientCustomLeft == 2 && state.ambientCustomRight == 1)
            try check(state.ambientCommandTail == [0, 1, 2])
            state.apply(
                SppMessage(
                    messageID: .acknowledgement, payload: Data([MessageID.customizeAmbientSound.rawValue, 0, 1, 1])),
                profile: profile)
            try check(state.ambientCustomEnabled && state.ambientCommandTail == [0, 1, 2])
        }
    }

    /// 注入不同自訂等級上限時，延伸回報與 ACK 採同一範圍並保留超限前值。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testConfiguredAmbientRange() throws {
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        // 同一測試分別注入兩款機型，再覆寫自訂上限驗證配置生效。
        for original in catalog.profiles {
            // 以完整已驗證配置注入 4 級上限，避免測試固定機型的預設值。
            var object = try require(
                JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
            object["ambientCustomMax"] = 4
            let profile = try JSONDecoder().decode(
                DeviceProfile.self, from: JSONSerialization.data(withJSONObject: object))
            try profile.validate()
            var state = BudsStatus()
            var report = Data(repeating: 0, count: 64)
            report[30] = 0x34
            state.apply(SppMessage(messageID: .extendedStatusUpdated, payload: report), profile: profile)
            try check(state.ambientCustomLeft == 3 && state.ambientCustomRight == 4)
            // 超限左右欄位不覆寫已取得的有效等級。
            report[30] = 0x55
            state.apply(SppMessage(messageID: .extendedStatusUpdated, payload: report), profile: profile)
            try check(state.ambientCustomLeft == 3 && state.ambientCustomRight == 4)
            try check(
                state.apply(
                    SppMessage(
                        messageID: .acknowledgement,
                        payload: Data([MessageID.customizeAmbientSound.rawValue, 1, 4, 3, 0, 1, 2])), profile: profile))
            try check(state.ambientCustomLeft == 4 && state.ambientCustomRight == 3)
        }
    }

    /// 零電量與未回報值必須能區分，基本回報也更新配戴狀態。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testZeroAndUnknownBattery() throws {
        var state = BudsStatus()
        try check(state.batteryLeft == nil)
        state.apply(SppMessage(messageID: .statusUpdated, payload: Data([1, 0, 255, 1, 1, 0x11, 100])))
        try check(state.batteryLeft == 0)
        try check(state.batteryRight == nil)
        try check(state.batteryCase == 100)
        try check(state.isLeftWearing && state.isRightWearing)
        try check(!state.hasControlStatus)
    }

    /// 延伸回報包含完整色碼、左右動作與配置範圍內的等級。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testExtendedStatus() throws {
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        let profile = try require(catalog.profiles.first { $0.id == "buds3Pro" })
        var payload = Data(repeating: 0, count: 46)
        payload[2] = 70
        payload[3] = 80
        payload[7] = 90
        payload[9] = 7
        payload[10] = 0x80
        payload[11] = 0x12
        payload[12] = 1
        payload[14] = 0x54
        payload[15] = 1
        payload[21] = 0x99
        payload[23] = UInt8(profile.ambientMax)
        payload[24] = 4
        payload[26] = 1
        payload[27] = 2
        payload[28] = 1
        payload[29] = 1
        payload[30] = 0x21
        payload[31] = 2
        payload[33] = 1
        payload[34] = 0
        var state = BudsStatus()
        state.apply(SppMessage(messageID: .extendedStatusUpdated, payload: payload), profile: profile)
        try check(state.batteryLeft == 70 && state.batteryRight == 80 && state.batteryCase == 90)
        try check(state.deviceColorID == 340)
        try check(state.hasControlStatus && state.noiseControlMode == .anc && state.ancLevel == 4)
        try check(state.ambientSoundVolume == profile.ambientMax)
        try check(state.touchHoldLeft == .voiceAssistant && state.touchHoldRight == .noiseControl)
        try check(state.noiseCycleLeft == .ancAmbient && state.noiseCycleRight == .ancAmbient)
        try check(state.ambientCustomLeft == 2 && state.ambientCustomRight == 1)
        try check(state.detectConversations && state.ambientDuringCalls && state.sidetone)
    }

    /// 短回報及未知模式不應被當成關閉，未知手勢與輪替組合保持 nil。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testMalformedStatusPreservesKnownValues() throws {
        var state = BudsStatus()
        state.noiseControlMode = .adaptive
        state.ancLevel = 4
        state.ambientSoundVolume = 2
        state.apply(SppMessage(messageID: .extendedStatusUpdated, payload: Data([1, 2])))
        try check(state.noiseControlMode == .adaptive && state.batteryLeft == nil)
        let payload = Data(repeating: 255, count: 38)
        state.apply(SppMessage(messageID: .extendedStatusUpdated, payload: payload))
        try check(state.noiseControlMode == .adaptive && state.ancLevel == 4 && state.ambientSoundVolume == 2)
        try check(state.touchHoldLeft == nil && state.noiseCycleLeft?.rawValue == 15)
        let sliced = (Data([0]) + Data([1, 50, 60])).dropFirst()
        state.apply(SppMessage(messageID: .statusUpdated, payload: sliced))
        try check(state.batteryLeft == 50 && state.batteryRight == 60)
    }

    /// 不完整曲線維持未回報，完整且有效的預設與自訂曲線才被採用。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testEqualizerCurveCompleteness() throws {
        var state = BudsStatus()
        state.apply(SppMessage(messageID: .customEqualizeRecv, payload: Data([2, 9, 1])))
        try check(state.presetEqualizerCurves.isEmpty)
        let payload = Data([2, 9]) + Data(repeating: 10, count: 9) + Data(repeating: 246, count: 9)
        state.apply(SppMessage(messageID: .customEqualizeRecv, payload: payload))
        try check(state.presetEqualizerCurves == [Array(repeating: 0, count: 9), Array(repeating: 10, count: 9)])
        try check(state.customEqualizerBands == Array(repeating: -10, count: 9))
        state.apply(SppMessage(messageID: .customEqualizeRecv, payload: Data([2, 9]) + Data(repeating: 127, count: 9)))
        try check(state.presetEqualizerCurves.count == 2)
    }
    /// 入盒開蓋可回報盒子電量，離盒的零值應回到未回報。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testCaseBatteryAvailability() throws {
        var state = BudsStatus()
        state.apply(SppMessage(messageID: .statusUpdated, payload: Data([1, 51, 55, 1, 1, 0, 0])))
        try check(state.batteryCase == nil)
        var report = Data(repeating: 0, count: 14)
        report[2] = 51
        report[3] = 55
        report[7] = 86
        report[12] = 1
        state.apply(SppMessage(messageID: .extendedStatusUpdated, payload: report))
        try check(state.batteryCase == 86)
        try check(state.touchCommandTail == nil)
        state.apply(SppMessage(messageID: .statusUpdated, payload: Data([1, 51, 55, 1, 1, 0, 0])))
        try check(state.batteryCase == nil)
    }

    /// ACK 取回實際設定，超出範圍的等級與未知組合不當成成功。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testAcknowledgementValues() throws {
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        let profile = try require(catalog.profiles.first { $0.id == "buds3Pro" })
        var state = BudsStatus()
        // 未注入範圍時不得假定為五段 ANC。
        try check(!state.apply(SppMessage(messageID: .acknowledgement, payload: Data([131, 4]))))
        try check(state.apply(SppMessage(messageID: .acknowledgement, payload: Data([120, 2]))))
        try check(state.noiseControlMode == .ambient && state.hasControlStatus)
        try check(state.apply(SppMessage(messageID: .acknowledgement, payload: Data([131, 4])), profile: profile))
        try check(state.ancLevel == 4)
        try check(!state.apply(SppMessage(messageID: .acknowledgement, payload: Data([131, 5])), profile: profile))
        try check(state.ancLevel == 4)
        state.apply(SppMessage(messageID: .acknowledgement, payload: Data([110, 0])))
        state.apply(SppMessage(messageID: .acknowledgement, payload: Data([144, 1])))
        try check(state.ambientDuringCalls && !state.touchpadLocked)
        state.apply(SppMessage(messageID: .acknowledgement, payload: Data([146, 1, 2])), profile: profile)
        try check(state.touchHoldLeft == .voiceAssistant && state.touchHoldRight == .noiseControl)
        try check(!state.apply(SppMessage(messageID: .acknowledgement, payload: Data([121, 1]))))
        try check(!state.apply(SppMessage(messageID: .statusUpdated, payload: Data([1, 50, 60]), isFragment: true)))
        try check(state.batteryLeft == nil)
    }

    /// 操作旗標與進階欄位使用 Buds3 系列位置，ACK 不重設未回報的旗標。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testAdvancedControlsAndGestureFlags() throws {
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        let profile = try require(catalog.profiles.first { $0.id == "buds3Pro" })
        var payload = Data(repeating: 0, count: 62)
        payload[10] = 0x80 | 0x08 | 0x02 | 0x20
        payload[19] = 0
        payload[25] = 24
        payload[28] = 1
        payload[29] = 1
        payload[30] = 0x12
        payload[31] = 2
        payload[33] = 1
        payload[34] = 1
        payload[44] = 1
        payload[46] = 1
        var state = BudsStatus()
        state.apply(SppMessage(messageID: .extendedStatusUpdated, payload: payload), profile: profile)
        try check(state.gestureEnabled == [true, false, true, false, false, true, false])
        try check(state.additionalSettings[.seamlessConnection] == true)
        try check(state.additionalSettings[.pauseWhenRemoved] == true)
        try check(state.additionalSettings[.clearCalls] == true)
        try check(state.stereoBalance == 24 && state.sidetone && !state.ambientDuringCalls)
        try check(state.ncWithOneEarbud && state.ambientCustomEnabled && state.ambientCustomRight == 2)
        state.apply(SppMessage(messageID: .acknowledgement, payload: Data([144, 1])))
        try check(state.gestureEnabled == [true, false, true, false, false, true, false])
        state.apply(SppMessage(messageID: .acknowledgement, payload: Data([144, 0, 0, 1, 0, 1, 1, 0, 1, 2, 3])))
        try check(state.gestureEnabled == [false, true, false, true, true, false, true])
        try check(state.touchpadLocked)
        try check(state.touchCommandTail == [2, 3])
        state.apply(SppMessage(messageID: .acknowledgement, payload: Data([175, 1])), profile: profile)
        try check(state.additionalSettings[.seamlessConnection] == false)
        try check(!state.apply(SppMessage(messageID: .acknowledgement, payload: Data([143, 33]))))
        try check(state.stereoBalance == 24)
    }

    /// 充電盒識別資料需要完整的九字元韌體與十一字元序號。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testCaseIdentityCompleteness() throws {
        var state = BudsStatus()
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        let profile = try require(catalog.profiles.first { $0.id == "buds3Pro" })
        let payload = Data("R630XX001TEST0000001".utf8)
        try check(payload.count == 20)
        try check(state.apply(SppMessage(messageID: .cradleSerialNumber, payload: payload), profile: profile))
        try check(state.caseSoftwareVersion == "R630XX001" && state.serialCase == "TEST0000001")
        try check(
            !state.apply(
                SppMessage(messageID: .cradleSerialNumber, payload: Data(payload.prefix(19))), profile: profile))
        try check(state.serialCase == "TEST0000001")
    }

    /// 機型配置決定後段欄位與盒子格式，頭部方向及語音子命令採獨立回報。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testConfiguredModernControls() throws {
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        let profile = try require(catalog.profiles.first { $0.id == "buds4Pro" })
        let identity = Data("CASEVERSION04TESTCASE000001".utf8)
        try check(identity.count == 27)
        var state = BudsStatus()
        try check(state.apply(SppMessage(messageID: .cradleSerialNumber, payload: identity), profile: profile))
        try check(state.caseSoftwareVersion == "CASEVERSION04" && state.serialCase == "TESTCASE000001")
        var payload = Data(repeating: 0, count: 62)
        payload[47] = 1
        payload[52] = 1
        payload[58] = 1
        state.apply(SppMessage(messageID: .extendedStatusUpdated, payload: payload), profile: profile)
        try check(state.additionalSettings[.voiceCommands] == true)
        try check(state.additionalSettings[.sirenDetection] == true)
        try check(state.additionalSettings[.volumeNormalization] == true)
        try check(state.apply(SppMessage(messageID: .setVoiceCommands, payload: Data([1, 0])), profile: profile))
        try check(state.additionalSettings[.voiceCommands] == false)
        state.apply(SppMessage(messageID: .acknowledgement, payload: Data([231, 3])), profile: profile)
        try check(state.headGestureMask == 3)
        state.apply(SppMessage(messageID: .headGestures, payload: Data([1])), profile: profile)
        try check(state.lastHeadGesture == true)
        state.apply(SppMessage(messageID: .acknowledgement, payload: Data([231, 1])), profile: profile)
        state.apply(SppMessage(messageID: .headGestures, payload: Data([1])), profile: profile)
        try check(state.lastHeadGesture == false)
        state.apply(SppMessage(messageID: .acknowledgement, payload: Data([121, 11, 9])), profile: profile)
        try check(state.noiseCycleLeft?.contains(.adaptive) == true)
        try check(state.noiseCycleRight?.rawValue == 9)
        try check(!state.apply(SppMessage(messageID: .acknowledgement, payload: Data([121, 8, 9])), profile: profile))
        state.apply(SppMessage(messageID: .acknowledgement, payload: Data([106, 1, 0])), profile: profile)
        try check(
            state.additionalSettings[.voiceBoost] == true && state.additionalSettings[.volumeNormalization] == false)
    }

    /// Buds4 的數位助理代碼與音量分開，ACK 保留兩耳助理類型。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testDigitalAssistantTouchActions() throws {
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        let profile = try require(catalog.profiles.first { $0.id == "buds4Pro" })
        var payload = Data(repeating: 0, count: 62)
        payload[11] = 0x36
        payload[59] = 0x12
        var state = BudsStatus()
        state.apply(SppMessage(messageID: .extendedStatusUpdated, payload: payload), profile: profile)
        try check(state.touchHoldLeft == .googleAssistant && state.touchHoldRight == .volume)
        try check(state.touchAssistantLeft == 1 && state.touchAssistantRight == 2)
        state.apply(SppMessage(messageID: .acknowledgement, payload: Data([146, 6, 3, 2, 1])), profile: profile)
        try check(state.touchHoldLeft == .volume && state.touchHoldRight == .googleAssistant)
        try check(state.touchAssistantLeft == 2 && state.touchAssistantRight == 1)
        try check(profile.touchActionCodes[TouchHoldAction.volume.rawValue] == 6)
        try check(profile.touchActionCodes[TouchHoldAction.digitalAssistant.rawValue] == 3)
        state.apply(SppMessage(messageID: .acknowledgement, payload: Data([146, 3, 6])), profile: profile)
        try check(state.touchAssistantLeft == 2 && state.touchAssistantRight == 1)
    }

    /// 自我測試位元與空間四元數的短資料不覆寫有效快照。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testDiagnosticsAndSpatialData() throws {
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        let profile = try require(catalog.profiles.first { $0.id == "buds4Pro" })
        var state = BudsStatus()
        try check(state.apply(SppMessage(messageID: .selfTest, payload: Data([1, 128, 0, 0])), profile: profile))
        try check(state.selfTestMask == 0x8001)
        try check(!state.apply(SppMessage(messageID: .selfTest, payload: Data([0, 0])), profile: profile))
        try check(state.selfTestMask == 0x8001)
        // 高頻姿態由共用解碼器直接交給音場，狀態快照不持有未使用的四元數。
        let quaternion = BudsStatus.decodeSpatialQuaternion(Data([32, 0, 0, 0, 0, 0, 0, 0x10, 0x27, 0]))
        try check(quaternion == [0, 0, 0, 1])
        try check(BudsStatus.decodeSpatialQuaternion(Data(repeating: 0, count: 10)) == nil)
        state.apply(SppMessage(messageID: .spatialAudioControl, payload: Data([2])), profile: profile)
        try check(state.spatialAttached)
        state.apply(SppMessage(messageID: .spatialAudioControl, payload: Data([3])), profile: profile)
        try check(!state.spatialAttached)
    }

    /// Buds3 協定 revision 4 以助理欄位覆蓋原動作，舊 revision 維持舊碼。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testBuds3AssistantRevision() throws {
        let catalog = try ProfileCatalog(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        let profile = try require(catalog.profiles.first { $0.id == "buds3Pro" })
        var data = Data(repeating: 0, count: 61)
        data[0] = 4
        data[11] = 0x32
        data[60] = 0x10
        var state = BudsStatus()
        state.apply(SppMessage(messageID: .extendedStatusUpdated, payload: data), profile: profile)
        try check(state.touchHoldLeft == .googleAssistant && state.touchHoldBaseLeft == 3)
        try check(state.touchAssistantSupported)
        data[0] = 3
        state.apply(SppMessage(messageID: .extendedStatusUpdated, payload: data), profile: profile)
        try check(state.touchHoldLeft == .volume && !state.touchAssistantSupported)
    }

}
