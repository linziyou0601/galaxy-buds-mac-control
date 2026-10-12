import SwiftUI

/// 系統空間音訊與耳機頭部追蹤的原生操作頁，權限由使用者啟動時授予。
struct SpatialAudioView: View {
    @Bindable var bluetooth: BluetoothManager
    @Bindable var audio: SpatialAudioController

    var body: some View {
        Form {
            Section {
                Text(
                    "Processes Mac audio locally with head tracking. macOS asks for system audio recording permission when enabled."
                )
                Toggle(
                    "Spatial audio processing",
                    isOn: Binding(
                        get: { audio.isRunning },
                        set: { enabled in
                            // 開啟由原生音訊服務建立 tap，關閉還原播放及耳機原設定。
                            if enabled {
                                audio.start()
                            } else {
                                // 停用時釋放 Mac 音訊處理並還原耳機追蹤旗標。
                                audio.stop()
                                bluetooth.setSpatialTracking(false)
                            }
                        })
                ).disabled(!bluetooth.isConnected || bluetooth.isDemo || bluetooth.firmware.isRunning)
                Toggle(
                    "Follow head movement",
                    isOn: Binding(get: { audio.headTrackingEnabled }, set: { audio.setHeadTracking($0) })
                ).disabled(bluetooth.isDemo)
                LabeledContent("System audio input") {
                    Text(audio.hasAudioInput ? "Receiving audio" : "No audio data yet")
                }
                // PCM 已存在但全為靜音時維持原音路徑，提示等待播放訊號。
                if audio.hasAudioInput && !audio.isProcessing {
                    Text("Waiting for playback audio").font(.caption).foregroundStyle(.secondary)
                }
                // 感測連線與音訊接收分開呈現，讓使用者辨識等待原因。
                LabeledContent("Head tracking") {
                    Text(bluetooth.status.spatialAttached ? "Connected" : "Not active")
                }
                LabeledContent("Virtual speaker angle") {
                    HStack {
                        Slider(
                            value: Binding(get: { audio.speakerAngleDegrees }, set: { audio.setSpeakerAngle($0) }),
                            in: 15...75, step: 5
                        ).accessibilityLabel("Virtual speaker angle").disabled(bluetooth.isDemo)
                        Text(audio.speakerAngleDegrees.formatted(.number.precision(.fractionLength(0))))
                            + Text(verbatim: "°")
                    }.frame(width: 200)
                }
                Text(
                    "macOS chooses the highest-quality native headphone renderer. Speaker angle changes the width of the virtual stereo soundstage."
                )
                .font(.caption).foregroundStyle(.secondary)
                // 只有處理與追蹤啟用時可重新置中，下一個有效姿態成為基準。
                Button("Recenter") { audio.recenter() }.disabled(!audio.isRunning || !audio.headTrackingEnabled)
                // 原生 API 與格式失敗保留服務錯誤，不呈現成功狀態。
                if let error = audio.errorText { Text(verbatim: error).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
    }
}
