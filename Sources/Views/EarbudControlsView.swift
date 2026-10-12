import SwiftUI

/// 機型能力決定長按輪替、操作開關、燈效與頭部動作的原生表單。
struct EarbudControlsView: View {
    @Bindable var bluetooth: BluetoothManager
    private var status: BudsStatus { bluetooth.status }

    private var holdActions: [TouchHoldAction] {
        // 可選動作須來自注入碼表，無模型時保持空集合。
        guard let profile = bluetooth.connectedModel?.profile else { return [] }
        return TouchHoldAction.allCases.filter {
            profile.touchActionCodes[$0.rawValue] != nil
                || (status.touchAssistantSupported && profile.assistantProviders[$0.rawValue] != nil)
        }
    }

    /// 數位助理類型由耳機回報，Bixby 與 Google 保留獨立語意。
    ///
    /// - Parameters:
    ///   - action: 機型配置可編碼的長按動作。
    /// - Returns: 長按動作名稱，助理提供者依耳機回報區分。
    private func actionTitle(_ action: TouchHoldAction) -> String {
        // 支援新助理欄位時保留 Bixby 與 Google 名稱，避免混同音量。
        if action == .voiceAssistant, status.touchAssistantSupported { return "Bixby" }
        return action.displayName
    }

    var body: some View {
        Form {
            Section("Touch and hold") {
                Picker(
                    "Left",
                    selection: Binding(
                        get: { status.touchHoldLeft },
                        set: {
                            // 一耳選取時保留另一耳已回報值，缺值不推測動作。
                            if let value = $0, let other = status.touchHoldRight {
                                bluetooth.setTouchHoldActions(left: value, right: other)
                            }
                        })
                ) {
                    Text("Unrecognized action").tag(TouchHoldAction?.none)
                    // 左耳長按選項依機型可用動作列出。
                    ForEach(
                        holdActions
                    ) {
                        Text(LocalizedStringKey(actionTitle($0))).tag(
                            Optional($0))
                    }
                }.disabled(status.touchHoldRight == nil)
                // 噪音輪替只屬於 noiseControl 動作，其餘助理與音量沒有模式遮罩。
                if status.touchHoldLeft == .noiseControl {
                    cycleOptions("Left cycle", cycle: status.noiseCycleLeft, other: status.noiseCycleRight) {
                        // 變更左耳輪替時保留已回報的右耳遮罩。
                        if let other = status.noiseCycleRight { bluetooth.setNoiseControlCycle(left: $0, right: other) }
                    }
                }
                Picker(
                    "Right",
                    selection: Binding(
                        get: { status.touchHoldRight },
                        set: {
                            // 一耳選取時保留另一耳已回報值，缺值不推測動作。
                            if let value = $0, let other = status.touchHoldLeft {
                                bluetooth.setTouchHoldActions(left: other, right: value)
                            }
                        })
                ) {
                    Text("Unrecognized action").tag(TouchHoldAction?.none)
                    // 右耳選項沿用同一動作資料與寫入服務。
                    ForEach(
                        holdActions
                    ) {
                        Text(LocalizedStringKey(actionTitle($0))).tag(
                            Optional($0))
                    }
                }.disabled(status.touchHoldLeft == nil)
                // 右耳沿用同一個輪替元件與當前左耳快照。
                if status.touchHoldRight == .noiseControl {
                    cycleOptions("Right cycle", cycle: status.noiseCycleRight, other: status.noiseCycleLeft) {
                        // 變更右耳輪替時保留已回報的左耳遮罩。
                        if let other = status.noiseCycleLeft { bluetooth.setNoiseControlCycle(left: other, right: $0) }
                    }
                }
            }
            Section("Gesture controls") {
                // 各個手勢開關使用已回報旗標，寫入保留其他手勢。
                ForEach(TouchGesture.allCases) { gesture in
                    Toggle(
                        LocalizedStringKey(gesture.displayName),
                        isOn: Binding(
                            get: { status.gestureEnabled?[gesture.rawValue] ?? false },
                            set: { bluetooth.setTouchGesture(gesture, enabled: $0) })
                    )
                    .disabled(status.gestureEnabled == nil || status.touchCommandTail == nil || status.touchpadLocked)
                }
                Toggle(
                    "Touchpad lock",
                    isOn: Binding(
                        get: { status.touchpadLocked },
                        set: {
                            bluetooth.setTouchpadLock($0)
                        })
                ).disabled(status.gestureEnabled == nil || status.touchCommandTail == nil)
                // 不完整操作回報保持停用，避免寫回其他未知旗標。
                if status.gestureEnabled == nil {
                    Text("Waiting for earbud settings").font(.caption).foregroundStyle(.secondary)
                }
            }
            // 燈效能力由 JSON 注入，其他耳機不顯示未提供的資料列。
            if bluetooth.connectedModel?.profile.features.contains(.bladeLights) == true {
                Section("Blade lights") {
                    Picker(
                        "Lighting style",
                        selection: Binding(
                            get: { status.touchCommandTail?.first.flatMap { (1...3).contains($0) ? Int($0) : nil } },
                            set: {
                                // 等待選項以 nil 表示，只有有效燈效碼才送到耳機。
                                if let value = $0 { bluetooth.setLightingStyle(value) }
                            })
                    ) {
                        Text("Waiting for earbud settings").tag(Int?.none).disabled(true)
                        Text("Steady").tag(Optional(1))
                        Text("Blinking").tag(Optional(2))
                        Text("Breathing").tag(Optional(3))
                    }.disabled(status.gestureEnabled == nil || status.touchCommandTail == nil)
                    Text("Pinch and hold both earbuds to turn the lights on or off.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

        }.formStyle(.grouped)
    }

    /// 兩耳共用四種模式選擇，傳送完整遮罩並保留另一耳設定。
    ///
    /// - Parameters:
    ///   - title: 目前耳機輪替選項的翻譯標題。
    ///   - cycle: 目前耳機已回報的輪替遮罩，nil 顯示等待。
    ///   - other: 另一耳已回報的輪替遮罩，寫入時須一併保留。
    ///   - change: 使用者選取有效遮罩時呼叫的寫入入口。
    /// - Returns: 四種模式的輪替選項，缺少回報時顯示等待。
    private func cycleOptions(
        _ title: LocalizedStringKey, cycle: NoiseControlCycle?, other: NoiseControlCycle?,
        change: @escaping (NoiseControlCycle) -> Void
    ) -> some View {
        VStack(alignment: .leading) {
            Text(title)
            // 已驗證的遮罩才可切換模式，未知值保留文字狀態。
            if let cycle {
                // 輪替選項限制在目前機型的已知聆聽模式。
                ForEach(bluetooth.connectedModel?.listenModes ?? []) { mode in
                    Toggle(
                        LocalizedStringKey(mode.displayName),
                        isOn: Binding(
                            get: { cycle.contains(mode) },
                            set: { enabled in
                                let mask = enabled ? cycle.rawValue | mode.cycleBit : cycle.rawValue & ~mode.cycleBit
                                // 至少兩個模式才能輪替，服務層再次驗證完整左右遮罩。
                                if mask.nonzeroBitCount >= 2 { change(NoiseControlCycle(rawValue: mask)) }
                            })
                    )
                    .toggleStyle(.checkbox)
                    .disabled(other == nil || (cycle.contains(mode) && cycle.rawValue.nonzeroBitCount <= 2))
                }
                Text("Select at least two modes.").font(.caption).foregroundStyle(.secondary)
            } else {
                // 輪替尚未回報時顯示等待文字，避免以預設遮罩寫入。
                Text("Unrecognized cycle").foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}
