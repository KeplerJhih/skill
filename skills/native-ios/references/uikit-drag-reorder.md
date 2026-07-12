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
