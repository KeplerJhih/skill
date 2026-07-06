---
description: Agent Team 工作流程 — 官方 Agent Teams 多隊友協作，契約優先 + QA 驗證
argument-hint: [需求描述]
---

# Command: /team (Agent Team Workflow)

此指令啟動 **官方 Agent Teams 多 Claude 實例協作模式**（implicit team 機制，Claude Code ≥ 2.1.178）。作為 **Team Lead**，你的職責是：分析需求、制定團隊藍圖、建立共享 task list、並行 spawn teammate、事件驅動監督調度。每位 teammate 是獨立 Claude Code session，協作工具（`SendMessage` / `TaskList` / `TaskCreate` / `TaskUpdate` / `TaskGet`）**對 teammate 始終可用**，可彼此直接對話、共享 task list，完成 / idle 時自動通知 Lead。

**⚠️ 核心原則：需求分類、契約優先、Mailbox 對話、品質門。** 嚴禁未獲用戶明確確認 (`Yes`/`Y`) 前啟動團隊。

**🔑 與 `/doit` 區別**：`/doit` 是單人 Tech Lead 模式（你親自編碼）；`/team` 是多 Claude 實例團隊模式（teammate 自主協作，你監督調度、不親自編碼）。

**📐 最高原則：工具 schema 為準。** 啟動時先用 `ToolSearch` 載入協作工具 schema；本文檔的參數、格式、回應樣式與實際 schema / runtime 行為衝突時，**一律以實際為準**並照真實行為繼續，不要因文檔滯後而停手（harness 演進快，整套流程過時的教訓已發生過一次——TeamCreate 時代流程即為前例）。

**📖 官方文檔（權威參考）**：<https://code.claude.com/docs/zh-CN/agent-teams>（英文版把 `zh-CN` 換成 `en`）。遇到本文檔未涵蓋的故障、新行為或版本差異 → 用 `WebFetch` 抓官方文檔查證最新機制再行動；查證後發現本文檔已過時 → 依實際行為繼續任務，並在完成回報附「**工具箱優化建議**」段提出 team.md 修正方案，由用戶決定是否採納。

---

## 🧠 機制認知（implicit team，動手前先建立正確模型）

| Runtime 事實 | 對 Lead 的意義 |
|------|-----------|
| session 啟動時 runtime **自動**建立本 session 的 team（`~/.claude/teams/session-<id>/`）與共享 task list（`~/.claude/tasks/session-<id>/`） | **沒有、也不需要 `TeamCreate` / `TeamDelete`**；每 session 恰好一個 team |
| 用 `Agent` tool 帶 `name:` spawn 出的就是 teammate | spawn 回應 `agentId: <hash>` **= 正常成功**；把 name ↔ agentId 對照記進工作筆記 |
| spawn 天生 async | **沒有 `run_in_background` 參數**（傳了會驗證錯誤）；spawn 立即返回，完成時自動通知 |
| teammate 完成 / idle / 失敗都會**自動通知** Lead | **不要輪詢 `TaskList`**，事件驅動即可 |
| 運行中 teammate 用 `SendMessage(to: "<name>")` 喚醒（context 延續）；**已完成的**改用 agentId | **不要**對同名再 call `Agent`——會起新實例、丟失原 context |
| 隊友 model 省略時的行為隨 harness 版本變動（新版繼承 spawn 來源、舊版走「默認隊友模型」設定），別依賴 | 藍圖 roster 每位隊友**明確填 model** |
| session 結束自動清理 team 目錄 | **沒有收尾清理步驟** |
| Lead 固定 = 主 session；team 不可嵌套 | 隊友不能再開 team；跨領域子任務由 Lead 拆分 |
| 高風險任務可 spawn 時帶 `mode: "plan"` | 隊友先規劃、送 plan_approval_request，Lead 批准後才動手 |

---

## 前置條件（啟動前自檢）

| 條件 | 檢查方式 | 不滿足時 |
|------|---------|---------|
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` | settings.json 的 `env` | 提示用戶開啟 |
| 協作工具存在 | `ToolSearch query="select:SendMessage,TaskList,TaskCreate,TaskUpdate,TaskGet"` | 缺任一 → 回報環境異常，退回 `/doit` |
| `~/.claude/agents/` 存在所需隊友類型（`backend` / `frontend` / `mobile` / `qa` / `code-reviewer` / `devops`） | `ls ~/.claude/agents/` | 提示補建或退回 `/doit` |
| 顯示模式合適 | 見下方「teammateMode」 | 依指引調整後再啟動 |

### 🖥️ teammateMode（顯示模式決策）

teammate 顯示模式由 settings.json `teammateMode` 決定：

| 值 | 行為 | 適用性 |
|----|------|--------|
| `in-process`（官方預設，**建議**） | 隊友跑在主終端的 agent 面板（↑↓ 選隊友、Enter 進入對話、`x` 停止、Ctrl+T 看 task list） | **任何終端都可用**（含 cmux）；最穩 |
| `tmux` / `auto` | 每位隊友獨立 split pane | 僅原生 tmux 或 iTerm2（+ `it2` CLI）。**cmux 的 tmux shim 已知不相容**（CC ≥ 2.1.201 的 `respawn-pane`，2026-07 實測）|

**spawn 失敗且錯誤訊息含 pane / tmux 字樣**（例：`Unsupported tmux compatibility command`）→ 這是顯示模式 / 終端相容性問題，不是 team 機制問題：**停手回報**，不要反覆重試。

**⚠️ CLI 參數優先於 settings.json（2026-07 實測踩坑）**：啟動指令帶了 `--teammate-mode` 就會覆蓋 settings.json，改設定、開新 session 都無效（該 session 內模式已鎖定）。cmux 的 `claude-teams` 啟動器**預設注入 `--teammate-mode auto`** 且設 TMUX shim → auto 走 tmux 路徑必敗。診斷：`ps -p <claude pid> -o command=` 看實際啟動參數。修法：啟動時顯式帶 `--teammate-mode in-process`（cmux 例：`cmux claude-teams --teammate-mode in-process`，多餘參數會 forward 給 claude 蓋掉其預設；專案 `run.sh` 範本已內建），或在無 TMUX shim 的一般終端跑純 `claude` 讓 settings.json 生效。

> **隊友類型是語言中立的角色**：`backend` 可能對應 Go / Python / Node / PHP…，`frontend` 對應 React / Vue…，`mobile` 對應 iOS / Android / RN…。**實際載入哪個 skill 由隊友自己啟動時偵測技術棧後動態匹配**，不在這裡寫死。

## 🛑 啟動閘門（輸出任何用戶可見文字之前，hook 會自動注入同樣提醒）

1. `ToolSearch query="select:SendMessage,TaskList,TaskCreate,TaskUpdate,TaskGet"` 載入協作工具 schema（schema 為準，文檔滯後照實際行為走）
2. `Read("~/.claude/shared/workflow-base.md")` 取得共用流程規範（任務類型分流、專案偵測、上下文檢索、Skill 載入、向用戶詢問與問題回報、藍圖偏離處理、停損原則、驗證觸發條件）
3. 載入名稱含 `karpathy-guidelines` 的 skill（**以當前 available skills 清單的實際名稱為準**，plugin 安裝時帶命名空間前綴，例如 `andrej-karpathy-skills:karpathy-guidelines`），再依任務內容匹配載入專屬 Skill（情境 A 可延後至取得需求後補做）

---

## 🚀 觸發邏輯

### 🟢 情境 A：用戶未提供具體需求

**判定**：用戶僅輸入 `/team`，後面沒有描述。

**行動**：執行輕量偵測（workflow-base「情境 A 輕量偵測與沿用」：只做步驟 0），展示偵測結果並詢問：

> **您好！我是您的 Team Lead，準備為您組建 Agent Team。**
>
> **🔎 偵測結果**：`[從 workflow-base 步驟 0 取得，包含偵測到的技術棧]`
> **🤝 可用隊友類型**：`[ls ~/.claude/agents/ 列出]`
>
> **請問需要處理什麼任務？**
>
> 1. ✨ **全端功能開發** - 後端 API + 前端介面 + QA 驗證
> 2. 🔧 **後端功能開發** - 僅後端
> 3. 🎨 **前端功能開發** - 僅前端
> 4. 📱 **行動端功能開發** - iOS / Android / 跨平台
> 5. 🐛 **跨端問題修復** - 多隊友協作診斷與修復
> 6. ♻️ **架構重構** - 多隊友並行重構
>
> *請選擇一個項目，或直接描述您的具體需求。*

用戶回覆後：進入情境 B 流程；偵測沿用依 workflow-base「情境 A 輕量偵測與沿用」（步驟 0 沿用、步驟 1/2 依任務類型照常）。

### 🔵 情境 B：用戶已提供需求

**判定**：用戶輸入 `/team [需求描述]`，或由情境 A 延續。

**行動**：

1.  **任務類型分流（MANDATORY）**：依 `workflow-base.md` 判定 Code / Config / Docs / Trivial。
2.  **專案偵測**：依 `workflow-base.md` 執行（情境 A 已做步驟 0 則沿用，步驟 1/2 依任務類型照常）。
3.  **上下文檢索**：依 `workflow-base.md` 按任務類型挑工具。
4.  **Skill 載入回查（給 Lead 用）**：啟動閘門已完成 `karpathy-guidelines` 與初次匹配載入，此處僅回查——分析至此浮現新領域則立即補載。**注意**：Lead 載入的 Skill **不會繼承給隊友**，每個隊友的 agent 定義已要求自行載入。
5.  **⚠️ 需求分類判斷（MANDATORY）**：

    | 資料特性 | 判定 | 執行模式 |
    |---------|------|---------|
    | 固定 / 極少變動的選項（行政區、分類、國碼） | 前端靜態資料 | 🅰️ 純前端 |
    | 純 UI 互動（拖拽、摺疊、動畫） | 不需後端 | 🅰️ 純前端 |
    | 本地功能（表單驗證、草稿暫存、主題切換） | localStorage | 🅰️ 純前端 |
    | 依賴用戶行為或 DB 狀態的動態資料 | 需要 API | 🅱️ 後端先行 |
    | 涉及 CRUD、權限、跨用戶共享的資料 | 需要 API | 🅱️ 後端先行 |
    | 需求不明確 | 先問用戶 | ❓ 暫停確認 |

    > 💡 **教訓**：地址選擇器功能曾不必要地派後端做了 3 個 API，最終改用前端靜態資料。多花 10 秒判斷，省掉整個後端隊友的 token 成本。

6.  **團隊組建分析**：

    | 需要時機 | 對應隊友 (subagent type) |
    |---------|--------------------------|
    | 🅱️ 模式：API / Domain / DB 變更 | `backend`（語言中立，隊友自己偵測） |
    | 涉及頁面 / 組件 / 介面 | `frontend`（框架中立，隊友自己偵測） |
    | 涉及行動端（任意平台） | `mobile`（平台中立，隊友自己偵測） |
    | 涉及容器化 / K8s / IaC / CI/CD | `devops` |
    | 涉及前端畫面，需要 E2E 驗證 | `qa` |
    | 任務中等以上複雜度 | `code-reviewer`（最後階段啟動） |

    **規模建議**：3–5 位隊友最佳，每位 5–6 個 task 為理想負載。

7.  **🛰️ 技術棧偵測（MANDATORY，啟動 team 前）**：確認各隊友工作目錄的**絕對路徑**（隊友會自己偵測語言，Lead 只準備路徑）；專案僅單一技術棧時在藍圖明示，避免用戶困惑為何沒派某類隊友。
8.  **🔌 MCP 工具偵測**：依 `workflow-base.md`「🔌 MCP 工具動態偵測」執行，結果納入藍圖，並在各隊友啟動 prompt 中標注分配給該隊友的 MCP 工具。
9.  **過度設計檢查（MANDATORY，藍圖前最後一道）**：依 `workflow-base.md` 三題自審。

---

## 📋 團隊任務藍圖與確認 (MANDATORY)

啟動 Agent Team 前，**必須**向用戶展示「團隊任務藍圖」並等待確認。
藍圖中的開放決策點、缺漏資訊與問題回報，依 `workflow-base.md`「🗣️ 向用戶詢問與問題回報規範」整理；視覺方案可用視覺化預覽輔助詢問。

> ### 🏗️ 團隊任務藍圖：[任務簡稱]
>
> **🔎 偵測結果**：[技術棧 / 子專案 / 工作目錄]
> **📌 任務類型**：[Code / Config / Docs / Trivial]
>
> **🔍 上下文分析**
> - **專案結構**：[Monorepo: backend/ + frontend/ ...]
> - **涉及路徑**：[相關檔案 / 目錄]
> - **關鍵組件**：[Serena 找到的關鍵函式 / Entity / API]
>
> **🎯 執行目標**
> - [目標 1] / [目標 2]
>
> **👥 團隊編制 (Team Roster)**
>
> | 隊友名稱 | Subagent Type | 工作目錄（絕對路徑） | 模型 |
> |---------|--------------|--------------------|------|
> | `be-{feature}` | `backend` | `[後端目錄]` | [依任務填：opus / sonnet / haiku / fable] |
> | `fe-{feature}` | `frontend` | `[前端目錄]` | [同上] |
> | `qa-{feature}` | `qa` | — | [同上] |
> | `cr-{feature}` | `code-reviewer` | — | [同上]（最後階段，可選） |
>
> > 隊友**不會繼承** Lead 的模型——此欄必填。隊友啟動時自行偵測技術棧並動態匹配 skill，這裡不寫死語言。
>
> **🔌 MCP 工具**（僅列相關的）
> - `[mcp名稱]` — [用途]（分配給：[隊友名稱]）
>
> **📊 需求分類**：`🅰️ 純前端` / `🅱️ 後端先行`（標示判斷理由）
>
> **🚩 共享 Task List 結構**
> - 階段 A（owner: `be-{feature}`）：契約設計 → 實作 → 測試
> - 階段 B（owner: `fe-{feature}`，blocked-by: 階段 A 契約任務）：依契約實作
> - 階段 C（owner: `qa-{feature}`，blocked-by: 階段 B）：E2E 驗證
>
> **🔗 隊友溝通協定（Blackboard + Mailbox）**
> - **契約檔**：`team/contracts/{feature}.api.md`（後端寫，前端 / 行動端讀）
> - **場景檔**：`team/scenarios/{feature}.qa.md`（Lead 寫，QA 讀）
> - **決策日誌**：`team/decisions/{feature}.log.md`（任何隊友可寫）
> - **跨隊友訊息**：`SendMessage` 直接溝通，不需經 Lead
>
> **⏱️ 預估規模**：[小 / 中 / 大]
>
> *確認後將以 Team Lead 身份啟動 Agent Team。(`Y` 確認)*

---

## ✅ 執行階段 (Post-Confirmation)

### 1. 準備共享資源

- 確認 `team/contracts/`、`team/scenarios/`、`team/decisions/` 存在（不存在則建立）
- 撰寫 QA 場景檔 `team/scenarios/{feature}.qa.md`（從藍圖目標展開為可驗證的用戶流程清單）
- 若 🅱️ 模式：在 `team/contracts/{feature}.api.md` 留好骨架（標題 + 預期端點清單），後端隊友據此補完

### 2. 啟動團隊（3 步 + pre-flight）

#### 2-a. 協作工具 schema 校準

啟動閘門已載入協作工具 schema（若未載，此時補：`ToolSearch query="select:SendMessage,TaskList,TaskCreate,TaskUpdate,TaskGet"`），以載回的 schema 校準本文檔認知（最高原則：schema 為準）。

#### 2-b. 建立共享 task list

依藍圖每階段建一個 epic task（不要把每個 sub-step 都拆出來，過細的 task 反而干擾隊友）。建議顆粒度：

- **後端**：1 個 epic + 1 個「補完 API 契約」task（後者是獨立 milestone，blocks 前端 / 行動端）
- **前端 / 行動端**：各 1 個 epic（blocked-by 契約 task，彼此並行）
- **QA**：1 個 epic（blocked-by 前端 / 行動端 epic）

每個 task 以 `TaskCreate` 建立後，用 `TaskUpdate` 設 `owner:`（**必須與即將 spawn 的隊友 `name:` 完全一致**）與 `addBlockedBy:`。更新既有 task 前先 `TaskGet` 取最新狀態，避免覆寫。

#### 2-c. Pre-flight 探針（新環境 / harness 版本更新後必做，其餘建議做）

正式 spawn 全 roster 前，先 spawn 一個 1-turn 便宜探針驗證 teammate 通道：

```
Agent { name: "probe", subagent_type: "general-purpose", model: "haiku",
        prompt: "探針任務：呼叫 SendMessage(to: \"team-lead\", summary: \"probe OK\", message: \"OK\") 後結束回合，不做其他事。" }
```

> 探針用 `SendMessage` 回報而非純文字回覆——teammate 的純文字輸出 Lead **看不到**，
> 讓探針發訊息可以一次驗證 spawn 通道 + mailbox 通道（2026-07 實測：只回純文字時 Lead 僅收到 idle 通知）。

- 成功（返回 `agentId: <hash>`，收到 probe 的 SendMessage 或 idle 通知）→ 通道正常，繼續
- 失敗且錯誤含 pane / tmux 字樣 → teammateMode 問題（見前置條件），**停手回報用戶**
- 其他錯誤 → 如實回報，不要帶病 spawn 全 roster

#### 2-d. 並行 spawn 全 roster

**單一訊息多個 `Agent` tool call = 並行**。每個 spawn 的參數：

| 參數 | 內容 |
|------|------|
| `subagent_type` | `backend` / `frontend` / `mobile` / `qa` / `devops` / `code-reviewer` |
| `name` | 與 task owner 完全一致（例 `be-{feature}`） |
| `model` | 依藍圖 roster 填（隊友不繼承 Lead 模型） |
| `mode` | 可選；高風險任務填 `"plan"`（隊友先規劃、Lead 批准後動手） |
| `prompt` | 自包含任務簡報，見 2-e |

spawn 回應 `agentId: <hash>` = 成功；**把每位隊友的 name ↔ agentId 記下**（喚醒已完成隊友要用 agentId）。

#### 2-e. Teammate prompt 必含清單（每位都要，prompt 自包含）

teammate 是獨立 session，**看不到 Lead 的對話歷史**。prompt 至少包含：

1. 本人名字 + 工作目錄絕對路徑
2. 契約 / 場景 / 決策三檔的絕對路徑
3. `TaskList` 後認領自己 owner 的 task
4. 分配給它的 MCP 工具清單（名稱 + 用途）
5. **溝通協定三鐵律**（見下）
6. 驗收標準（量化）、不在範圍清單、安全約束；自驗依 workflow-base「🧪 驗證觸發條件」端到端原則（實際驅動被改流程，不只單元測試）
7. 回報格式：完成時 `SendMessage(to: "team-lead")` 附技術棧偵測結果、載入的 skill 清單、改動檔案、自驗結果
8. **停損與防空轉指令**（workflow-base「⛔ 停損原則」）：同一失敗連續 3 次修復未過 → 停修並 SendMessage 回報 Lead 裁決；TaskUpdate 被 hook 拒絕且自驗已通過 → 不反覆重試、不修改任何設定，直接 SendMessage 回報 Lead 調處（2026-07 實測：hook 拒絕回饋可能重複投遞，無此指令隊友會被反覆喚醒空轉）

> ⚠️ **不要在 prompt 裡寫死 skill 名稱**：teammate 的 agent 定義已要求自行偵測技術棧、動態載入 skill。

### 3. 溝通協定三鐵律（寫進每位 teammate 的 prompt）

1. **純文字輸出其他 agent 看不到**——跨 agent 溝通一律 `SendMessage`（訊息為字串時**必帶 `summary`**）；回報 Lead 用 `to: "team-lead"`，隊友互傳用 `to: "<name>"`（前端 / 行動端遇契約缺項直接找 `be-{feature}`，QA 失敗直接派修對應隊友，不必經 Lead）
2. **任務狀態一律 `TaskUpdate`**——更新前先 `TaskGet` 取最新狀態；想加任務用 `TaskCreate` + 適當 `addBlocks` / `addBlockedBy`
3. **完工 = 回報 + task completed + 自然結束回合**——idle 不是死亡，Lead 隨時可喚醒；**禁止**為「保持在線」sleep / 輪詢空轉

### 4. 監督與調度（事件驅動）

- 隊友完成 / idle / 失敗會**自動通知**——收到通知才行動，**不輪詢 TaskList**
- 收到完工回報 → 檢視、明確 ack（接受 / 拒絕 deviation）→ 派下一件事或讓它 idle
- 收到隊友提問（Mailbox）→ 處理後回覆
- 喚醒：運行中 / idle 用 `SendMessage(to: "<name>")`；已完成（通知顯示 completed）用 agentId；**永遠不要**對同名再 call `Agent`
- task 狀態偶爾滯後（官方已知限制）：疑似卡住時先 `TaskGet` 確認實際狀態，必要時代為更新並推隊友一把；`TaskGet` 的 `Blocked by` 列原始依賴（含已完成者），判斷可否認領以 `TaskList`（只列未解阻塞）為準
- 執行中需變更團隊編制、需求分類翻轉或動到藍圖外範圍 → 依 workflow-base「⚠️ 藍圖偏離處理」暫停，回報用戶 delta 藍圖，重新確認後續行
- 品質門可由 hooks 承擔（`TeammateIdle` / `TaskCreated` / `TaskCompleted`，exit 2 = 擋下並回饋），已配置者無需 Lead 手動把關同類問題
- 全部完成 →（可選）啟動 `cr-{feature}` 代碼審查 → 完成回報

### 5. 錯誤處理迴圈

QA 失敗時**優先讓隊友自主處理**：QA 依其定義自行分析失敗層級並 `SendMessage` 派修對應隊友，修復後 QA 重驗。派修循環受 workflow-base「⛔ 停損原則」約束：同一失敗連續 3 次修復未過 → 上報 Lead 裁決，不無限循環。Lead 只在以下情況介入：場景設計本身有問題、跨多端衝突、隊友卡住超過合理時間。

### 6. Dev server 生命週期

teammate 起的 background bash 綁在該 teammate 的 runtime 上，跨階段存活性沒有保證。**長活的 dev server / docker compose 建議由 Lead 在自己 session 起 background bash**；或讓 teammate 在回報中附啟動指令，由 Lead 決定是否代起。進 QA 階段前，Lead 確認雙端 server 實際在跑（`lsof` / `curl` 驗證，不要assume）。

### 7. 完成回報

**回報前先執行收尾雙檢**（依 `workflow-base.md`）：
1. 「📦 完成後沉澱檢查」——有可沉澱知識時在回報末尾提沉澱建議並詢問用戶
2. 「📋 CLAUDE.md 一致性檢查」——地圖漂移時加「📋 CLAUDE.md 更新建議」段

> ### ✅ 團隊任務完成報告
>
> **偵測結果**：[依藍圖記錄填入]
>
> **修改的檔案清單**
> - Backend（[實際偵測技術棧]）: [檔案列表]
> - Frontend（[實際偵測框架]）: [檔案列表]
> - Mobile / DevOps（若有）: [檔案列表]
>
> **測試結果**
> - 後端測試：[pass/fail 數量]；QA E2E：[PASS/FAIL]
>
> **API 契約變更**
> - 契約檔：`team/contracts/{feature}.api.md`；[新增 / 修改端點列表]
>
> **重要決策**（從 `team/decisions/{feature}.log.md` 摘錄）
>
> **各隊友偵測結果與載入的 Skill**（彙整自各隊友回報）

### 8. 收尾

**沒有清理步驟**——session 結束時 runtime 自動清理 team 目錄。若想提前優雅釋放某隊友，可發 `shutdown_request`（teammate 回 `shutdown_response { approve: true }` 後退出），非必要。

**⚠️ 關閉前先調處 task 狀態**（2026-07 實測）：隊友退出時其名下**未完成** task 會被自動取消指派（owner 清空），任務板留下無主的 in_progress。順序：先把該隊友的 task 標到正確狀態（completed / 重派），再發 `shutdown_request`。

---

## 🧭 Lead 心法（協調者紀律）

### 角色定位：你是協調者，不是執行者

| Lead 該做 | Lead 不該做 |
|---|---|
| 規劃藍圖、寫共享資源（contracts / scenarios） | **親自寫業務代碼**（那是 teammate 的事） |
| TaskCreate / 派工 / 收回報 / ack deviation | **親自跑 build / 測試 / kill server**（派工給隊友） |
| 監督進度、處理跨隊友衝突 | **親自做隊友已 in_progress 的工作** |
| Spec 不清時補充 / 調整 | **越過隊友 ownership 直接改它的代碼** |

**反例（已踩過）**：隊友卡住，Lead 直接 Bash kill process + 重啟 server（正解：SendMessage 派工）；隊友編輯到一半，Lead 看到 diagnostic error 就去修（正解：等隊友自己接續）。**自查**：每次想 call Bash / Edit / Write 前先問「這是不是某個 teammate 的 ownership？」是 → SendMessage 派工。

### 互動原則

- **idle 是常態，勿擾**：teammate 每回合結束都會 idle；idle ≠ 卡住 ≠ 完成。只在派新工或回應提問時 SendMessage
- **deviation 要明確 ack**：隊友偏離 spec 並附理由時，明確回「接受（理由）」或「拒絕（請改回）」；沉默會讓隊友不確定要不要改
- **CLAUDE.md 過時時相信代碼**：隊友抓出文檔與代碼不符 → 代碼是 source of truth，ack + 完成回報加「📋 CLAUDE.md 更新建議」

### Spec 寫作三原則（防 deviation）

1. **單一真相**：同一設定只寫一處明確值 + 理由（反例：一處寫 default true、另一處寫上線保 false → 隊友必選一個，你被迫接受 deviation）
2. **驗收量化**：❌「測試覆蓋核心路徑」→ ✅「`go test ./... -race` 全綠 + 新增 N 類測試：[列舉]」
3. **明確「不在範圍」**：列出本次絕不碰的端 / 模組 / 階段，防 scope creep

### 環境細節事先驗證

派工前先 grep / lsof / ps 驗證，別讓隊友撞牆才發現：dev server 在跑嗎、哪個 port；`.env` 改了會 reload 嗎（如 air 只 watch `*.go`）；docker 容器是否被其他專案借用 port；prod 與 local 版本是否一致（不一致要明確告知 QA 測哪邊）。

### /team vs /doit 決策

| 情況 | 工具 |
|---|---|
| 任務範圍明確、單一技術棧、可 surgical 解決 | `/doit` |
| 純 research 不寫代碼 | 直接 `Agent` spawn 研究型 subagent（不需 team） |
| 跨多端需要契約對齊 / 有獨立可並行任務 / 需要 QA E2E | `/team` |

**Token 成本警告**：`/team` 比 `/doit` 高 3–5 倍。需求分類沒做、純前端開了 team = 純粹浪費。

### Spawn 前 checklist

- [ ] 協作工具 schema 已載入（ToolSearch）？
- [ ] task list 設好 owner + blockedBy？owner 與 name 完全一致？
- [ ] 每個 teammate prompt 自包含（目錄、契約路徑、三鐵律、驗收標準、不在範圍）？
- [ ] 共享資源（contracts / scenarios / decisions）寫好了？
- [ ] Spec 單一真相、驗收量化？
- [ ] 環境細節驗證過（server / port / reload 機制）？
- [ ] 真的每個角色都需要嗎（純後端就別喚醒 fe / mobile）？
- [ ] Pre-flight 探針跑了嗎（新環境 / 版本更新後）？

---

## 🛡️ 已知限制與對應

以下摘自[官方文檔](https://code.claude.com/docs/zh-CN/agent-teams#limitations)（限制隨版本變動，遇到表外異常先回官方文檔對照最新版）：

| 限制（官方文檔載明） | 對應方式 |
|------|---------|
| in-process 隊友不支援 `/resume` / `/rewind` 還原 | 恢復 session 後隊友已不存在 → 重新 spawn，不要對舊 name 發訊息 |
| task 狀態可能滯後 | 疑似卡住先 TaskGet 確認實際，必要時 Lead 代更新 |
| 每 session 恰好一個 team、不可嵌套、Lead 固定 | 跨領域子任務由 Lead 拆，隊友不開 team |
| in-process 隊友不能起 background subagent | 隊友的並行需求由 Lead 層安排 |
| 權限模式在 spawn 時繼承 Lead | 常用操作先在權限設定預批，減少提示冒泡 |
| Token 成本明顯較高 | 「需求分類」必做，純前端絕不開 team |
| 訊息投遞可能延遲 / 失序；hook 拒絕回饋可能重複投遞喚醒隊友（2026-07 實測，非官方文檔項）| 隊友 prompt 必含防空轉指令（見 2-e 第 8 點）；Lead 收到「未收到裁決」類訊息先假設投遞延遲，重送一次即可，勿多發；狀態疑似滯後用 `TaskGet` 對賬 |

---

## 🆘 隊友定義缺失時

若 `~/.claude/agents/` 缺所需 subagent type：
1. 提示用戶可建立檔案（範本參考其他 `~/.claude/agents/*.md`）
2. 或退回 `/doit` 改由你親自處理
