import SwiftUI

/// 以原生 Slider 與增減按鈕呈現配置的離散等級。
struct DiscreteLevelSlider: View {
    var label: LocalizedStringKey = "ANC strength"
    let level: Int
    let count: Int?
    let onChange: (Int) -> Void

    var body: some View {
        // 至少兩段有效範圍才能建立離散滑桿。
        if let count, count > 1 {
            let upperBound = count - 1
            let clamped = max(0, min(upperBound, level))
            HStack {
                Button {
                    onChange(clamped - 1)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless).disabled(clamped == 0).accessibilityLabel(
                    Text("Decrease level") + Text(verbatim: " ") + Text(label))
                Slider(
                    value: Binding(get: { Double(clamped) }, set: { onChange(Int($0.rounded())) }),
                    in: 0...Double(upperBound), step: 1
                ) { Text(label) }
                .labelsHidden().accessibilityValue("\(clamped + 1)/\(count)")
                Button {
                    onChange(clamped + 1)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless).disabled(clamped == upperBound).accessibilityLabel(
                    Text("Increase level") + Text(verbatim: " ") + Text(label))
            }.controlSize(.small)
        } else {
            // 未知段數與無效範圍以等待狀態呈現，避免猜測可操作值。
            Text("Waiting for earbud settings").foregroundStyle(.secondary)
        }
    }
}
