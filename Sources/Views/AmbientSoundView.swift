import SwiftUI

/// 左右環境音等級設定，數值範圍依控制協定。
struct AmbientSoundView: View {
    @Bindable var bluetooth: BluetoothManager
    private var status: BudsStatus { bluetooth.status }

    var body: some View {
        Form {
            // 自訂環境音需要機型上限，缺少配置時不建立可寫入表單。
            if let profile = bluetooth.connectedModel?.profile {
                Section("Customize ambient sound") {
                    Toggle(
                        "Customize ambient sound",
                        isOn: Binding(
                            get: { status.ambientCustomEnabled },
                            set: {
                                bluetooth.setCustomAmbient(
                                    enabled: $0, left: status.ambientCustomLeft,
                                    right: status.ambientCustomRight)
                            }))
                    LabeledContent("Left") {
                        Slider(
                            value: Binding(
                                get: { Double(status.ambientCustomLeft) },
                                set: {
                                    bluetooth.setCustomAmbient(
                                        enabled: true, left: Int($0),
                                        right: status.ambientCustomRight)
                                }), in: 0...Double(profile.ambientCustomMax), step: 1)
                    }.disabled(!status.ambientCustomEnabled)
                    LabeledContent("Right") {
                        Slider(
                            value: Binding(
                                get: { Double(status.ambientCustomRight) },
                                set: {
                                    bluetooth.setCustomAmbient(
                                        enabled: true, left: status.ambientCustomLeft,
                                        right: Int($0))
                                }), in: 0...Double(profile.ambientCustomMax), step: 1)
                    }.disabled(!status.ambientCustomEnabled)

                }
            }
        }.formStyle(.grouped).disabled(status.ambientCommandTail == nil)
    }
}
