import Foundation

/// 此專案實作的 Samsung SPP 命令與回報 ID。
enum MessageID: UInt8, Sendable {
    case debugGetAllData = 38
    case debugSerialNumber = 41
    case acknowledgement = 66
    case setClearCalls = 72
    case resp = 81
    case statusUpdated = 96
    case extendedStatusUpdated = 97
    case setVoiceCommands = 100
    case customEqualizeRecv = 105
    case setBoostLoudness = 106
    case pauseMediaWhenRemoved = 108
    case setCallPathControl = 110
    case setAncWithOneEarbud = 111
    case noiseControlsUpdate = 119
    case noiseControls = 120
    case setTouchAndHoldNoiseControls = 121
    case setDetectConversations = 122
    case setDetectConversationsDuration = 123
    case setSpatialAudio = 124
    case customizeAmbientSound = 130
    case noiseReductionLevel = 131
    case ambientVolume = 132
    case equalizer = 134
    case managerInfo = 136
    case customEqualize = 137
    case setSidetone = 139
    case stereoBalance = 143
    case lockTouchpad = 144
    case setTouchpadOption = 146
    case checkFitOfEarbuds = 157
    case checkFitResult = 158
    case findMyEarbudsStart = 160
    case findMyEarbudsStop = 161
    case muteEarbud = 162
    case findMyEarbudsOnWearingStart = 166
    case updateTime = 167
    case selfTest = 171
    case setSeamlessConnection = 175
    case fotaResult = 185
    case fotaOpen = 187
    case fotaControl = 188
    case fotaDownloadData = 189
    case fotaUpdate = 190
    case spatialAudioData = 194
    case spatialAudioControl = 195
    case cradleSerialNumber = 205
    case setAdaptiveVolume = 217
    case setFitAdjustment = 218
    case setSirenDetection = 222
    case headGestures = 231
    /// 需要向使用者回報傳輸與耳機確認的操作命令。
    var isSetting: Bool {
        // 只有會寫入耳機設定的命令參與設定回饋判斷。
        switch self {
        // 這些已知控制命令會改寫耳機設定，需要追蹤傳輸與耳機回覆。
        case .setSirenDetection, .setAdaptiveVolume, .setFitAdjustment, .setVoiceCommands,
            .setBoostLoudness, .headGestures, .setClearCalls, .pauseMediaWhenRemoved,
            .setSeamlessConnection, .stereoBalance, .noiseControls, .noiseReductionLevel,
            .ambientVolume, .setAncWithOneEarbud, .customizeAmbientSound,
            .setDetectConversations, .setDetectConversationsDuration, .setSidetone,
            .setCallPathControl, .equalizer, .customEqualize, .lockTouchpad,
            .setTouchpadOption, .setTouchAndHoldNoiseControls, .checkFitOfEarbuds,
            .findMyEarbudsStart, .findMyEarbudsStop, .findMyEarbudsOnWearingStart, .muteEarbud:
            true
        // 非設定命令不參與設定寫入回饋。
        default: false
        }
    }

}
