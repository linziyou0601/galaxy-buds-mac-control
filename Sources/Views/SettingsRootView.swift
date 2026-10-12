import SwiftUI

/// 同一個原生分欄視窗承載連線與設定，狀態變動保留側欄及工具列結構。
struct SettingsRootView: View {
    @Bindable var bluetooth: BluetoothManager
    let navigation: SettingsNavigation
    let spatialAudio: SpatialAudioController

    var body: some View {
        NativeSettingsView(bluetooth: bluetooth, navigation: navigation, spatialAudio: spatialAudio)
            .onChange(of: spatialAudio.isProcessing) { _, receiving in
                // 視窗根層管理感測器，切換分類不終止已接手的音訊。
                if receiving && spatialAudio.isRunning && spatialAudio.headTrackingEnabled {
                    bluetooth.setSpatialTracking(true)
                }
            }
            .onChange(of: spatialAudio.headTrackingEnabled) { _, enabled in
                // 本機追蹤偏好與音訊處理分開，處理中才更新耳機感測器。
                if spatialAudio.isProcessing { bluetooth.setSpatialTracking(enabled) }
            }
            .onChange(of: spatialAudio.isRunning) { _, running in
                // 引擎停止或錯誤時還原耳機設定，關窗另由原生 delegate 收束。
                if !running { bluetooth.setSpatialTracking(false) }
            }
            .onChange(of: bluetooth.isConnected) { _, connected in
                // 控制裝置斷線後停止擷取，避免保留舊裝置的音場。
                if !connected { spatialAudio.stop() }
            }
    }
}
