import SwiftUI
import UIKit

// MARK: - GlassPillPicker — Tab bar 式可拖曳玻璃鏡片選擇器
//
// 依賴同目錄 `Surface.swift`（`selectionLens`）與 `HorizontalPanGesture.swift`；設計與踩坑 → references/liquid-glass-ios26.md。
//
// 手感對齊 iOS 26 底部 Tab bar：
//   · 固定的毛玻璃膠囊殼（`.ultraThinMaterial`，**不用 glassEffect**：鏡片是 glassEffect，殼再玻璃 = 巢狀，真機粗黑邊）
//   · 一顆常駐鏡片停在選中 chip 上，點別的 chip 滑過去；按住拖 → 鏡片跟手、經過哪個選哪個、放手吸附
//   · chip 放得下靜態排列；放不下才在殼內捲（此時只能點、不拖）
//
// 用法：
//   GlassPillPicker(items: Period.allCases, selection: $period,
//                   onSelect: { if $0 == .custom { showSheet = true } }) { p, active in
//       Text(p.label).padding(.horizontal, 10).padding(.vertical, 5)
//           .foregroundColor(active ? .accentColor : .secondary)   // 鏡片透明，靠字色標記選中
//   }

struct GlassPillPicker<Item: Hashable, Label: View>: View {
    let items: [Item]
    @Binding var selection: Item
    /// 17–25 替身鏡片的淡底色（iOS 26 鏡片不染色）。分類型 pill 可依項目給 hue。
    var accent: (Item) -> Color = { _ in .accentColor }
    /// 選中（點或拖到）某項時的副作用（開 sheet / 清細篩…）。
    var onSelect: ((Item) -> Void)? = nil
    @ViewBuilder var label: (Item, Bool) -> Label

    @State private var frames: [Item: CGRect] = [:]
    /// 拖曳中鏡片中心 x（殼內座標）；nil = 沒在拖。
    @State private var dragX: CGFloat? = nil

    private let space = "glassPillPicker"
    private let spacing: CGFloat = 2
    private let inset: CGFloat = 3

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(draggable: true).padding(inset)
            ScrollView(.horizontal, showsIndicators: false) {
                row(draggable: false).padding(inset)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .clipShape(Capsule())
        }
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func row(draggable: Bool) -> some View {
        HStack(spacing: spacing) {
            ForEach(items, id: \.self) { item in
                let active = item == selection
                Button { select(item, haptic: .light) } label: {
                    label(item, active).contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { frames[item] = $0 }
            }
        }
        .coordinateSpace(name: space)
        // 鏡片放 background：真機文字在鏡片上方正常可見；模擬器會把玻璃畫成不透明蓋住字，是模擬器問題勿改架構。
        .background { lens }
        .modifier(PickerPanBridge(enabled: draggable, onChanged: { x in handleDrag(x: x) }, onEnded: { dragX = nil }))
    }

    private var lensRect: CGRect? {
        guard let base = frames[selection] else { return nil }
        guard let x = dragX else { return base }
        let mids = frames.values.map(\.midX)
        guard let lo = mids.min(), let hi = mids.max() else { return base }
        let cx = min(max(x, lo), hi)
        return CGRect(x: cx - base.width / 2, y: base.minY, width: base.width, height: base.height)
    }

    @ViewBuilder
    private var lens: some View {
        if let r = lensRect {
            Capsule().fill(Color.clear)
                .selectionLens(fallback: accent(selection))
                .frame(width: r.width, height: r.height)
                .scaleEffect(dragX == nil ? 1 : 1.08)          // 按住「拿起來」的回饋
                .position(x: r.midX, y: r.midY)
                .animation(dragX == nil ? .spring(response: 0.35, dampingFraction: 0.8)
                                        : .interactiveSpring(response: 0.18, dampingFraction: 0.85), value: r)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dragX == nil)
                .allowsHitTesting(false)
        }
    }

    private func handleDrag(x: CGFloat) {
        dragX = x
        if let nearest = items.min(by: { abs((frames[$0]?.midX ?? 0) - x) < abs((frames[$1]?.midX ?? 0) - x) }),
           nearest != selection {
            select(nearest, haptic: .selection)
        }
    }

    private enum Haptic { case light, selection }

    private func select(_ item: Item, haptic: Haptic) {
        if item != selection {
            switch haptic {
            case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case .selection: UISelectionFeedbackGenerator().selectionChanged()
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = item }
        }
        onSelect?(item)
    }
}

/// 拖曳橋接：iOS 18+ 走 `HorizontalPanGesture`（只在水平為主時 begin，垂直讓給 ScrollView / sheet 收合），17 退 DragGesture。
private struct PickerPanBridge: ViewModifier {
    let enabled: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if !enabled {
            content
        } else if #available(iOS 18.0, *) {
            content.gesture(HorizontalPanGesture(onChanged: { _, _, loc in onChanged(loc.x) },
                                                 onEnded: { _, _ in onEnded() }))
        } else {
            content.gesture(DragGesture(minimumDistance: 10)
                .onChanged { v in onChanged(v.location.x) }
                .onEnded { _ in onEnded() })
        }
    }
}
