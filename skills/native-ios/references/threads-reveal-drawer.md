# Threads 式 Reveal 側選單（主頁滑開、選單固定在主頁底下）

> **觸發場景**：「像 Threads / 脆一樣的側選單」「主頁滑開露出選單」「選單在主頁底下」
> 「reveal / push drawer」「左右滑動整頁切選單」。
> 本文是實戰定案 + 血淚踩坑（每條都真實發生過），照抄可避開十餘輪 build 的試錯。

## 視覺規格（對齊 Threads）

- 選單 = **全螢幕頁面**（寬 = 螢幕寬 − 64pt），固定貼左、拖曳全程**不動**
- 主頁整體向右平移，只剩右側 **64pt 窄條**（tap 窄條或左滑收回）
- 主頁窄條**直角、上下貫穿全螢幕**（不加圓角裁切，見踩坑 #2）
- 展開時底部 tab bar **跟主頁一起滑出畫面**（不是留在原地、也不是另外藏）

## 架構定案

```
ZStack(alignment: .leading) {
    menu(dismiss)                       // 底層:固定貼左,frame(width: 屏寬-64)
        .background(bg.ignoresSafeArea())
        .allowsHitTesting(isPresented)
        .ignoresSafeArea(edges: .top)   // 內容區到狀態列下(header 自查 UIWindow inset)

    content                             // 主頁(被推開的層)
        .overlay { /* scrim: 黑 0.35×progress, ignoresSafeArea, tap 收回 */ }
        .overlay(alignment: .leading) { /* 左緣 16pt 漸層陰影帶, offset(x:-16) */ }
        .offset(x: totalOffset)         // 0(關) → revealWidth(開)
}
```

1. **ViewModifier 形式，拖曳 state 放 modifier 自身 `@State`** —— content 是 proxy，
   @State 變動只重跑 modifier body，不重建主頁樹。放 host 會讓 host body 每幀重繪
   → 長清單的 closure props 換 identity → 整列重渲染 → 滑動卡頓。
2. **掛載層：要推動 tab bar 就必須掛 App 根層**（包住整個 TabView）。tab bar 是
   TabView chrome，不在 tab content 子樹裡，從內層推不動。
3. **主頁不加 clipShape**：clip 範圍 = layout bounds（safe area 內），會把主頁上下
   （狀態列 / home indicator / tab bar 區）的背景延伸裁掉 → 推開後窄條上下縮一截
   ＋圓角斷面。不裁 = 直角全高，Threads 同款。
4. 開 / 關全走 `withAnimation`，**不掛 `.animation(value:)`**（隱式＋顯式雙重動畫
   會在 offset 上二次 pop）。

## 手勢（UIKit 橋接，勿用 SwiftUI DragGesture）

- **開啟**：`UIScreenEdgePanGestureRecognizer`（24pt 邊緣帶）。系統級 edge 手勢，
  自帶 `cancelsTouchesInView`（辨識成立自動取消 row Button 的 tap）、自動排除垂直
  捲動。`.began` 時 `setTranslation(.zero)` 歸零（系統 hysteresis 已累積幾 pt，
  不歸零起手會跳一段）。
- **收回**：`UIPanGestureRecognizer` + `cancelsTouchesInView = true`，掛在「子樹含
  UIScrollView 的祖先」（往上爬 superview 找，限 8 跳）；delegate
  `gestureRecognizerShouldBegin` 回 `|dx| > |dy|`（水平為主才 begin，垂直留給
  ScrollView）；`shouldRecognizeSimultaneouslyWith` 只放行 `other.view is UIScrollView`。
- **SwiftUI 手勢淘汰原因**：`.gesture(DragGesture)` 跟 ScrollView 搶 touch 卡頓；
  `.simultaneousGesture` 缺「判定為 drag 就取消 tap」→ 收回時誤觸 row。
- **手勢層 always-mounted，用 `isEnabled` 開關**。分支不可依 `isPresented` 切換
  view 結構（`if isPresented { view } else { view.modifier(...) }` 會換 view
  identity → 完成開啟那刻整個子樹拆掉重建，畫面閃一下）。
- always-mounted + 祖先掛載的 recognizer 要補「回前景（didBecomeActive）重掛」
  ——背景化期間祖先關係鬆動，attach 落錯 host 且守衛 `pan.view?.window != nil`
  恆真不自癒 → 回前景後收回手勢死透。

## velocity-matched spring（保證不過衝）

```swift
// distance = 目標 offset − 當前 offset;過衝會露出面板後面的縫,參數是算出來的:
// damping 42 / stiffness 380 → 衰減根 λ₂ = (42+√(42²−4·380))/2 ≈ 28.8
// 初速 clamp ±16 < λ₂ → 數學上不可能過衝,快甩只會更快到位
let rawV = abs(distance) > 1 ? Double(velocity / distance) : 0
return .interpolatingSpring(mass: 1, stiffness: 380, damping: 42,
                            initialVelocity: min(max(rawV, -16), 16))
```

放手判定：開 = 拖 > 70pt 或 fling > 350pt/s；收 = 拖過 33% 寬或 fling > 350。

## 踩坑清單（血淚版，按殺傷力排序）

1. **🔴 模擬器對「offset 平移含 UIKit 容器的大樹」渲染不可信**。同一份代碼在
   sim 上時好時壞，壞法包括：整片疊影（主頁內容留在原位、只有 overlay 被移走）、
   窄條顯示錯誤的一側（clip 窗移了、內容沒跟）。**真機始終正常**。視覺驗證一律
   真機；**勿因 sim 異常改架構**——曾誤信 sim 疊影而加回 clip、換掛載層、堆
   tab bar 補丁，把真機上已完成的版本改壞，代價十餘輪 build 才回滾。
2. **clipShape 會把窄條裁短**：clip bounds = safe area 內 → 上下縮 + 圓角斷面
   （真機用戶紅筆抓過兩次）。
3. **iOS 26 `.toolbar(.hidden, for: .tabBar)` 有留白 bug**：收起後 tab content
   高度縮短且不歸還，底部留一條白帶。
4. **UIKit `setTabBarHidden` 同樣救不了**：tab bar 藏了但仍佔 layout 位，safe area
   不更新，SwiftUI `ignoresSafeArea` 延伸不過去，露出 hosting 殼的預設白底。
   （正解根本不是藏 tab bar，是掛根層讓它跟著滑。）
5. **人造 hosting 邊界皆死路**：單 tab `TabView` + toolbar hidden → 底部留白；
   `NavigationStack` + navigationBar hidden → SwiftUI DisplayList
   `NSException` 直接 crash。
6. **`.geometryGroup()` 套在 App 級大樹上會弄壞子樹內 Button 的 hit-test**
   （tap 沒反應）。
7. **兜底 / scrim 層帶「隨進度變色」的動態成分，放在 GeometryReader background
   或 ZStack 新子項，會打亂渲染 flatten**（sim 上 offset 又脫節）。ZStack 子項數
   本身也是敏感因素——結構改動後必須整套重驗。
8. **陰影用左緣漸層帶，不用 `.shadow`**：主頁是天天滾動的活內容，layer 內容一變
   shadow 快取即失效 → 全屏離屏 blur 每幀重算。「常數 shadow 快取免費」的策略
   只適用靜態面板。
9. **雙抽屜互斥**：左右兩側抽屜要互傳 `canOpen: !另一側.isPresented`，否則同開
   時 backdrop 疊兩層、offset 互打、關不掉。
10. **跨層 drawer 內容要顯式觀察 theme / 語言並掛 `.id(theme+lang)`**：
    always-mounted overlay 的 @EnvironmentObject 變動 propagation 不可靠，
    換主題 / 語言後 drawer 卡舊樣式到重啟。
11. **edge-open 攔截層會吃掉子樹 NavigationStack 的原生返回**：開啟手勢的 edge zone
    （overlay + hitTest 攔截左緣帶）蓋在整個 root 上，push 頁的 interactive pop
    （也是左緣手勢）在 sibling 子樹收不到 touch → 用戶右滑想返回卻開了選單。
    不是手勢仲裁問題（`require(toFail:)` 無效——touch 根本到不了 pop recognizer），
    是 hitTest 攔截。修法：push 頁 onAppear / onDisappear 上報全域 flag，host 以
    canOpen gate 讓 edge zone hitTest 回 nil 透傳；sheet 呈現的頁天然免疫
    （presented 層在攔截層之上）。onAppear/onDisappear 時序天然正確（interactive
    pop 拖一半取消不 fire onDisappear、切 tab fire 後切回重 fire）。sim 驗證:idb
    合成 swipe 觸發不了 UIScreenEdgePanGestureRecognizer 但觸發得了 interactive
    pop（要慢滑）;判定 edge zone 是否攔截 = tap 左緣帶內可點元素,被吞即攔截中。

## 相關基建

同一套 UIKit 手勢橋接（edge pan 開啟 / 全幅 pan 收回 / 禁 ScrollView 回彈）也是
傳統 overlay 側板（面板蓋在主頁上方滑入）的基礎；overlay 側板若要全高蓋住
tab bar，掛根層 overlay + 全向 `ignoresSafeArea` 即可（無 transform，無踩坑 #1）。
