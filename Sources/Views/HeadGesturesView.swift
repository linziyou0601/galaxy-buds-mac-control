import SwiftUI

/// 耳機偵測偏好與最近的肯定、否定事件，能力由機型配置決定。
struct HeadGesturesView: View {
    @Bindable var bluetooth: BluetoothManager
    private var status: BudsStatus { bluetooth.status }
    var body: some View {
        Form {
            Section {
                Toggle(
                    "Enable head gestures on this Mac",
                    isOn: Binding(
                        get: { (status.headGestureMask ?? 2) & 1 != 0 },
                        set: {
                            bluetooth.setHeadGestures(
                                enabled: $0, nodForPositive: (status.headGestureMask ?? 2) & 2 != 0)
                        }))
                Picker(
                    "Positive gesture",
                    selection: Binding(
                        get: { (status.headGestureMask ?? 2) & 2 != 0 },
                        set: {
                            bluetooth.setHeadGestures(
                                enabled: (status.headGestureMask ?? 2) & 1 != 0, nodForPositive: $0)
                        })
                ) {
                    Text("Nod").tag(true)
                    Text("Shake head").tag(false)
                }
                // 實際偵測事件才建立結果列，本地偏好不冒充感測資料。
                if let positive = status.lastHeadGesture {
                    LabeledContent("Last detected gesture") { Text(positive ? "Positive" : "Negative") }
                }
                Text(
                    "This Mac stores the detection preference. Call and assistant responses require integration with the app handling them."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
