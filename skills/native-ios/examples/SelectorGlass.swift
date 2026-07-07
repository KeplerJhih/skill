import SwiftUI

/// 選擇類控件(下拉 Menu / 開 sheet 的 Button)的**中性玻璃底**:
/// 原生 `Material` + 20pt 連續圓角 + 頂亮→底淡細白描邊 + 低仰角軟陰影。
///
/// **為什麼不用系統 Menu 預設玻璃**:iOS 26 系統玻璃會**吸收 label 內前景 icon 的色調**
/// (例:label 裡有一顆金色 icon → 整顆膠囊被染金);自製 Material 底不吃 tint,永遠中性。
/// 用法:Menu / Button 加 `.buttonStyle(.plain)` 壓掉系統玻璃,label content 套 `.selectorGlass()`。
///
/// **零 design-system 依賴,可 drop-in 任何 SwiftUI 專案**(iOS 15+)。
extension View {
    func selectorGlass(cornerRadius: CGFloat = 20) -> some View {
        modifier(SelectorGlassStyle(cornerRadius: cornerRadius))
    }
}

private struct SelectorGlassStyle: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            // shadow 掛在背景 shape(掛外層會連 label 文字一起投影)。
            .background(
                shape.fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.06), radius: 5, y: 1)
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
            )
    }
}

/// 開 sheet 的 Button 用:SelectorGlass 外觀 + 平滑 spring 按壓縮放。
struct SelectorGlassButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 20

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .selectorGlass(cornerRadius: cornerRadius)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
