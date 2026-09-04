import SwiftUI
import UIKit

// MARK: - LongPressRowReorderList — 長按「整列」拖曳排序（無把手版）
//
// 零 design-system 依賴，可 drop-in 任何 SwiftUI 專案。
// 與 `ReorderableDragList.swift` 的差異：那份用 ☰ 把手、recognizer 掛在把手上的透明 view；
// 這份**沒有把手**，長按列上任何位置都能抓起 → recognizer 必須掛到**外層 UIScrollView**。
// 根因與四個新踩的坑 → references/uikit-drag-reorder.md「整列長按變體」一節。
//
// 用法：
//   LongPressRowReorderList(items: categories, rowHeight: 60,
//                           onReorder: { persistOrder($0) }) { item in
//       MyRow(item: item)          // 列高必須等於 rowHeight
//   }
//
// ⚠️ 與 `.contextMenu` 互斥（長按會先成立並取消 touch）——用本元件的列請改用左滑動作。

struct LongPressRowReorderList<Item: Identifiable & Equatable, Row: View>: View {
    let items: [Item]
    /// 必須精確等於列的視覺高度（列鎖 `.frame(height:)`，勿讓字體縮放撐高），否則 swap 邊界算錯。
    let rowHeight: CGFloat
    /// 放手後的新順序（只在順序真的變了才呼叫）；呼叫端負責持久化。
    let onReorder: ([Item]) -> Void
    @ViewBuilder let row: (Item) -> Row

    /// 拖曳工作副本：began 拷貝、拖曳中 swap 都在這、ended 才 commit；
    /// commit 後保留到外部 items 追上（資料層重新排序）才清掉，避免閃回舊順序。
    @State private var working: [Item]? = nil
    @State private var draggingID: Item.ID? = nil
    /// 拖曳起點 index（從啟動到結束不變——swap 後更新會累積錯位「兩格兩格切換」）。
    @State private var dragStartIdx: Int? = nil
    @State private var dragOffset: CGFloat = 0

    private var display: [Item] { working ?? items }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(display.enumerated()), id: \.element.id) { idx, item in
                rowContainer(idx: idx, item: item)
            }
        }
        .background(
            ReorderRecognizerHost(
                rowHeight: rowHeight, count: items.count,
                onBegan: { beginDrag(at: $0) },
                onMoved: { updateDrag(dy: $0) },
                onFinished: { endDrag(cancelled: $0) })
        )
        .onChange(of: items) { _, new in
            // commit 後外部順序追上工作副本 → 放掉副本，回到單一真相。
            if draggingID == nil, let w = working, w == new { working = nil }
        }
    }

    @ViewBuilder
    private func rowContainer(idx: Int, item: Item) -> some View {
        let isDragging = draggingID == item.id
        // 被拖列的視覺位置＝起點格＋手指位移；dragOffset 來自 window 座標，不受讓位動畫污染。
        let visualOffset: CGFloat = {
            guard isDragging, let start = dragStartIdx else { return 0 }
            return dragOffset - CGFloat(idx - start) * rowHeight
        }()
        row(item)
            .frame(height: rowHeight)
            // 浮起只用縮放＋zIndex，不掛 .shadow：常駐 shadow（即使半徑 0）會逼每列走離屏渲染，
            // 列內有其他每幀變動的 offset（例如同一列同時支援左滑）時就明顯掉幀。
            .scaleEffect(isDragging ? 1.03 : 1)
            .offset(y: visualOffset)
            .zIndex(isDragging ? 1 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: draggingID)
            // 被拖列禁 implicit animation（instant 跟手）；讓位列由 updateDrag 的 withAnimation 驅動。
            .transaction { if isDragging { $0.animation = nil } }
    }

    // MARK: - Drag lifecycle（UIKit recognizer 回呼，全程主執行緒）

    private func beginDrag(at idx: Int) {
        guard idx >= 0, idx < items.count else { return }
        working = items
        dragStartIdx = idx
        draggingID = items[idx].id
        dragOffset = 0
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func updateDrag(dy: CGFloat) {
        guard let id = draggingID, var w = working, let start = dragStartIdx,
              let current = w.firstIndex(where: { $0.id == id }) else { return }
        dragOffset = dy
        // Hysteresis 0.6 格（非 round 0.5）：解觸控 ±1pt 雜訊在半格邊界反覆 swap-unswap。
        let raw = dy / rowHeight
        let diff = raw - CGFloat(current - start)
        let threshold: CGFloat = 0.6
        let increment: Int
        if diff >= threshold { increment = Int(diff - threshold) + 1 }
        else if diff <= -threshold { increment = -(Int(-diff - threshold) + 1) }
        else { increment = 0 }
        let target = max(0, min(w.count - 1, current + increment))
        if target != current {
            let moved = w.remove(at: current)
            w.insert(moved, at: target)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { working = w }
        }
    }

    private func endDrag(cancelled: Bool) {
        let committed = !cancelled && working.map { $0 != items } == true
        if committed, let w = working { onReorder(w) }
        if draggingID != nil { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            draggingID = nil
            dragOffset = 0
            dragStartIdx = nil
            if !committed { working = nil }   // 取消／沒動：丟棄副本彈回原序
        }
    }
}

// MARK: - UIKit 長按 recognizer（掛在外層 UIScrollView）

/// 零尺寸干擾的 background view：不參與 hit-test，只負責在進出視窗時把長按 recognizer
/// 掛到／卸下外層 UIScrollView，並提供列表座標系（location → 列 index）。
private struct ReorderRecognizerHost: UIViewRepresentable {
    let rowHeight: CGFloat
    let count: Int
    let onBegan: (Int) -> Void
    let onMoved: (CGFloat) -> Void
    /// cancelled = true：被系統取消（來電／背景化／離開畫面），caller 應丟棄而非 commit。
    let onFinished: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> HostView {
        let v = HostView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false    // 不參與 hit-test；recognizer 在祖先 scroll view 上
        v.coordinator = context.coordinator
        context.coordinator.host = v
        sync(context.coordinator)
        return v
    }

    func updateUIView(_ uiView: HostView, context: Context) { sync(context.coordinator) }

    static func dismantleUIView(_ uiView: HostView, coordinator: Coordinator) { coordinator.detach() }

    private func sync(_ c: Coordinator) {
        c.rowHeight = rowHeight
        c.count = count
        c.callbacks = (onBegan, onMoved, onFinished)
    }

    final class HostView: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { coordinator?.attach(from: self) } else { coordinator?.detach() }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var callbacks: (began: (Int) -> Void, moved: (CGFloat) -> Void, finished: (Bool) -> Void)?
        var rowHeight: CGFloat = 0
        var count = 0
        weak var host: UIView?

        private weak var scrollView: UIScrollView?
        private var recognizer: UILongPressGestureRecognizer?
        private var startY: CGFloat = 0
        private var dragging = false

        func attach(from view: UIView) {
            guard recognizer == nil, let sv = Self.findScrollView(from: view) else { return }
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(handle(_:)))
            // 0.45s / 8pt：左滑起手稍慢也能在長按成立前就因移動而讓長按失敗，交還給列的左滑；
            // 醞釀期被捲動 pan 搶走＝默默 fail，無視覺副作用。
            lp.minimumPressDuration = 0.45
            lp.allowableMovement = 8
            lp.delegate = self
            sv.addGestureRecognizer(lp)
            recognizer = lp
            scrollView = sv
        }

        func detach() {
            if let lp = recognizer, let sv = scrollView { sv.removeGestureRecognizer(lp) }
            recognizer = nil
            if dragging { finish(cancelled: true) }
            scrollView?.isScrollEnabled = true
            scrollView = nil
        }

        /// 只在列表範圍內才成立：頁面其他區域（分段控制、別的清單）不受影響。
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let host else { return false }
            return host.bounds.contains(g.location(in: host))
        }

        /// **關鍵**：讓同一根手指上的其他 recognizer（SwiftUI 的 tap／drag）等本長按**失敗**後才成立。
        /// `cancelsTouchesInView` 只取消 view 的 touch，管不到 SwiftUI 自己的手勢 recognizer——
        /// 沒有這條，長按成立後放手仍會觸發列的點擊（推進下一頁）。
        /// 點一下＝放手時長按失敗 → tap 照常；左滑＝移動超過 allowableMovement 長按失敗 → drag 照常。
        /// 捲動的 pan 例外，維持即時響應。
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            if let sv = scrollView, other === sv.panGestureRecognizer { return false }
            return true
        }

        @objc func handle(_ g: UILongPressGestureRecognizer) {
            switch g.state {
            case .began:
                guard let host, rowHeight > 0 else { return }
                let idx = Int(g.location(in: host).y / rowHeight)
                guard idx >= 0, idx < count else { return }
                startY = g.location(in: g.view?.window).y
                dragging = true
                scrollView?.isScrollEnabled = false   // UIKit 事件流內即時生效，不等 SwiftUI render
                callbacks?.began(idx)
            case .changed:
                guard dragging else { return }
                callbacks?.moved(g.location(in: g.view?.window).y - startY)
            case .ended:
                finish(cancelled: false)
            case .cancelled, .failed:
                finish(cancelled: true)
            default:
                break
            }
        }

        private func finish(cancelled: Bool) {
            scrollView?.isScrollEnabled = true
            guard dragging else { return }
            dragging = false
            callbacks?.finished(cancelled)
        }

        private static func findScrollView(from view: UIView?) -> UIScrollView? {
            var node = view?.superview
            while let current = node {
                if let sv = current as? UIScrollView { return sv }
                node = current.superview
            }
            return nil
        }
    }
}
