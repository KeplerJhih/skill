# 收鍵盤 & 可編輯輸入框 — 通用元件與慣例

SwiftUI 表單的「收鍵盤」與「輸入框可點性」沉澱成三個**零 design-system 依賴、可跨專案 drop-in** 的元件。**新表單一律沿用，不要各自手刻**。改外觀只動單一檔，全 app 同步。

---

## 0. 可移植版 — drop-in 任何 SwiftUI 專案

完整源碼在本 skill 的 `examples/`（已**解除** design-system 耦合，純 SwiftUI / UIKit / Combine，iOS 16+）：

| 檔案 | 角色 | 對外 API |
|------|------|---------|
| `examples/KeyboardDismissDome.swift` | 玻璃半圓拉柄 View（Liquid Glass dome 外觀）| `KeyboardDismissDome(accent:action:)` |
| `examples/View+KeyboardDismiss.swift` | 收鍵盤 modifier | `.dismissKeyboardOnTap()` / `.keyboardDismissDome(accent:)` |
| `examples/EditableFieldStyle.swift` | 「明顯可編輯」輸入框樣式 | `.editableFieldStyle(fill:border:rail:pencilColor:showPencil:)` |

**三步安裝**：
1. 複製 `examples/` 三個檔到目標專案的 `Core/`（dome + modifier 是一組，必須一起搬）。
2. 表單 sheet 最外層套 `.keyboardDismissDome(accent: <主色>)`；備註 / 選填欄套 `.editableFieldStyle()`。
3. 要把 footer 釘在螢幕底 → 整層再加 `.ignoresSafeArea(.keyboard, edges: .bottom)`（完整骨架見 §2③）。

**解耦對照**（從有 design-system 的專案移植時，把專案 token 傳進參數即可；省略就吃系統語意色、零配置可跑）：

| 元件 | 原 token（範例）| 可移植參數 | 省略時的預設（系統語意色）|
|------|------|-----------|------|
| dome 箭頭 | `t.gold` | `accent:` | `.accentColor` |
| 輸入框填色 | `t.bgElev` | `fill:` | `.secondarySystemBackground` |
| 輸入框外框 | `t.lineFaint` | `border:` | `.separator` |
| 輸入框左軌 | `t.gold` | `rail:` | `.accentColor` |
| 鉛筆 icon | `t.inkDim` | `pencilColor:` | `.secondary` |

> dome 的尺寸（76×38 = 完美半圓）、icon 名、動畫曲線是**唯一合理值 → 刻意寫死**，不開成參數（開了沒人會改、只增複雜度）。要大改外觀直接動 `KeyboardDismissDome.swift` 一個檔。

下面 §1–§5 是**為什麼這樣設計**與踩坑——照抄前先讀，省得重踩。

> **與有 design-system 的專案版之關係**：專案內通常另有一份直接吃 `@Environment(\.theme)` token 的版本（收鍵盤 modifier、dome、editableFieldStyle）；`examples/` 版是把那些 token 抽成參數的可移植副本。若把早期的 toolbar 收法 / stickyKeyboardBar 收法統一成 dome 後，那些舊 modifier 會零 caller、可下架。

---

## 1. 收鍵盤模式 — 決策矩陣

統一收斂後 `View+KeyboardDismiss.swift` 只剩 2 個 live modifier（**早期的 `keyboardDismissToolbar`（黏鍵盤頂 toolbar 收法）/ `stickyKeyboardBar`（黏鍵盤頂輸入列）在全 app 改 dome 後通常零 caller、可下架** — 需要黏鍵盤頂的 chat/收款輸入列或全屏 TextEditor toolbar 收法時，pattern 見本檔 git 史）：

| 場景 | 作法 | 說明 |
|------|------|------|
| **表單 sheet**（有送出/儲存鈕的輸入頁）| `.keyboardDismissDome(accent:)`（Mode 4）| 收鍵盤全套（拉柄 + 點背景 + 滑動）；footer 釘底另見 §2③ |
| **純搜尋頁**（搜尋欄 + 結果清單、無送出鈕）| `.scrollDismissesKeyboard(.immediately)` + `.dismissKeyboardOnTap()` | iOS 原生搜尋手感（捲結果收 + 點空白收）。**別套 dome** — 見 §5 |
| 只要「點空白收」、不要拉柄 | `.dismissKeyboardOnTap()`（Mode 1）| dome 內部也用它；輕量場景單獨用 |

**Mode 4 dome 是「收鍵盤全套」**：一個 modifier 內含 ① 玻璃拉柄 tap ② 點背景空白收（`dismissKeyboardOnTap`）③ 滑動內容收（`scrollDismissesKeyboard(.immediately)`）。套這一行三種都有。

⚠️ **dome 內建 `.immediately` scroll-dismiss 有副作用**：在 dome 表單上「**一捲動就立刻收鍵盤**」。對表單通常沒問題（footer 釘底 + 捲動策略見 §2③），但這也是**純搜尋頁不套 dome** 的原因之一（見 §5）。

共用 dismiss 手法：一律 `window.endEditing(true)`（對整個 window 強制收），比 `sendAction(resignFirstResponder)` 可靠，且連 SwiftUI `@FocusState` 也會清（backing 仍是 UIKit responder）。

⚠️ **tap 手勢必須掛 window、不能掛 `background` 局部 view**：`Form`/`List`（UICollectionView）會把空白處的 touch 全部吃掉，touch 到不了 background 層的 recognizer → 點空白收在 Form 型 sheet **完全無效**（ScrollView/VStack 型 sheet 不會踩，所以容易漏測）。`View+KeyboardDismiss.swift` 的 `TapProxyView` 已改為 `didMoveToWindow` 時把 recognizer 掛到 window（ancestor 收得到所有 descendant 的 touch）、離開 window 自動移除；delegate 過濾（跳過 UITextField/UITextView、simultaneous）不變。

---

## 2. 玻璃半圓拉柄（Mode 4 / KeyboardDismissDome）— 為什麼這樣做

鍵盤頂緣中央浮一顆毛玻璃半圓凸起（鍵盤 icon + 金色向下箭頭），隨鍵盤升降、緊貼鍵盤頂緣，tap 收鍵盤。**這裡有 4 個非顯而易見的決策，照抄別重踩**：

### ① overlay 在內容層，不是 `.keyboard` toolbar
`.keyboard` `ToolbarItemGroup` 渲染在「鍵盤自己的圖層」，毛玻璃只能糊到鍵盤暗底 → 看起來是「**黑底 + 玻璃疊上去**」，不是真 Liquid Glass，且黏在 accessory 區不夠貼鍵。
**正解**：dome 放進 **app 內容層的 `.overlay`**（`KeyboardDismissDomeModifier`），毛玻璃透出的是真正的表單內容 → 真 Liquid Glass。

### ② 位置綁「連續鍵盤高度」，用鍵盤自己的動畫時長
`KeyboardHeightObserver` 觀察 `keyboardWillChangeFrame` / `WillShow` / `WillHide`，發佈 `height = UIScreen.main.bounds.height − frame.minY` + `duration = keyboardAnimationDuration`。dome 用 `.position(y: geo.size.height − kb.height − 19)` 釘在鍵盤頂緣（19 = domeHeight/2），並 `.animation(.easeOut(duration: kb.duration), value: kb.height)`。
**踩雷**：若改用 `keyboardWillShow` 的「最終高度 + fade-in」，視覺會變成「**dome 先就定位在那等待、鍵盤才從下面彈上來**」。必須綁連續 height + 鍵盤同款時長，才會「跟鍵盤一起從下往上滑」。

### ③ footer 釘底防誤觸 + 底部欄位可見 — footer 釘底 pattern
鍵盤彈起時要讓底部「送出 / 儲存」鈕**留原位不被頂上去**（按鈕浮到手指附近 = 誤觸送出，危險）：靠對**整個 sheet** 加 `.ignoresSafeArea(.keyboard, edges:.bottom)`（只加在 footer 上無效 — 父層 ScrollView/ZStack 仍被鍵盤 inset）。

⚠️ **硬事實（真機實測、SwiftUI 限制）**：同一層「footer 釘螢幕底」與「ScrollView 底部 focus 欄位自動捲上來可見」**互斥** — 因為 auto-scroll-to-focused 綁在 keyboard safe area，整層 `ignoresSafeArea` 會把它一起關掉。曾以為「只讓 footer 忽略鍵盤、ScrollView 保留迴避」可解耦 → 做不到。

**正解 = footer 釘底 pattern**（footer 釘底 **且** 欄位仍可捲動看見、非 type-blind）：
```swift
SheetRoot {                                     // ← 你的 sheet 根容器
  header
  ZStack(alignment: .bottom) {
    ScrollView { VStack { …欄位… }.padding(.bottom, 100) }  // ← padding 給捲動餘裕
    footerBar                                               // ← sibling、不放進 ScrollView
  }
}
.ignoresSafeArea(.keyboard, edges: .bottom)   // footer 釘螢幕底
.keyboardDismissDome(accent: <主色>)
```
- footer 當 `ZStack(.bottom)` 的 sibling（不在 ScrollView 內）→ 釘螢幕底、被鍵盤蓋住沒關係（dome 收鍵盤後才按得到，安全）。
- ScrollView 內容加 `.padding(.bottom, ~100)` → 低處 focus 欄位可**手動捲**到鍵盤上方看見可打（auto-scroll 雖被關，手動捲仍可，跟上面骨架一致）。
- **反例**：只對整個 sheet 根容器套 `ignoresSafeArea` 而不用 `ZStack(.bottom)` + padding → footer 是釘底了，但底部欄位被鍵盤蓋死又捲不出來（type-blind）。
- ⚠️ dome 的 `.immediately` scroll-dismiss：捲動時鍵盤會收 → 等於「捲動 → 收鍵盤露出欄位」，可接受；但要靠 padding 才有得捲。

短表單（欄位都在上半、鍵盤升起仍可見）可省 `ZStack(.bottom)`、整層 `ignoresSafeArea` 即可。**搜尋頁無送出鈕、不涉誤觸 → 不要釘底**（見 §5）。

### ④ 中文 / 注音輸入「不需要」另做組件
中文鍵盤上方的「預測候選列」是鍵盤 frame 的一部分，dome 綁的是 `frame.minY`（鍵盤頂緣，含候選列），所以 dome 會**自動坐在候選列之上**、不會被蓋。**不需要為中文輸入額外做一個組件**（此問題實測確認過）。

外觀調整：只動 `KeyboardDismissDome.swift`。半圓用 `UnevenRoundedRectangle(topLeadingRadius: h, topTrailingRadius: h, bottoms: 0)`，`width = 2×height`（76×38）為完美半圓；`.background(.ultraThinMaterial, in: dome)` + 上緣白色高光漸層描邊 = Liquid Glass 感。鍵盤 icon 用 `.primary`（深淺自適應），箭頭用傳入 `accent`（通常是主色 token）。

---

## 3. 「明顯可編輯」輸入框（editableFieldStyle）

選填欄（尤其備註）常用極淡外框，跟分隔線一樣 → user 不知道能點。`.editableFieldStyle()` 解決：**填色底 `fill` + 左金色細軌 `rail` + 細框 `border` + 右鉛筆 icon**，傳入 theme token → 深淺色自適應。`showPencil: false` 可關鉛筆。

```swift
TextField("note", text: $note).editableFieldStyle()
```

**注意**：此 modifier 只管「樣式」與 `.contentShape(Rectangle())`。**focus / tap 手勢仍要 caller 自己掛**（見下節），style 本身不會讓點 padding 就 focus。

---

## 4. 通用陷阱：`.contentShape` 擴大的是 SwiftUI 命中區，不是 UITextField focus

`.contentShape(Rectangle())` 讓整個框在 **SwiftUI 層**可被 tap 命中，但**點到 padding/旁邊空白不會 focus 底層的 UITextField**（TextField 的 first responder 只有文字本身那塊會觸發）。

要「點整個框任何地方都 focus」：caller 自己掛 `@FocusState` + 整框 `.simultaneousGesture(TapGesture)`：
```swift
@FocusState private var focused: Field?
…
TextField("amount", text: $amount)
    .focused($focused, equals: .amount)
    .editableFieldStyle()
    .simultaneousGesture(TapGesture().onEnded { focused = .amount })  // 點框邊也 focus
```
用 `.simultaneousGesture` 而非 `.onTapGesture`，才不會吃掉 TextField 自己的點擊。

---

---

## 5. 純搜尋頁：不套 dome（用 scroll + tap）

搜尋類 sheet（「搜尋欄 + 結果清單」這種）**不要套 dome 拉柄**，改 `.scrollDismissesKeyboard(.immediately)` + `.dismissKeyboardOnTap()`。原因：

- 結果少時（1~2 筆），清單頂部對齊、下方到鍵盤之間會有一塊空白 — 這是 **iOS 原生搜尋的正常樣子**（通訊錄 / 設定 / App Store 皆然），**不是 bug、修不掉也不該修**。
- dome 玻璃拉柄浮在那塊空白裡 = **視覺孤兒**，突兀。
- 搜尋頁本就沒送出鈕、不涉誤觸，也不需 footer 釘底；scroll（捲結果）+ tap（點空白）收鍵盤就是最自然的 iOS 搜尋手感。
- **踩坑**：曾誤把 dome 套上搜尋頁 → 使用者回報「怎麼有這麼大的空格」。診斷重點：那塊空白**不是 dome 把 content 撐全高造成**（content 本就有 keyboard-avoid — 空狀態訊息落在「鍵盤上方」區而非全螢幕中央可證），純粹是「少結果 top-aligned 清單」固有 + 孤兒拉柄。改 overlay 重構也修不掉（因為本來就 avoid），正解是拆掉搜尋頁的 dome。

---

## 落地參考（在你的專案裡挑真實 sheet 當範本）

- **表單 + footer 釘底完整骨架**：在專案裡挑一個「表單 + 底部送出/儲存鈕」的 sheet，做成 §2③ 的完整骨架（ZStack(.bottom) + padding.bottom + ignoresSafeArea + dome + editableFieldStyle + 整框 focus 手勢），其餘長表單一律沿用同骨架。
- **純搜尋頁 scroll+tap**：搜尋類 sheet（搜尋欄 + 結果清單）沿用 §5，不套 dome。
- 專案特有的踩坑決策過程，沉澱在該專案自己的踩坑日誌（CLAUDE.md / decisions log）。

> 移植到新專案時：源碼從 §0 的 `examples/` 複製，互動骨架與「footer 釘底」照 §2③ 抄；上面的骨架只是「長這樣用」的範本、不是依賴。
