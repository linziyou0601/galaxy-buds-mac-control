import SwiftUI

/// 手機式四圓排列，控制項材質、選取與明暗色交由系統 ButtonStyle。
struct ListenModePicker: View {
    let modes: [NoiseControlMode]
    let selection: NoiseControlMode?
    var circleSize: CGFloat = InterfaceMetrics.modeDiameter
    let onSelect: (NoiseControlMode) -> Void

    var body: some View {
        GeometryReader { geometry in
            let cell = geometry.size.width / CGFloat(max(1, modes.count))
            ZStack(alignment: .top) {
                Path { path in
                    // 連接線只放在相鄰模式圓之間，單一模式沒有連接線。
                    for index in 0..<max(0, modes.count - 1) {
                        let start = cell * (CGFloat(index) + 0.5) + circleSize / 2 + 4
                        let end = cell * (CGFloat(index) + 1.5) - circleSize / 2 - 4
                        // 狹窄版面不繪製負長度連線，控制項維持系統圓形 Button。
                        if end > start {
                            path.move(to: CGPoint(x: start, y: circleSize / 2))
                            path.addLine(to: CGPoint(x: end, y: circleSize / 2))
                        }
                    }
                }.stroke(.secondary.opacity(0.18), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                HStack(spacing: 0) {
                    // 各模式共用相同按鈕建立流程與操作入口。
                    ForEach(modes) { mode in
                        VStack(spacing: 6) {
                            modeButton(mode).frame(width: circleSize, height: circleSize)
                            Text(LocalizedStringKey(mode.displayName)).font(.caption).multilineTextAlignment(.center)
                                .foregroundStyle(mode == selection ? Color.accentColor : Color.secondary)
                                .accessibilityHidden(true)
                        }.frame(width: cell)
                    }
                }
            }
        }.frame(height: circleSize + 22)
    }

    /// 原生玻璃按鈕樣式處理材質、焦點與互動，選取模式採 prominent 樣式。
    ///
    /// - Parameters:
    ///   - mode: 要選擇或查詢的已知噪音模式，協定碼由共用列舉提供。
    /// - Returns: 指定模式的原生按鈕，依選取與系統版本呈現樣式。
    @ViewBuilder private func modeButton(_ mode: NoiseControlMode) -> some View {
        let control = Button {
            onSelect(mode)
        } label: {
            Image(systemName: mode.iconName)
                .font(.title3).symbolRenderingMode(.monochrome)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel(Text(LocalizedStringKey(mode.displayName)))
        .accessibilityAddTraits(mode == selection ? .isSelected : [])
        // Liquid Glass 是公開系統版本能力，舊版沿用原生 bordered 樣式。
        if #available(macOS 26, *) {
            // 選中狀態交由原生 prominent 樣式處理，圖示對比由系統決定。
            if mode == selection {
                control.buttonStyle(.glassProminent).buttonSizing(.flexible)
            } else {
                // 未選取模式保留系統預設玻璃樣式。
                control.buttonStyle(.glass).buttonSizing(.flexible)
            }
        } else {
            // 較舊系統使用原生 bordered，選取語意仍由系統色呈現。
            control.buttonStyle(.bordered).tint(mode == selection ? Color.accentColor : nil)
        }
    }
}
