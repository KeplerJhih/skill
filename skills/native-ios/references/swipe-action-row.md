# ScrollView 內的左滑動作列：為什麼自訂、以及五個修過的坑

> Drop-in 源檔：`examples/SwipeActionRow.swift`（零 design-system 依賴）。
> 適用：`List` 之外的自繪列（ScrollView + VStack 卡片風格），`.swipeActions` 在那裡完全無效。
> 若能接受 `List` 的樣式介入，優先用系統 `.swipeActions`，不需要本文。

## 版面骨架：actions 掛 `background(alignment:)`，不要 ZStack sibling

```swift
content
    .offset(x: offset)
    .background(alignment: .trailing) { if shouldReveal { actions } }
```

三個好處，都是踩過才知道：

1. **免量高**。background 拿到的 proposal 就是 content 的實際大小，`maxHeight: .infinity`
   剛好填滿列高。ZStack 版要用 GeometryReader 量高再寫 `@State`，每列實體化都付
   「量高 → 寫 state → 第二輪 body + layout」雙 pass，一次展開 N 列時卡頓很明顯。
2. **z 序天生正確**。`.offset` 是 geometry effect，layout frame 不動 → background 停在原位，
   content 滑開自然露出，不必調 zIndex。
3. **零常駐成本**。`if shouldReveal` 條件建構，按鈕子樹只在開始滑動時才 build。
   用 `opacity(0)` 隱藏的版本會讓 N 列 × 2~3 顆按鈕全部白建。

## 坑 1：`minimumDistance` 不能低於 UIScrollView pan 的閾值

pan 大約 10pt 啟動。曾把門檻降到 12pt 想讓水平起手更跟手，結果**垂直** touch 也被本手勢
圈住，ScrollView 收不到 → sheet 的系統下拉收合（走 scroll pan 鏈路）整個失效，真機才發現。

**18pt** 是實測的甜蜜點：垂直拖曳在死區內先被 scroll pan 認領，水平又比 28pt 靈敏。

## 坑 2：方向判定只在第一幀做，之後不准重算

```swift
if dragLock == .undecided {
    if abs(dx) > abs(dy) * 2.2 { dragLock = .horizontal }
    else { dragLock = .releasedToScroll; /* 順手收合 */ return }
}
```

每幀重算的話，使用者拉開後手指自然往下飄（滑到隔壁列的高度）就被判成垂直、整列回彈。
`2.2` 倍是「明顯水平」的門檻，比 1.0 更能把斜向起手讓給捲動。

垂直分支要**順手收合已開的列**：不收的話，開著的 row 手勢狀態會卡住後續下拉，sheet 拖不動。

## 坑 3：`.buttonStyle(.plain)` 不可省（iOS 26）

沒指定 style 時，iOS 26 會把動作鈕畫成半透明玻璃膠囊，蓋掉自訂的實色底——刪除鈕變成
淺粉色、編輯鈕變成一塊灰方塊。加 `.plain` 才會照自己的 `background` 渲染。

## 坑 4：常駐 `.shadow` 讓滑動掉幀

給列加「浮起」效果時，直覺是掛 `.shadow(color: isDragging ? … : .clear, radius: isDragging ? 8 : 0)`。
即使半徑 0、顏色透明，SwiftUI 仍會讓**每一列**走離屏渲染；列內 offset 每幀變動時就明顯卡。

改用 `overlay(Color.primary.opacity(0.05 * progress))` + `clipShape(圓角 × progress)` 表達浮起，
視覺接近、成本為零。

## 坑 5：收合淡出期間的 ghost tap

按鈕改成條件建構後，close 的 removal transition（約 0.3s）期間子樹**仍可被 hit-test**
（removal 中的子樹以最後渲染值凍結，加 `allowsHitTesting` 也擋不住）。第二次 tap 會重複觸發，
對非冪等動作（toggle 類）會直接歸零。

每個動作進入點加 `guard isOpen else { return }`：第一次 tap 已把 isOpen 設 false，等價即時阻斷。

## 點列的動作由元件代管

```swift
.onTapGesture { isOpen ? close() : onTapContent?() }
```

**呼叫端不要在 content 內自帶 `NavigationLink` / `Button`**，會跟收合手勢雙發：
使用者想關掉 actions，結果收合的同時推進了下一頁。

用程式化導航（`navigationDestination(item:)`）配 `onTapContent` 回呼取代 NavigationLink。

## 多列協調：捲動即收合

只靠列自己的手勢，「在**別的列**上往下捲」收不到任何訊號 → 開著的列一直開著，
使用者只能點空白處關掉（真實回報過的抱怨）。

容器持一個 `SwipeRowCoordinator` 放進 environment：

```swift
@State private var swipeCoordinator = SwipeRowCoordinator()
...
ScrollView { … }
    .environment(swipeCoordinator)
    .onScrollPhaseChange { _, new in if new != .idle { swipeCoordinator.scrollDidMove() } }
```

列在開啟時登記 `openRowID`、`onChange` 觀察到不是自己就收合，順帶得到「同時只開一列」。
`draggingRowID` 是必要的例外：水平拖曳中若捲動階段剛好有變化（斜向起手），不該把正在拖的
那列收掉。

## 與長按拖曳排序同時存在時

兩者會搶同一根手指，見 `references/uikit-drag-reorder.md` 的「整列長按變體」一節：
長按 recognizer 要用 `shouldBeRequiredToFailBy` 讓 SwiftUI 的 tap/drag 等它失敗，
移動超過 `allowableMovement` 時長按失敗、左滑照常接手。

## 驗證注意

**模擬器的合成左滑（`idb ui_swipe`）驅動不了 SwiftUI 的 `DragGesture`**，
不論 duration 0.25~1.2s、delta 2~4，一律被當成點擊。左滑行為只能真機驗；
模擬器能驗的只有點擊導航、選單、彈窗與垂直捲動（走 UIScrollView 原生 pan，不受影響）。
