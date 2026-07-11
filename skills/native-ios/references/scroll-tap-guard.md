# ScrollView 內 tap 列的捲動誤觸防線（scroll-tap-guard）

> Drop-in 源檔：`examples/ScrollTapGuard.swift`（SwiftUI + UIKit，無 design-system 依賴）。
> 實戰來源：2026-07 記帳 app 統計頁展開列——捲動慢拖誤開明細 sheet，同一坑在設定頁 / 選單 / picker 都踩過。

## 問題機制（為什麼會誤觸）

兩個獨立成因，疊加時最嚴重：

1. **SwiftUI 對「按下後慢速小拖」會 commit 給 Button**。手指按上 Button 後緩慢移動 10~30pt 再放手，SwiftUI 仍判定為點擊（實測 20pt / 0.5s 必中）。UIScrollView 自己的取消紀律（`canCancelContentTouches`）**管不到 SwiftUI 手勢系統**——它取消的是 UIKit touch 遞送，SwiftUI 的 gesture graph 不甩它。
2. **全域關掉觸摸延遲的副作用**。很多 app 為了修「ScrollView 內 TextField tap-to-focus 慢半拍」，會在 App init 設 `UIScrollView.appearance().delaysContentTouches = false`。副作用：捲動頁上的 Button「碰到立即按下」，快速輕滑的起手瞬間就被判成點擊。

## 解法：雙防線（`restoreTouchDelays()`）

一個 modifier 掛兩層防線：

1. **恢復觸摸延遲**：把所屬 UIScrollView 的 `delaysContentTouches` 恢復 true（先延遲 ~150ms 判意圖）——只影響這個 scrollview，表單頁維持全域設定不受牽連。
2. **垂直位移取消守衛**（`VerticalTapCancelGuard`）：UIKit `UIPanGestureRecognizer` + `cancelsTouchesInView = true`。垂直為主的移動一旦成立，立即取消 hit-test view（SwiftUI hosting）的 touch，已按下的 Button / onTapGesture 放棄觸發。UIKit pan 能取消到 SwiftUI touch 的關鍵：取消發生在 touch 遞送層（UIWindow sendEvent），不是 gesture 仲裁層。

```swift
ScrollView {
    VStack { rows }        // ← 掛在「內容」上
        .restoreTouchDelays()
}
```

## 三個掛載陷阱（都踩過）

1. **必掛 ScrollView 的「內容」上，不是 ScrollView 本身**。modifier 靠 superview walk 往上找 UIScrollView；掛 ScrollView 本身 = 注入的 UIView 是它的 sibling，walk 永遠落空 → 防線**靜默失效**（無 crash 無 log，只是誤觸還在）。
2. **sheet 呈現初期 superview 鏈還沒接上**。presentation 動畫期間 walk 會落空；靜態頁（之後沒有 state 變更觸發 `updateUIView`）一次落空 = 永久失效。源檔內建 50ms × 10 次重試補上。
3. **觸發詞寫太窄會漏掛新頁**。規則如果寫成「設定頁要掛」，之後新增統計卡內可點列時就不會想到它。正確觸發詞：「**任何 ScrollView 內新增 Button / onTapGesture 列的非表單頁**」——新增 scrollable tap 列時逐次自問有沒有掛。

## 適用邊界

| 場景 | 掛？ |
|------|------|
| 選項頁 / 清單 / 卡內可點列（無 TextField） | ✅ 掛 |
| 表單頁（有 TextField，靠全域 `delaysContentTouches=false` 修 tap-to-focus） | ❌ 勿掛 |
| 有橫向手勢的列（swipe row / 橫滑切 page） | ✅ 可掛——守衛只攔「垂直為主」移動，分軸不互擾 |
| 圖表按住查值（`chartXSelection` 類） | ✅ 可掛——按住不動位移 < pan 門檻，守衛不 begin |
| 長按拖曳排序的列表 | ⚠️ 掛 + 豁免——在 `gestureRecognizerShouldBegin` 開頭加你的排序旗標檢查（源檔有註解掛鉤）；scrollview `isScrollEnabled=false` 已內建不 begin |

## 驗證方式

- **正常 tap**：點列 → 應照常觸發。
- **慢速小拖**：從列上按下、緩慢垂直拖 ~25pt 放手 → 應只捲動、不觸發（修復前必誤觸）。
- 模擬器滑鼠對手勢細膩度保真有限——機制層可在 sim 驗，最終手感真機確認。
