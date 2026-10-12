import SwiftUI

/// 尋找音效與靜音命令，離開頁面時傳送停止命令。
struct FindMyEarbudsView: View {
    @Bindable var bluetooth: BluetoothManager
    @State private var requestedRinging = false
    @State private var muteLeft = false
    @State private var muteRight = false

    var body: some View {
        Form {
            Section("Find earbuds") {
                Text(
                    LocalizedStringKey(
                        requestedRinging
                            ? "Find sound requested. Use Stop to end it." : "Ring your earbuds to locate them."))
                Button(LocalizedStringKey(requestedRinging ? "Stop" : "Play sound")) {
                    let next = !requestedRinging
                    // 原生控制封包排入後才更新等待狀態，不宣稱已聽見實際音效。
                    if bluetooth.findMyBuds(start: next) {
                        requestedRinging = next
                        // 新一輪尋找將本地靜音選擇回到兩耳可響鈴。
                        if next {
                            muteLeft = false
                            muteRight = false
                        }
                    }
                }
            }
            // 尋找期間才提供左右靜音操作，保持完整兩耳參數。
            if requestedRinging {
                Section("Mute") {
                    Toggle(
                        "Left",
                        isOn: Binding(
                            get: { muteLeft },
                            set: {
                                // 傳輸未排入時保留原本本地選取，裝置回覆由服務揭露。
                                if bluetooth.setMuteEarbud(left: $0, right: muteRight) { muteLeft = $0 }
                            }))
                    Toggle(
                        "Right",
                        isOn: Binding(
                            get: { muteRight },
                            set: {
                                // 傳輸未排入時保留原本本地選取，裝置回覆由服務揭露。
                                if bluetooth.setMuteEarbud(left: muteLeft, right: $0) { muteRight = $0 }
                            }))
                }
            }
        }.formStyle(.grouped)
            .onDisappear {
                // 只有此頁啟動過尋找音效，離開時才送出停止命令。
                if requestedRinging { bluetooth.findMyBuds(start: false) }
            }
    }
}
