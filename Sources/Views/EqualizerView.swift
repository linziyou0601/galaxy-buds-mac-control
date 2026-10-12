import AppKit
import SwiftUI

/// 九段 EQ 使用原生垂直滑桿，預設曲線採耳機回報值。
struct EqualizerView: View {
    @Bindable var bluetooth: BluetoothManager
    private let frequencies = ["63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    private var status: BudsStatus { bluetooth.status }
    private var isCustom: Bool { status.equalizerPreset == .custom }

    private var bands: [Int]? {
        // 自訂值與唯讀預設曲線從各自的已回報快照取得。
        if isCustom { return status.customEqualizerBands }
        let index = status.equalizerPreset.rawValue
        // 尚未回報的曲線索引保持未知，不推測為平坦。
        guard status.presetEqualizerCurves.indices.contains(index) else { return nil }
        return status.presetEqualizerCurves[index]
    }

    var body: some View {
        Form {
            Section("Preset") {
                Picker("Mode", selection: Binding(get: { status.equalizerPreset }, set: { bluetooth.setEqualizer($0) }))
                {
                    // 所有 EQ 預設使用共用名稱與原生選取。
                    ForEach(EqualizerPreset.allCases) { Text(LocalizedStringKey($0.displayName)).tag($0) }
                }
            }
            Section("Frequency bands") {
                // 完整九段曲線才呈現原生編輯控制。
                if let bands, bands.count == frequencies.count {
                    HStack {
                        // 九個頻段依固定頻率順序建立垂直滑桿。
                        ForEach(frequencies.indices, id: \.self) { index in
                            VStack(spacing: 8) {
                                Text("\(bands[index])").monospacedDigit()
                                EqualizerBandSlider(
                                    value: Binding(
                                        get: { Double(bands[index]) },
                                        set: { bluetooth.setCustomEqualizerBand(index, value: Int($0.rounded())) }),
                                    label: frequencies[index] + " Hz", enabled: isCustom
                                )
                                .frame(width: 24, height: 190)
                                Text(frequencies[index]).font(.caption)
                            }.frame(maxWidth: .infinity)
                        }
                    }.padding(.vertical, 8)
                    // 自訂值與唯讀預設曲線從各自的已回報快照取得。
                    if isCustom {
                        Button("Reset to flat") { bluetooth.setCustomEqualizer(bands: Array(repeating: 0, count: 9)) }
                    } else {
                        // 預設曲線未回報時顯示等待狀態。
                        Text("Preset curve (read-only)").foregroundStyle(.secondary)
                    }
                } else {
                    // EQ 模式未回報時不建立可編輯曲線。
                    Text("Waiting for preset curves").foregroundStyle(.secondary)
                    // 自訂值與唯讀預設曲線從各自的已回報快照取得。
                    if isCustom {
                        Button("Start with a flat custom curve") {
                            bluetooth.setCustomEqualizer(bands: Array(repeating: 0, count: 9))
                        }
                    }
                }
            }
        }.formStyle(.grouped)
    }
}

/// AppKit 垂直 NSSlider，將連續操作轉成整數增益。
private struct EqualizerBandSlider: NSViewRepresentable {
    @Binding var value: Double
    let label: String
    let enabled: Bool

    /// 建立原生垂直滑桿，-10...10 dB 範圍沿用九段 EQ 協定。
    ///
    /// - Parameters:
    ///   - context: SwiftUI 提供的橋接環境，包含此 View 的 coordinator。
    /// - Returns: 範圍為 -10...10 dB 的原生垂直滑桿。
    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(frame: NSRect(x: 0, y: 0, width: 24, height: 190))
        slider.minValue = -10
        slider.maxValue = 10
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        return slider
    }

    /// 同步增益、啟用狀態與可存取標籤，預設曲線維持唯讀。
    ///
    /// - Parameters:
    ///   - slider: AppKit 提供的垂直增益滑桿。
    ///   - context: SwiftUI 提供的橋接環境，包含此 View 的 coordinator。
    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        slider.doubleValue = value
        slider.isEnabled = enabled
        slider.setAccessibilityLabel(label)
    }

    /// 建立 AppKit 事件橋接，binding 由 updateNSView 更新。
    ///
    /// - Returns: 保存此 View binding 與原生回呼的 coordinator。
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    /// 將 AppKit 控制項事件交回 SwiftUI binding。
    @MainActor final class Coordinator: NSObject {
        var parent: EqualizerBandSlider
        /// 保存首次建立時的 View 快照，原生回呼使用最新 binding。
        ///
        /// - Parameters:
        ///   - parent: 目前 View 與 binding 快照，由原生 coordinator 保存。
        init(parent: EqualizerBandSlider) { self.parent = parent }
        /// 將原生連續值轉為整數增益，再由服務寫入完整九段曲線。
        ///
        /// - Parameters:
        ///   - slider: AppKit 提供的垂直增益滑桿。
        @objc func changed(_ slider: NSSlider) { parent.value = slider.doubleValue.rounded() }
    }
}
