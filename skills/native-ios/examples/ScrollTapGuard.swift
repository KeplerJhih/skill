import SwiftUI
import UIKit

// ScrollView 內 tap 列的「捲動誤觸」雙防線。
//   症狀：捲動頁上的 Button / onTapGesture 列，快滑起手或慢速小拖放手會被誤判成點擊
//        （SwiftUI 對「按下後慢速小拖」會 commit 給 Button — 移動 10~30pt 放手仍觸發，
//         實測 20pt / 0.5s 必中；UIScrollView 的 canCancelContentTouches 管不到 SwiftUI 手勢）。
//   若 app 又為了修「ScrollView 內 TextField tap-to-focus 慢半拍」全域設過
//   `UIScrollView.appearance().delaysContentTouches = false`，誤觸會更嚴重（碰到立即按下）。
//
// 用法：掛在 ScrollView 的「內容」上（不是 ScrollView 本身，見下方註解）：
//   ScrollView { content.restoreTouchDelays() }
// 適用：無 TextField 的捲動 tap 列頁（選項頁 / 清單 / 統計卡內可點列）。表單頁勿掛。
// 相容：守衛只攔「垂直為主」的移動 — 水平手勢（SwipeableRow / 橫滑切 page）、
//       chart 按住查值（位移 < pan 門檻）、sheet 下拉皆不受影響。
// 依賴：SwiftUI + UIKit。無 design-system 依賴，可 drop-in 任何專案。

extension View {
    /// 捲動 tap 列的誤觸雙防線：恢復觸摸延遲 + 垂直位移取消守衛。
    ///
    /// 1. **觸摸延遲**：把所屬 UIScrollView 的 `delaysContentTouches` 恢復為原生 true
    ///    （先延遲 ~150ms 判意圖），治「快速輕滑起手被誤判成點擊」。
    /// 2. **垂直位移取消守衛**（`VerticalTapCancelGuard`）：UIKit pan +
    ///    `cancelsTouchesInView=true` — 垂直為主的移動一旦成立即取消 rows 的 press，
    ///    治「慢速小拖仍 commit 給 Button」；純 tap（位移 < pan 門檻 ~10pt）不受影響。
    ///
    /// **必掛 ScrollView 的內容上** — modifier 靠 superview walk 往上找 UIScrollView，
    /// 掛 ScrollView 本身 = 注入 view 是它的 sibling、walk 永遠落空 → 防線**靜默失效**。
    func restoreTouchDelays() -> some View {
        background(TouchDelayRestorer())
    }
}

private struct TouchDelayRestorer: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        Self.restoreWithRetry(from: v, attempt: 0)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        Self.restoreWithRetry(from: uiView, attempt: 0)
    }

    /// sheet 呈現初期 superview 鏈可能還沒接上 UIScrollView（presentation 動畫中），
    /// 首次 walk 落空就以 50ms 間隔重試（上限 10 次）。靜態頁沒有後續 state 變更觸發
    /// updateUIView 自癒，一次性 walk 落空 = 掛載默默失效，必須靠重試補上。
    /// 找到即冪等設定，重複排程無害。
    private static func restoreWithRetry(from view: UIView, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.05)) { [weak view] in
            guard let view else { return }
            if restore(from: view) { return }
            if attempt < 10 { restoreWithRetry(from: view, attempt: attempt + 1) }
        }
    }

    /// 往上 superview 找第一個 UIScrollView（內容的祖先）：恢復觸摸延遲 + 掛取消守衛（冪等）。
    @discardableResult
    private static func restore(from view: UIView) -> Bool {
        var node = view.superview
        while let current = node {
            if let scrollView = current as? UIScrollView {
                scrollView.delaysContentTouches = true
                if !(scrollView.gestureRecognizers ?? []).contains(where: { $0 is VerticalTapCancelGuard }) {
                    scrollView.addGestureRecognizer(VerticalTapCancelGuard())
                }
                return true
            }
            node = current.superview
        }
        return false
    }
}

/// 垂直捲動位移的「取消 row press」守衛 — 純 observer，不驅動任何行為：
/// begin 的唯一副作用是 `cancelsTouchesInView` 取消 hit-test view（SwiftUI hosting）的
/// touch，讓已按下的 Button / onTapGesture 放棄觸發。
/// - 只在「垂直為主」移動時 begin；水平留給 SwipeableRow / 抽屜等手勢（分軸互不干擾）
/// - `shouldRecognizeSimultaneouslyWith` 一律 true：不搶不擋 scroll pan / sheet 下拉 / 任何手勢
/// - scrollview `isScrollEnabled=false`（如拖曳排序中 scrollDisabled）時不 begin
/// - 若 app 有「長按拖曳排序」類手勢需要豁免守衛，在 gestureRecognizerShouldBegin
///   開頭加你的旗標檢查（例：`if MyReorderCoordination.active { return false }`）
private final class VerticalTapCancelGuard: UIPanGestureRecognizer, UIGestureRecognizerDelegate {
    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = true
        delegate = self
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let p = g as? UIPanGestureRecognizer, let view = p.view else { return false }
        if let sv = view as? UIScrollView, !sv.isScrollEnabled { return false }
        let v = p.velocity(in: view)
        let useVelocity = abs(v.x) + abs(v.y) > 1
        let dx = useVelocity ? v.x : p.translation(in: view).x
        let dy = useVelocity ? v.y : p.translation(in: view).y
        return abs(dy) > abs(dx)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
