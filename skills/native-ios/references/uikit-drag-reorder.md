# 自製長按拖曳排序：SwiftUI 手勢的結構性盡頭與 UIKit 橋接解法

> Drop-in 源檔：`examples/ReorderableDragList.swift`（零 design-system 依賴）。
> 適用：ScrollView 內的自繪排序列表（長按 ☰ 把手抓起 → 拖動 swap → 放手 commit）。
> 若專案用原生 `List + .onMove` 且能接受 List 樣式介入，不需要本文；自繪卡片風格才走這條路。

## 症狀

長按拖曳排序「一直抖動」，且在 SwiftUI 層怎麼修都殘留：按住彈掉要按好幾次、
拖動跨列時跳格、兩列邊界緩慢來回時瘋狂震盪、偶發拖完列表卡在浮起狀態。

## 兩個結構性根因（SwiftUI 層修不掉）

### 1. 啟動競態 — 長按醞釀期被其他 recognizer 殺掉

`LongPressGesture.sequenced(before: DragGesture)` 醞釀期（0~0.5s），同一根手指上至少還有：

| Recognizer | 啟動閾值 | 殺傷方式 |
|---|---|---|
| UIScrollView 原生 pan | ~10pt | `canCancelContentTouches` 取消 content touch |
| 專案自訂 touch-cancel 守衛（若有） | ~10pt | `cancelsTouchesInView` |

SwiftUI LongPress 的 `maximumDistance` 容忍若 >10pt 形同虛設——pan 先到。防護旗標
（static bool）要**長按成立後**才能翻；`scrollDisabled` 要等 SwiftUI render 落地
UIKit——兩道豁免都有時序死角。按住時的自然肉抖 ≥10pt → touch 被 cancel → 序列半途
死 → 列彈回 → 重按又死 =「一直抖」。

**致命連帶**：touch 被 UIKit cancel 時，SwiftUI sequenced gesture 的 `onEnded`
**不保證 fire** → 拖曳旗標 / draggingID 卡死（scrollDisabled 永久、列卡浮起）。
背景化中斷同款。

### 2. swap 時基 — ForEach move 動畫與 `.local` 座標互相污染

自製 reorder 的標準寫法：swap 時 `withAnimation { items = copy }`（讓位動畫）+
dragging row 用 `visualOffset = dragOffset − (idx − startIdx) × stride` 補正 +
`.transaction { $0.animation = nil }` 攔自身動畫。這套數學**只在「排位位移與 offset
補正同幀 atomic 落地」時自洽**：

- `.transaction` 能否完全攔住 ForEach move 的 position 動畫是黑箱（版本間行為有異）
- 攔不住 → 排位是 0.3s 漸變、offset 是瞬時 → 跨界瞬間跳半格再漂回
- 更糟：`DragGesture(coordinateSpace: .local)` 的座標系掛在把手上，row 移位中
  translation 被污染 → 污染值回饋進 swap 判定 → **邊界 swap↔unswap 無限震盪**

## UIKit `UILongPressGestureRecognizer` 橋接（解法四要點）

把手上蓋一個透明 `UIViewRepresentable`，掛 `UILongPressGestureRecognizer`：

1. **`.began` 同步關外層 scroll**：walk superview 找 `UIScrollView` →
   `isScrollEnabled = false`——UIKit 事件流內即時生效，**不等 SwiftUI render**。
   競態消失：長按成立瞬間 pan 已無從啟動。若專案有 touch-cancel 守衛，同一時點翻
   豁免旗標（同樣即時）。`.ended/.cancelled` 對稱恢復。
2. **位移一律讀 `location(in: view.window)`**：window 座標系不隨 row 移位變化，
   translation 永遠乾淨——就算讓位動畫沒被攔乾淨也只是視覺過渡，不會回饋進手勢。
3. **`.cancelled / .failed` 分支保證清理**：來電 / 背景化 / touch 被系統收走都走
   這裡，旗標與浮起狀態必復位（SwiftUI onEnded 給不了這個保證）。
4. **拖曳中 swap 只動 local 工作副本，`.ended` 才 commit 回 binding**：
   binding 若直通 `@Published`（didSet persist），逐 swap 寫入 = 每次 swap 觸發
   JSON encode + 整頁 re-render；local copy 讓 persist 收斂為結束一次。
   cancelled 丟棄副本 → 意外中斷不落半成品排序。

**為什麼 UIKit recognizer 不怕 re-render**：手勢狀態在 Coordinator（UIKit 物件），
SwiftUI view diff 只要 identity 穩定（ForEach id 不變）就保留 UIView 實例，
`updateUIView` 刷新 closure 捕獲即可——進行中的手勢完全不受 body 重評估影響。
這是它相對 SwiftUI gesture（state 隨 view 樹重建）的根本優勢。

## 保留的 SwiftUI 層數學（橋接後仍需要）

- **hysteresis 0.6 格**判 swap（非 round 0.5）：解觸控 ±1pt 雜訊在半格邊界反覆
  swap-unswap
- **`dragStartIdx` 從啟動到結束不變**：swap 後更新 start 會讓 translation 與
  start 不同步，累積錯位變「兩格兩格切換」
- **rowHeight 必須精確等於 row 視覺高度**（排序列鎖 `.frame(height:)`，字體縮放
  不得撐高），stride = rowHeight + 列間距
- dragging row：`.transaction { $0.animation = nil }` + 讓位列 spring；
  scale/shadow 進出場由 `.animation(value: draggingID)` 承擔

## 微調參數心得

- `minimumPressDuration` 0.35s 即可（SwiftUI 版被迫 0.5s 是為了降低半途死的頻率；
  UIKit 版醞釀期被 pan 搶走 = 默默 fail 改捲動，無視覺副作用，不需要長 duration）
- `allowableMovement` 用預設 ~10pt：跟 scroll pan 的互斥仲裁天然分流
  「滑動意圖（快移）→ pan 先成立」vs「按住意圖（慢）→ 長按成立」，
  正是原生 UITableView reorder 的行為模型
- 慢速捲動誤抓的後果（列浮起，放手復原）遠輕於漏抓的挫敗感，不必為此加大 duration

## 驗證注意

抖動類問題**模擬器不可信**（渲染時基與真機不同），真機驗四項：
抓起成功率（連按十次）、跨多列拖動、兩列邊界緩慢折返、拖曳中背景化再回來。
模擬器可冒煙的部分：長按浮起（`idb ui tap --duration 2.5` 後台 + 中途截圖）、
放開復位、捲動恢復。模擬器打不出「長按+拖曳」複合手勢（idb swipe 只有線性插值）。

---

# 整列長按變體（無把手）

> Drop-in 源檔：`examples/LongPressRowReorderList.swift`。
> 上面那套把 recognizer 掛在 ☰ 把手的透明 view 上。若要**長按列上任何位置**都能抓起
> （列面積就是把手），透明 view 覆蓋整列會擋掉列本身的點擊與左滑 —— 改掛到**外層 UIScrollView**。

## 為什麼掛祖先而不是列

祖先的 recognizer 收得到整個子樹的 touch，但**不參與 hit-test**，所以：

- 列的 `NavigationLink` / `onTapGesture` / 左滑 `DragGesture` 全部照常運作
- 長按成立那一刻才由 recognizer 接管

`gestureRecognizerShouldBegin` 用 host view 的 bounds 過濾，讓長按只在列表範圍內成立，
頁面其他區域（分段控制、別的清單）不受影響。列 index 從 `location(in: host).y / rowHeight` 換算，
所以**列高必須固定且精確**。

## 坑：`cancelsTouchesInView` 管不到 SwiftUI 手勢

最反直覺的一條。長按成立後放開手指，**列的點擊照樣觸發**（推進了下一頁）。
`cancelsTouchesInView` 只取消 UIView 的 touch 傳遞，SwiftUI 自己那套 recognizer 不吃這招。

解法是宣告失敗依賴：

```swift
func gestureRecognizer(_ g: UIGestureRecognizer,
                       shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
    if let sv = scrollView, other === sv.panGestureRecognizer { return false }
    return true
}
```

其他 recognizer 必須等長按**失敗**才能成立。行為自然分流：

| 使用者意圖 | 長按結果 | 誰接手 |
|---|---|---|
| 點一下 | 放手時未達 0.45s → 失敗 | SwiftUI tap |
| 左滑 | 移動超過 `allowableMovement` → 失敗 | SwiftUI drag（左滑動作列） |
| 長按拖曳 | 成立 | 本 recognizer |
| 捲動 | 醞釀期被 pan 搶走，默默 fail | scroll pan（例外，維持即時） |

捲動的 pan 必須排除在依賴之外，否則捲動要等 0.45s 才會動。

## 參數：0.45s / 8pt（比把手版寬鬆）

把手版用 0.35s / 12pt。整列版要跟**左滑**共存，門檻調成 0.45s / 8pt：
移動判定更早失敗，左滑起手稍慢也不會被長按吃掉。

## 坑：常駐 `.shadow` 讓同列的左滑掉幀

浮起效果若寫成 `.shadow(color: isDragging ? … : .clear, radius: isDragging ? 8 : 0)`，
即使半徑 0 也會讓每列走離屏渲染。同一列若還支援左滑（offset 每幀變動）就明顯卡。
改用 `scaleEffect` + `zIndex` 表達浮起即可。

## 與 `.contextMenu` 互斥

兩者都吃長按，0.45s 的 recognizer 會先成立並取消 touch，contextMenu 再也叫不出來。
用本元件的列，把編輯／刪除改放到左滑動作（見 `references/swipe-action-row.md`）。

## 驗證注意

模擬器打不出「長按＋拖曳」複合手勢，但**可以驗依賴是否正確**：
`idb ui tap --duration 1.0` 打在列上，若列沒有被推進下一頁 = `shouldBeRequiredToFailBy` 生效。
拖曳手感、swap 邊界仍須真機。
