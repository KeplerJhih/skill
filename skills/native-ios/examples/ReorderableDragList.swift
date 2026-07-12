import SwiftUI
import UIKit

// MARK: - ReorderableDragList — 自製長按拖曳排序列表（UIKit 手勢橋接版）
//
// 零 design-system 依賴，可 drop-in 任何 SwiftUI 專案。
// 為什麼不用 SwiftUI LongPress+Drag sequence（會「一直抖」的兩個結構性根因）、
// UIKit 橋接四要點、參數心得與真機驗證清單 → references/uikit-drag-reorder.md。
//
// 用法：
//   ReorderableDragList(items: $configs, rowHeight: 44, isReordering: $dragging) { idx, binding in
//       MyRow(item: binding.wrappedValue)   // 排序列建議純顯示、固定高度 = rowHeight
//   }
//   外層 ScrollView 掛 .scrollDisabled(dragging) 作第二道保險（第一道是 recognizer
//   began 同步關 isScrollEnabled，不依賴 SwiftUI render 時序）。
//
// 若專案有 touch-cancel 類守衛（cancelsTouchesInView 的 UIPanGestureRecognizer），
// 讓它的 shouldBegin 查 DragReorderCoordination.active 豁免。

struct ReorderableDragList<Item: Identifiable & Equatable, Row: View>: View {
    @Binding var items: [Item]
    /// 必須精確等於 row 視覺高度（排序列鎖 .frame(height:)，勿讓字體縮放撐高），
    /// 否則 swap 邊界計算錯位。
    let rowHeight: CGFloat
    var rowSpacing: CGFloat = 6
    /// 把手顏色（原專案用 theme token，drop-in 版參數化）。
    var handleColor: Color = .secondary
    /// 通知 parent 拖曳中 — 供外層 .scrollDisabled 第二道保險。
    @Binding var isReordering: Bool
    let row: (Int, Binding<Item>) -> Row

    /// 拖曳工作副本：began 拷貝、拖曳中 swap 都在這、ended 一次 commit 回 binding。
    /// 拖曳中不碰 binding → 不觸發 caller 的 @Published didSet persist / 整頁 re-render。
    @State private var workingItems: [Item]? = nil
    @State private var draggingID: Item.ID? = nil
    @State private var dragOffset: CGFloat = 0
    /// 拖曳起點 index（從啟動到結束不變 — swap 後更新會累積錯位「兩格兩格切換」）。
    @State private var dragStartIdx: Int? = nil

    private var displayItems: [Item] { workingItems ?? items }

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(Array(displayItems.enumerated()), id: \.element.id) { idx, item in
                rowContainer(idx: idx, item: item)
            }
        }
    }

    @ViewBuilder
    private func rowContainer(idx: Int, item: Item) -> some View {
        let isDragging = draggingID == item.id
        // dragging row 視覺位置 = startIdx 位置 + dragOffset（跟手指 1:1）。
        // dragOffset 來自 window 座標（recognizer 回報），不受 row 排位移動污染。
        let stride = rowHeight + rowSpacing
        let visualOffset: CGFloat = {
            guard isDragging, let start = dragStartIdx else { return 0 }
            return dragOffset - CGFloat(idx - start) * stride
        }()
        HStack(spacing: 6) {
            handleView(item: item)
            row(idx, rowBinding(id: item.id, fallbackIdx: idx))
        }
        .scaleEffect(isDragging ? 1.02 : 1)
        .shadow(color: isDragging ? Color.black.opacity(0.18) : .clear,
                radius: isDragging ? 8 : 0, y: 4)
        .offset(y: visualOffset)
        .zIndex(isDragging ? 1 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: draggingID)
        // dragging row 全程禁 implicit animation：讓位列維持 spring（下方 withAnimation
        // 驅動），被拖列的 offset / 排位變化 instant 落地跟手。
        .transaction { txn in
            if isDragging { txn.animation = nil }
        }
    }

    @ViewBuilder
    private func handleView(item: Item) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 14, weight: .regular))
            .foregroundColor(handleColor)
            .frame(width: 24, height: 44)
            .contentShape(Rectangle())
            .overlay(
                DragHandleRecognizer(
                    onBegan: { beginDrag(item: item) },
                    onMoved: { dy in updateDrag(item: item, dy: dy) },
                    onFinished: { cancelled in endDrag(cancelled: cancelled) }
                )
            )
    }

    /// row binding 以 id 解析（拖曳中 displayItems 順序 ≠ items 順序，
    /// 位置型 $items[idx] 會指錯列）。讀走 displayItems，寫同步進兩者。
    private func rowBinding(id: Item.ID, fallbackIdx: Int) -> Binding<Item> {
        Binding(
            get: {
                if let w = workingItems, let i = w.firstIndex(where: { $0.id == id }) { return w[i] }
                if let i = items.firstIndex(where: { $0.id == id }) { return items[i] }
                return items[min(fallbackIdx, items.count - 1)]
            },
            set: { newVal in
                if let i = items.firstIndex(where: { $0.id == id }) { items[i] = newVal }
                if workingItems != nil,
                   let i = workingItems!.firstIndex(where: { $0.id == id }) {
                    workingItems![i] = newVal
                }
            }
        )
    }

    // MARK: - Drag lifecycle（UIKit recognizer 回呼，全程主執行緒）

    private func beginDrag(item: Item) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        workingItems = items
        dragStartIdx = i
        draggingID = item.id
        dragOffset = 0
        // UIKit 事件流內寫 SwiftUI state 安全：recognizer 狀態在 Coordinator，
        // 不隨 re-render 重置。
        isReordering = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func updateDrag(item: Item, dy: CGFloat) {
        guard draggingID != nil else { return }
        dragOffset = dy
        guard var working = workingItems, let start = dragStartIdx,
              let currentIdx = working.firstIndex(where: { $0.id == item.id }) else { return }
        // Hysteresis 0.6 格（非 round 0.5）：解觸控 ±1pt 雜訊在半格邊界反覆 swap-unswap。
        let stride = rowHeight + rowSpacing
        let raw = dy / stride
        let lastDelta = currentIdx - start
        let diff = raw - CGFloat(lastDelta)
        let threshold: CGFloat = 0.6
        let increment: Int
        if diff >= threshold {
            increment = Int((diff - threshold) / 1.0) + 1
        } else if diff <= -threshold {
            increment = -(Int((-diff - threshold) / 1.0) + 1)
        } else {
            increment = 0
        }
        let targetIdx = max(0, min(working.count - 1, currentIdx + increment))
        if targetIdx != currentIdx {
            let m = working.remove(at: currentIdx)
            working.insert(m, at: targetIdx)
            // 只重排 workingItems 包 spring（讓位動畫）；dragging row 由 visualOffset
            // 補正 + transaction nil，instant 跟手。
            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                workingItems = working
            }
        }
    }

    private func endDrag(cancelled: Bool) {
        // 正常放手才 commit（一次 persist）；cancelled（來電 / 背景化）丟棄副本，
        // 列表 spring 回原序 — 意外中斷不落半成品排序。
        if !cancelled, let working = workingItems, working != items {
            items = working
        }
        if draggingID != nil {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            draggingID = nil
            dragOffset = 0
            dragStartIdx = nil
            workingItems = nil
        }
        isReordering = false
    }
}

// MARK: - UIKit 長按拖曳 recognizer 橋接

/// 把手上的透明 UIView + UILongPressGestureRecognizer。
/// - 0.35s 成立；醞釀期被 ScrollView pan 搶走 = 默默 fail 改捲動（無視覺副作用），
///   不需要 SwiftUI 版的長 duration 防抖
/// - began 同步關外層 UIScrollView.isScrollEnabled + 翻協調旗標（UIKit 事件流內
///   即時生效，無 SwiftUI render 時序死角）
/// - 位移以 window 為座標系：row 因 swap 移位不影響回報值
private struct DragHandleRecognizer: UIViewRepresentable {
    let onBegan: () -> Void
    let onMoved: (CGFloat) -> Void
    /// cancelled = true：手勢被系統取消（來電 / 背景化），caller 應丟棄而非 commit。
    let onFinished: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        let lp = UILongPressGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.handle(_:)))
        lp.minimumPressDuration = 0.35
        lp.allowableMovement = 12
        v.addGestureRecognizer(lp)
        context.coordinator.callbacks = (onBegan, onMoved, onFinished)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // row body 重評估會重建本 struct；UIView / Coordinator 由 SwiftUI 保留
        // （view identity 不變），只需刷新 closure 捕獲。進行中的手勢不受影響。
        context.coordinator.callbacks = (onBegan, onMoved, onFinished)
    }

    final class Coordinator: NSObject {
        var callbacks: (began: () -> Void, moved: (CGFloat) -> Void, finished: (Bool) -> Void)?
        private var startY: CGFloat = 0
        private weak var scrollView: UIScrollView?

        @objc func handle(_ g: UILongPressGestureRecognizer) {
            switch g.state {
            case .began:
                startY = g.location(in: g.view?.window).y
                // 每次拖曳即時 walk（不快取跨次結果）：回前景後祖先鏈可能重排。
                scrollView = Self.findScrollView(from: g.view)
                scrollView?.isScrollEnabled = false
                DragReorderCoordination.active = true
                callbacks?.began()
            case .changed:
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
            scrollView = nil
            DragReorderCoordination.active = false
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

/// 跨元件協調旗標（**非 SwiftUI state** — 讀寫不觸發 render）。
/// 專案若有 touch-cancel 類守衛（cancelsTouchesInView 的 pan recognizer），
/// 讓其 shouldBegin 查此旗標豁免拖曳。由 recognizer 的 began / ended / cancelled
/// 對稱維護 — 系統取消也走 cancelled，不會卡 true。
enum DragReorderCoordination {
    static var active = false
}
