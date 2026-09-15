import SwiftUI
import UIKit

// MARK: - HorizontalPanGesture — 橫向元件的統一手勢入口（UIKit pan 橋接）
//
// 零 design-system 依賴，可 drop-in 任何 SwiftUI 專案。設計推導 → references/swipe-action-row.md「手勢所有權」。
//
// 解決什麼：SwiftUI `DragGesture` 放在 ScrollView 內時，由 SwiftUI 分配手勢所有權——起手橫向分量
// 只要 ≳ 0.9 倍垂直，整條手勢就判給元件，**被判走的手勢不會回到 ScrollView / sheet 下拉收合**。
// 結果是「整頁都是列」的 sheet 往下拉常常收不了、斜向捲動卡住。
//
// 本橋接用 UIKit `UIPanGestureRecognizer`：
//   · `gestureRecognizerShouldBegin` 只在「水平為主」時 begin；垂直手勢元件完全不參與，
//     ScrollView 捲動 / sheet 收合 / 系統 List 行為原封拿到整條
//   · 與 UIScrollView 的 pan 不並存，且要求 scroll pan 等本 pan 失敗（`shouldBeRequiredToFailBy`）
//     → 仲裁順序確定：橫向本 pan 先 begin、scroll 失敗；縱向本 pan 立刻失敗、scroll 接手，只多等一幀
//   · `cancelsTouchesInView` = begin 當下取消底下的 tap
//
// 用法（iOS 18+；17 用下方 HorizontalPanBridge 自動退回 DragGesture）：
//   content.gesture(HorizontalPanGesture(
//       onBegan: { … },
//       shouldBegin: { dx in canShift(dx < 0 ? 1 : -1) },   // 選填:該方向到底就不接手 → 手勢原封給外層 pager
//       onChanged: { dx, dy, location in … },
//       onEnded: { dx, predictedExtra in … }))
//
// `shouldBegin`:水平為主之外的額外 begin 條件（參數 = 起手 dx，正 = 往右）。回 false 本 pan 不 begin，
// 觸摸交給下一個辨識器——放在 page TabView 裡的月曆 / 輪播用它做「翻得了就翻，翻不了就切 tab」：
// 沒這個鉤子，元件在邊界會吃掉手勢卻沒反應（SwiftUI DragGesture 做不到「判斷後退回」，UIKit 才有）。
//
// 注意：UIKit 的 translation 不含起手 ~10pt 滯後（真機連續取樣差異可忽略；模擬器 10pt 步進會少 10–20pt）。

@available(iOS 18.0, *)
struct HorizontalPanGesture: UIGestureRecognizerRepresentable {
    var onBegan: () -> Void = {}
    /// 水平為主之外的額外 begin 條件（參數 = 起手 dx）；回 false 不接手、手勢交給外層。nil = 只看方向。
    var shouldBegin: ((CGFloat) -> Bool)? = nil
    /// (translationX, translationY, 目前觸點在本 view 座標的位置)
    var onChanged: (CGFloat, CGFloat, CGPoint) -> Void
    /// (translationX, 鬆手後預期再滑距離 pt ≈ velocityX × 0.12s；與 SwiftUI predictedEndTranslation − translation 同量級)
    var onEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        context.coordinator.shouldBegin = shouldBegin
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = true
        pan.maximumNumberOfTouches = 1
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.shouldBegin = shouldBegin   // closure 會隨 view 重建更新（捕捉最新的 canShift 狀態）
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        guard let view = recognizer.view else { return }
        let t = recognizer.translation(in: view)
        let loc = recognizer.location(in: view)
        switch recognizer.state {
        case .began:
            onBegan()
            onChanged(t.x, t.y, loc)
        case .changed:
            onChanged(t.x, t.y, loc)
        case .ended, .cancelled, .failed:
            onEnded(t.x, recognizer.velocity(in: view).x * 0.12)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var shouldBegin: ((CGFloat) -> Bool)?

        // velocity≈0 fallback：極慢起手 velocity 偶為 0，改用 translation 判主軸。
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let p = g as? UIPanGestureRecognizer, let view = p.view else { return false }
            let v = p.velocity(in: view)
            let useVelocity = abs(v.x) + abs(v.y) > 1
            let dx = useVelocity ? v.x : p.translation(in: view).x
            let dy = useVelocity ? v.y : p.translation(in: view).y
            guard abs(dx) > abs(dy) else { return false }
            return shouldBegin?(dx) ?? true
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            false
        }

        /// scroll pan 等本 pan 失敗再開始：本 pan 對垂直手勢在第一次判定就失敗，scroll 只多等一幀；
        /// 對水平手勢本 pan 先 begin，scroll pan 隨之失敗，不會出現「列在滑、頁也在捲」。
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView
        }
    }
}

/// iOS 18+ 掛 `HorizontalPanGesture`，17 退 SwiftUI `DragGesture`（`minimumDistance` 走舊門檻；
/// 17 路徑的方向仍由 caller 在第一幀決定，因為 SwiftUI 可能把偏直的手勢也交給你）。
struct HorizontalPanBridge: ViewModifier {
    var minimumDistance: CGFloat = 18
    var onBegan: () -> Void = {}
    /// (translationX, translationY)
    let onChanged: (CGFloat, CGFloat) -> Void
    /// (translationX, predictedExtra)
    let onEnded: (CGFloat, CGFloat) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.gesture(HorizontalPanGesture(onBegan: onBegan,
                                                 onChanged: { dx, dy, _ in onChanged(dx, dy) },
                                                 onEnded: onEnded))
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: minimumDistance)
                    .onChanged { v in onChanged(v.translation.width, v.translation.height) }
                    .onEnded { v in onEnded(v.translation.width, v.predictedEndTranslation.width - v.translation.width) }
            )
        }
    }
}
