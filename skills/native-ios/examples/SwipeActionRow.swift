import SwiftUI
import UIKit

// MARK: - SwipeActionRow — ScrollView 內的左滑動作列（仿 iPhone 備忘錄）
//
// 零 design-system 依賴，可 drop-in 任何 SwiftUI 專案。
// 用於 `List` 之外的自繪列（ScrollView + VStack 卡片風格），`.swipeActions` 在那裡無效。
// 設計要點與踩坑推導 → references/swipe-action-row.md
//
// 用法：
//   SwipeActionRow(
//       deleteTitle: "刪除",
//       confirmTitle: "刪除「\(item.name)」？",
//       onEdit: { editing = item },            // nil = 不提供編輯
//       onDelete: { delete(item) },
//       onTapContent: { push(item) }           // 開著時 tap 只收合，不觸發
//   ) {
//       MyRow(item: item)                      // 內容勿再自帶 NavigationLink / Button
//   }
//
// 多列協調（同時只開一列、捲動即收合）：容器建一個 SwipeRowCoordinator 放進 environment，
// 並在 ScrollView 掛 .onScrollPhaseChange，見檔案末尾。
//
// 手勢層依賴同目錄 `HorizontalPanGesture.swift`（iOS 18+ UIKit pan：只在水平為主時 begin，垂直手勢
// 完全讓給 ScrollView / sheet 下拉收合；17 退 SwiftUI DragGesture）。

struct SwipeActionRow<Content: View>: View {
    // 動作文案（呼叫端負責在地化；元件本身不依賴 loc）
    var editTitle: String = "Edit"
    var deleteTitle: String = "Delete"
    /// 刪除確認的 alert 標題；空字串 = 不確認，直接執行。
    var confirmTitle: String = ""
    var deleteIcon: String = "trash"
    var editIcon: String = "pencil"
    // 配色（呼叫端傳 theme token）
    var editTint: Color = .accentColor
    var editForeground: Color = .white
    var deleteTint: Color = .red
    var cancelTitle: String = "Cancel"

    /// nil = 不提供編輯動作。
    var onEdit: (() -> Void)? = nil
    var onDelete: () -> Void
    /// 收合狀態下點 content 的動作（推頁 / 開編輯）。**由本元件代管**而非呼叫端自掛
    /// `.onTapGesture`：actions 開著時 tap 只收合、不觸發動作（對齊系統 List）；
    /// 呼叫端自掛會跟收合手勢雙發（收合的同時誤開下一頁）。
    var onTapContent: (() -> Void)? = nil
    @ViewBuilder var content: Content

    @Environment(SwipeRowCoordinator.self) private var coordinator: SwipeRowCoordinator?
    @State private var rowID = UUID()
    @State private var dragOffset: CGFloat = 0
    @State private var isOpen = false
    /// 本次拖曳方向的鎖定：第一幀決定後不再重評估，避免手指途中垂直偏移被當成取消而回彈。
    @State private var dragLock: DragLock = .undecided
    /// 拉到底已武裝：鬆手直接執行刪除（或進確認）；進出各震一次。
    @State private var fullSwipeArmed = false
    @State private var confirming = false

    private enum DragLock { case undecided, horizontal, releasedToScroll }

    private let capsuleWidth: CGFloat = 66
    private let edgeMargin: CGFloat = 16
    private let gap: CGFloat = 8
    private let spring = Animation.spring(response: 0.3, dampingFraction: 0.85)

    private var revealWidth: CGFloat { CGFloat(onEdit == nil ? 1 : 2) * (capsuleWidth + gap) + edgeMargin }
    private var offset: CGFloat { (isOpen ? -revealWidth : 0) + dragOffset }
    private var revealProgress: CGFloat { min(1, max(0, -offset / revealWidth)) }
    private var fullSwipeThreshold: CGFloat { revealWidth * 2.2 }
    /// 拉超過 open 位置後刪除膠囊連續拉長；未超過回 nil＝標準寬。
    private var trailingStretch: CGFloat? { -offset > revealWidth ? capsuleWidth + (-offset - revealWidth) : nil }
    /// 按鈕子樹只在開始滑動時才建構，列實體化時零成本（用 opacity 0 隱藏會讓 N 列白建）。
    private var shouldReveal: Bool { isOpen || dragOffset < -2 }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            // 浮起：滑開時整列微暗＋長出圓角，像從卡片中抽出一張獨立卡。
            // 不掛 .shadow：常駐 shadow（即使半徑 0）會逼每列走離屏渲染，滑動時掉幀。
            .overlay(Color.primary.opacity(0.05 * revealProgress).allowsHitTesting(false))
            .clipShape(RoundedRectangle(cornerRadius: 13 * revealProgress, style: .continuous))
            // .offset 是 geometry effect，layout frame 不動 → 下面的 background 停在原位，
            // content 滑開自然露出，z 序也天然在 content 之下（免 ZStack + GeometryReader 量高）。
            .offset(x: offset)
            .modifier(HorizontalPanBridge(
                minimumDistance: 18,
                onBegan: { beginHorizontal() },
                onChanged: { dx, dy in
                    if dragLock == .undecided { legacyDecideAxis(dx: dx, dy: dy) }   // 17 路徑才會進來
                    panChanged(dx: dx)
                },
                onEnded: { _, predictedExtra in panEnded(predictedExtra: predictedExtra) }
            ))
            // 已開的列碰到垂直捲動 → 收合（對齊系統 List）。UIKit 路徑下垂直手勢不會進本元件，
            // 另掛一個只在「已開」時才生效的旁聽 drag；不收的話開著的列手勢狀態會卡住後續下拉。
            .simultaneousGesture(closeOnVerticalScroll, including: isOpen ? .all : .none)
            .onTapGesture { isOpen ? close() : onTapContent?() }
            .background(alignment: .trailing) {
                if shouldReveal {
                    HStack(spacing: gap) {
                        if let onEdit, trailingStretch == nil {          // 拉到底時讓位給刪除鈕
                            capsuleButton(icon: editIcon, title: editTitle, bg: editTint, fg: editForeground) {
                                guard isOpen else { return }            // 防收合淡出期間的 ghost tap
                                close()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { onEdit() }
                            }
                        }
                        capsuleButton(icon: deleteIcon, title: deleteTitle, bg: deleteTint,
                                      fg: .white, stretched: trailingStretch) {
                            guard isOpen else { return }
                            triggerDelete()
                        }
                    }
                    .padding(.trailing, edgeMargin)
                    .scaleEffect(0.5 + 0.5 * revealProgress, anchor: .trailing)   // 隨進度擠入
                    .opacity(min(1, revealProgress * 1.6))
                    .frame(width: revealWidth, alignment: .trailing)
                    .frame(maxHeight: .infinity)
                }
            }
            .clipShape(Rectangle())
            // 別列開了、或容器捲動 → 協調者換掉／清空 openRowID → 本列收合。
            .onChange(of: coordinator?.openRowID) { _, current in
                if isOpen, current != rowID { close() }
            }
            .alert(confirmTitle, isPresented: $confirming) {
                Button(cancelTitle, role: .cancel) { close() }
                Button(deleteTitle, role: .destructive) { close(); onDelete() }
            }
    }

    // MARK: 手勢核心（iOS 18+ UIKit pan / iOS 17 SwiftUI DragGesture 共用同一套狀態機）
    //
    // 為什麼換 UIKit：SwiftUI DragGesture 在 ScrollView 內由 SwiftUI 分配所有權，起手橫向分量 ≳ 0.9 倍垂直
    // 就把整條手勢判給列，**被判走的下拉手勢不會回到 ScrollView / sheet 收合**——整頁都是列的 sheet
    // 「下拉很常收不了」。UIKit pan 只在水平為主時 begin，垂直手勢本元件根本不參與。
    // 17 舊路徑門檻 18pt：不可低於 UIScrollView pan 啟動閾值 ~10pt（曾降到 12pt 讓 sheet 下拉整條失效）。

    private func beginHorizontal() {
        dragLock = .horizontal
        coordinator?.draggingRowID = rowID
        if !isOpen { coordinator?.openRowID = nil }   // 開新列＝先收掉別列
    }

    /// 17 舊路徑第一幀決定方向（水平為主才接手；否則釋放給 ScrollView 並收合開著的列）。
    private func legacyDecideAxis(dx: CGFloat, dy: CGFloat) {
        if abs(dx) > abs(dy) {
            beginHorizontal()
        } else {
            dragLock = .releasedToScroll
            if dragOffset != 0 { dragOffset = 0 }
            if isOpen { withAnimation(spring) { isOpen = false } }
        }
    }

    private var closeOnVerticalScroll: some Gesture {
        DragGesture(minimumDistance: 18).onChanged { v in
            if abs(v.translation.height) > abs(v.translation.width), isOpen, dragLock != .horizontal { close() }
        }
    }

    private func panChanged(dx: CGFloat) {
        guard dragLock == .horizontal else { return }
        dragOffset = isOpen ? min(dx, revealWidth)    // 往右最多收到 0；往左可繼續拉深
                            : (dx < 0 ? dx : 0)       // 只接左滑；允許一路拉到底
        let nowArmed = -offset > fullSwipeThreshold
        if nowArmed != fullSwipeArmed {
            fullSwipeArmed = nowArmed
            UIImpactFeedbackGenerator(style: nowArmed ? .medium : .light).impactOccurred()
        }
    }

    /// - predictedExtra：鬆手後預期還會再滑的距離（SwiftUI = predictedEndTranslation − translation；
    ///   UIKit = 速度 × 0.12s 近似），flick 判定門檻 220。
    private func panEnded(predictedExtra: CGFloat) {
        defer {
            dragLock = .undecided
            coordinator?.draggingRowID = nil
        }
        guard dragLock == .horizontal else {
            withAnimation(spring) { dragOffset = 0 }
            return
        }
        if fullSwipeArmed {                           // 拉到底鬆手：收合並直接執行
            fullSwipeArmed = false
            withAnimation(spring) { isOpen = false; dragOffset = 0 }
            triggerDelete()
            return
        }
        let velocity = predictedExtra
        let current = offset
        withAnimation(spring) {
            if isOpen {
                let closeByDistance = current > -revealWidth * 0.4
                let closeByFlick = velocity > 220 && current > -revealWidth * 0.8
                if closeByDistance || closeByFlick { isOpen = false }
            } else {
                let openByDistance = current < -revealWidth * 0.6
                let openByFlick = velocity < -220 && current < -capsuleWidth * 0.4
                if openByDistance || openByFlick {
                    isOpen = true
                    coordinator?.openRowID = rowID
                }
            }
            dragOffset = 0
        }
    }

    private func triggerDelete() {
        if confirmTitle.isEmpty { close(); onDelete() } else { confirming = true }
    }

    private func close() {
        withAnimation(spring) {
            isOpen = false
            dragOffset = 0
        }
        if coordinator?.openRowID == rowID { coordinator?.openRowID = nil }
    }

    /// 扁膠囊只含圖示、文字在膠囊下方；`stretched` 為拉到底時的拉長寬。
    /// `.buttonStyle(.plain)` 不可省：iOS 26 的預設 button style 會把它畫成半透明玻璃膠囊，
    /// 蓋掉這裡的實色底。
    private func capsuleButton(icon: String, title: String, bg: Color, fg: Color,
                               stretched: CGFloat? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(fg)
                    .frame(width: stretched ?? capsuleWidth, height: 38)
                    .background(Capsule().fill(bg))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: stretched ?? capsuleWidth)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 多列協調者（同時只開一列、捲動即收合）

/// 容器持有一份放進 `.environment(...)`，並在 ScrollView 掛：
///   .onScrollPhaseChange { _, new in if new != .idle { coordinator.scrollDidMove() } }
/// 沒放協調者的單列場景，SwipeActionRow 會自動退回單列行為。
///
/// 為什麼需要它：只靠列自己的手勢，「在**別的列**上往下捲」收不到任何訊號，
/// 開著的列會一直開著，使用者只能點空白處關掉。
@Observable
final class SwipeRowCoordinator {
    /// 目前開著的列；nil＝都收合。列讀它決定要不要把自己收掉。
    var openRowID: UUID?
    /// 正在水平拖曳中的列：拖曳期間若捲動階段有變化（斜向起手），不該把它收掉。
    var draggingRowID: UUID?

    func scrollDidMove() {
        if draggingRowID == nil { openRowID = nil }
    }
}
