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

## 手勢所有權：橫向手勢一律走 UIKit pan 橋接（取代坑 1、坑 2）

**根因**：SwiftUI `DragGesture` 放在 ScrollView 內時，由 SwiftUI 在起手約 10pt 依方向分配所有權——
橫向分量只要 ≳ 0.9 倍垂直，整條手勢就判給列；**被判走的手勢不會回到 ScrollView，也到不了 sheet 的
下拉收合**。兩個實際症狀：

1. 列自己的判定若比 SwiftUI 嚴（舊寫法 `|dx| > 2.2·|dy|` 才鎖橫向），42°–66° 的斜向手勢落入死區：
   SwiftUI 已判給列、列又嫌不夠橫而放掉 → 既不捲也不開，拇指斜著滑長清單「很難滑」
   （模擬器實測同角度在無列的標題上捲 20pt、在列上捲 0pt）。
2. 就算列的判定對齊到 `|dx| > |dy|`，起手偏橫一點的下拉仍被列吃掉 → 整頁都是列的 sheet
   （備忘錄 / 歷史）往下拉「很常收不了」。

**正解**：`examples/HorizontalPanGesture.swift`（iOS 18 `UIGestureRecognizerRepresentable`）——
`gestureRecognizerShouldBegin` 只在水平為主時 begin，垂直手勢本元件根本不參與；與 UIScrollView pan
不並存並要求它等本 pan 失敗（`shouldBeRequiredToFailBy`），仲裁順序確定。`HorizontalPanBridge` 在
17 退回 SwiftUI DragGesture（18pt 門檻——不可低於 UIScrollView pan ~10pt，曾降到 12pt 讓 sheet 下拉整條失效）。
改後：45° 與偏直斜滑都會捲、左滑開鈕 / full swipe 正常、sheet 從列上下拉可收。

兩個連帶：
- **已開的列要在垂直捲動時收合**（對齊系統 List）。UIKit 路徑下垂直手勢不進元件，改掛一個只在
  `isOpen` 時才生效的旁聽 `simultaneousGesture`（`including: isOpen ? .all : .none`）。
- UIKit 的 translation 不含起手 ~10pt 滯後：真機連續取樣差異可忽略；模擬器 10pt 步進會少 10–20pt，
  測 full swipe 要多拉一點。

**通則**：任何自訂橫向手勢（左滑列、可拖曳的 pill 選擇器…）一律套這個橋接；不要再用 SwiftUI
DragGesture 猜 SwiftUI 的所有權邊界。方向判定只在 begin 時做一次，之後不重算（每幀重算會因手指下飄而誤判回彈）。

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

模擬器 `idb ui swipe` **驅動得了** UIKit pan 與 SwiftUI DragGesture（18pt 門檻可開列、可拉深觸發 full swipe），
也驅動得了 sheet 的系統下拉收合（從 ScrollView 內容區往下拉）——先前「合成左滑一律被當點擊」「拉不動 sheet」
的紀錄分別是舊 28pt 門檻與全域關橫向回彈（見 `scroll-bounce-and-width.md`）造成的誤判。驗法：固定角度 swipe 前後
比對 AX 元素 y（捲動量）／截圖看按鈕；震動與拉長的體感、玻璃渲染仍要真機。
