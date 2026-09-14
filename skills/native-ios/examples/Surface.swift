import SwiftUI
import UIKit

// MARK: - Surface — 圓角尺 + 表面 modifier（iOS 26 Liquid Glass 三層分工）
//
// 零 design-system 依賴，可 drop-in 任何 SwiftUI 專案：顏色由呼叫端注入（預設吃系統語意色）。
// 三層原則、真機踩坑與驗收 → references/liquid-glass-ios26.md。
// **`#available(iOS 26)` 只允許出現在本檔**，Feature 層不得自行寫 availability 分支。

/// 圓角尺：全部 `.continuous`；巢狀同心（內 = 外 − 內距）。
enum Radius {
    static let xs: CGFloat = 6     // 徽章、小 tag
    static let sm: CGFloat = 10    // 圖示底、卡內小格
    static let md: CGFloat = 14    // 輸入框、子卡、群組卡
    static let lg: CGFloat = 20    // 卡片、面板、下拉
    static let xl: CGFloat = 28    // hero 容器、sheet 角
}

func surfaceShape(_ radius: CGFloat) -> RoundedRectangle {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
}

/// CTA 樣式：struct + static 讓 `.filled` 與 `.filled(enabled:)` 兩種寫法並存（enum 做不到）。
struct CTAStyle {
    enum Kind { case filled(enabled: Bool), outline(Color), dashed(Color) }
    let kind: Kind
    static let filled = CTAStyle(kind: .filled(enabled: true))
    static func filled(enabled: Bool) -> CTAStyle { CTAStyle(kind: .filled(enabled: enabled)) }
    static func outline(_ color: Color) -> CTAStyle { CTAStyle(kind: .outline(color)) }
    static func dashed(_ color: Color) -> CTAStyle { CTAStyle(kind: .dashed(color)) }
}

extension View {
    /// 內容層卡片：實色底 + 0.5 細框 + 連續圓角，並以同形裁切內容（卡內直角 accent 條不露角）。
    func contentCard(radius: CGFloat = Radius.lg,
                     fill: Color = Color(.secondarySystemBackground),
                     stroke: Color = Color(.separator).opacity(0.5),
                     lineWidth: CGFloat = 0.5) -> some View {
        let shape = surfaceShape(radius)
        return background(fill, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(stroke, lineWidth: lineWidth))
    }

    /// 只畫圓角細框、不填底、不裁切。底下若另有直角填色請改用 `contentCard(fill:)`。
    func roundedStroke(_ color: Color, lineWidth: CGFloat = 0.5,
                       radius: CGFloat = Radius.md, dash: [CGFloat]? = nil) -> some View {
        overlay(surfaceShape(radius).strokeBorder(color, style: StrokeStyle(lineWidth: lineWidth, dash: dash ?? [])))
    }

    /// 輸入框表面：填色 + 細框 + md 圓角；錯誤態紅框 1pt。tap-to-focus 面積由 caller 的 `.contentShape(Rectangle())` 保留。
    func fieldSurface(radius: CGFloat = Radius.md, isError: Bool = false,
                      fill: Color = Color(.tertiarySystemBackground),
                      stroke: Color = Color(.separator).opacity(0.5)) -> some View {
        let shape = surfaceShape(radius)
        return background(fill, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(isError ? Color.red : stroke, lineWidth: isError ? 1 : 0.5))
    }

    /// pill / chip：active = 填色 + 反白字、inactive = 細框。放在玻璃殼內時 `bordered: false` 免雙框。
    /// iOS 26 坑：chip 進 Menu 必配 `.buttonStyle(.plain)`、進 toolbar 必配 `sharedBackgroundVisibility(.hidden)`。
    func pillChip(active: Bool, accent: Color = .accentColor, inactiveFill: Color = .clear,
                  inactiveStroke: Color = Color(.separator).opacity(0.5), bordered: Bool = true) -> some View {
        background(active ? accent : inactiveFill, in: Capsule())
            .overlay(Capsule().strokeBorder(active ? accent : inactiveStroke, lineWidth: bordered ? 0.5 : 0))
            .contentShape(Capsule())
    }

    /// CTA 膠囊：`.filled` 帶軟陰影；disabled 用 `.filled(enabled: canSave)`（淡色、無陰影）。
    func capsuleCTA(_ style: CTAStyle, accent: Color = .accentColor, disabledFill: Color? = nil) -> some View {
        modifier(CapsuleCTAStyle(style: style, accent: accent, disabledFill: disabledFill ?? accent.opacity(0.35)))
    }

    /// 導航層 Liquid Glass：iOS 26 `.glassEffect`（interactive 可互動），17–25 磨砂替身 + 細白邊（elevated 加陰影）。
    /// 只給浮在內容上方的控制層：角落鈕、pill 殼以外的浮動 bar、鍵盤拉柄。**不要套在會滑動的內容上、不要巢狀**。
    func chromeGlass<S: Shape>(in shape: S, interactive: Bool = false, elevated: Bool = false) -> some View {
        modifier(ChromeGlassStyle(shape: shape, interactive: interactive, elevated: elevated))
    }

    /// 選擇器常駐鏡片（GlassPillPicker 用）：iOS 26 不染色 interactive 玻璃（對齊 Tab bar），17–25 accent 18% 淡底。
    /// 套在 `Capsule().fill(.clear)` 上、由呼叫端定位。**鏡片不染色**（染金在真機像實心色塊），選中靠文字改色。
    func selectionLens(fallback: Color) -> some View {
        modifier(SelectionLens(fallback: fallback))
    }

    /// 釘底 footer（ZStack(.bottom) sibling 的儲存 / 確認列）的磨砂底：材質往下延伸到螢幕底、頂緣 35% 漸淡。
    /// 掛在 footer 最外層；ScrollView 內容仍留 `.padding(.bottom, ~100)`。
    func pinnedFooterBackdrop(tint: Color = Color(.systemBackground)) -> some View {
        modifier(PinnedFooterBackdrop(tint: tint))
    }
}

// MARK: - Implementations

private struct CapsuleCTAStyle: ViewModifier {
    let style: CTAStyle
    let accent: Color
    let disabledFill: Color

    func body(content: Content) -> some View {
        switch style.kind {
        case .filled(let enabled):
            content
                .background(enabled ? accent : disabledFill, in: Capsule())
                .shadow(color: accent.opacity(enabled ? 0.28 : 0), radius: 10, x: 0, y: 5)
        case .outline(let color):
            content.overlay(Capsule().strokeBorder(color, lineWidth: 0.5))
        case .dashed(let color):
            content.overlay(Capsule().strokeBorder(color, style: StrokeStyle(lineWidth: 0.5, dash: [4])))
        }
    }
}

private struct ChromeGlassStyle<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let elevated: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            let base = content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 0.5))
            if elevated {
                base.shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 6)
                    .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 2)
            } else {
                base
            }
        }
    }
}

private struct SelectionLens: ViewModifier {
    let fallback: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(fallback.opacity(0.18), in: Capsule())
        }
    }
}

private struct PinnedFooterBackdrop: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .padding(.top, 14)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Rectangle().fill(tint.opacity(0.4))
                }
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.35)],
                                     startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea(edges: .bottom)
            }
    }
}
