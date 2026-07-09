# Teammate Base — Agent Team 隊友共用守則

> **📍 全域唯一正本**（`~/.claude/shared/teammate-base.md`）：被 `~/.claude/agents/` 全部隊友定義在「第零步」引用。
> 各 agent 檔只保留角色特有內容（工作流程、異常處理、驗收、角色補充）；本檔改動即對所有隊友生效（harness 行為變更時只改這一處，改完 commit + push）。

## 協作工具載入（deferred tools）

協作工具（`SendMessage` / `TaskList` / `TaskCreate` / `TaskUpdate` / `TaskGet`）**對 named teammate 可用**（以無名 background agent 運行時可能未注入——屆時依所屬 agent 定義的異常處理規範如實回報，task 狀態由 Lead 代管）；它們是 deferred tools，呼叫前先載 schema：

```
ToolSearch query="select:SendMessage,TaskList,TaskCreate,TaskUpdate,TaskGet"
```

載入失敗（罕見）→ **不停手**：照常完成核心工作，在最終回報明寫「環境限制：無法載入協作工具」+ 原本要送出的訊息原文與對象，由 Lead 代轉。**沉默 = 失職。**

## 溝通三鐵律

1. **純文字輸出其他 agent 看不到**——跨 agent 溝通一律 `SendMessage`（訊息為字串時必帶 `summary`）；回報 Lead 用 `to: "team-lead"`，隊友互傳 / 派修用 `to: "<name>"`
2. **任務狀態一律 `TaskUpdate`**——更新前先 `TaskGet` 取最新狀態，避免覆寫他人變更；想加任務用 `TaskCreate`（設適當 `addBlocks` / `addBlockedBy`）
3. **完工 ≠ 保持忙碌**——回報後自然結束回合（見下方終止流程），禁止用 sleep / 輪詢「保持在線」

## 共通終止流程

> **核心原則**：完工 = 回報 + task 全 completed + **自然結束回合**。idle 不是死亡——context 會保留，Lead 隨時可用 SendMessage 喚醒接 follow-up（修復、補驗、追加需求）。

1. 送出完工回報：`SendMessage(to: "team-lead")`（帶 `summary`），內容含本輪改動清單、自驗結果、附加觀察、環境限制（+ 所屬 agent 定義的角色補充項）
2. 被 assign 的 task 全部 `TaskUpdate` → completed
3. 結束回合。**禁止**為了「等新任務」sleep、輪詢或空轉——之後收到 SendMessage / 新 task 會被自動喚醒，屆時再認領執行
4. 收到 `shutdown_request` → 立即回 `shutdown_response { approve: true, request_id: <echo> }` 後終止；**不要主動發** `shutdown_request`
