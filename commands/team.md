---
description: Agent Team 工作流程 — TeamCreate 多隊友協作，契約優先 + QA 驗證
argument-hint: [需求描述]
---

# Command: /team (Agent Team Workflow)

此指令啟動 **官方 Agent Team 多 Claude 實例協作模式**（Claude Code ≥ 2.1.32）。作為 **Team Lead**，你的職責是分析需求、制定團隊藍圖、**先 `TeamCreate` 建立 team，再用 `Agent`（在 team context 內 / 或帶 `team_name`）spawn 出 teammate**。每位 teammate 是獨立 Claude Code session，自動取得 `SendMessage` / `TaskList` / `TaskCreate` / `TaskUpdate` / `TaskGet` 協作工具，可彼此 `SendMessage` 直接對話、共享 task list、自動 idle 通知。

**⚠️ 核心原則：需求分類、契約優先、Mailbox 對話、品質門。** 嚴禁未獲用戶明確確認 (`Yes`/`Y`) 前啟動團隊。

**🔑 與 `/doit` 區別**：`/doit` 是單人 Tech Lead 模式（你親自編碼）；`/team` 是多 Claude 實例團隊模式（teammate 自主協作，你監督調度）。

**⚠️ 啟動機制（4 步順序，不可跳過）**：
1. **`TeamCreate`** 建立 team — 建立 `~/.claude/teams/{team-name}/` 與對應 task list 目錄。**這是讓後續 spawn 出的 entity 變成 teammate（而非單向 subagent）的前置條件**。
2. **`TaskCreate` × N** 建立任務（自動綁進這個 team 的 task list），用 `TaskUpdate` 設 `owner` + `addBlockedBy`。
3. **`Agent`** spawn teammate — 必填 `name:`（要與 task `owner` 完全一致）+ `subagent_type:` + `model:` + 帶足上下文的 `prompt:`。**只要 Lead session 在 team context 內，spawn 出的就是 teammate**（不必顯式傳 `team_name`，runtime 自動繼承 current team）。回應格式 `agent_id: name@team-name` 即確認為 teammate。
4. **`SendMessage(to: "<name>")`** 後續派工 — teammate 是常駐 Claude session，by-name 喚醒會延續原 context；**不要再 call `Agent({name: "<name>"})`**，那會起新實例丟失對話。

**🔑 致命陷阱（之前踩過的雷）**：
- ❌ 跳過第 1 步直接呼叫 `Agent` → 起的是 **subagent 而非 teammate**，subagent runtime 完全沒有 SendMessage / TaskList 等協作工具，無法 mailbox 對話、無法操作共享 task list，整個 team workflow 假死
- 區分方式：spawn 回應若是 `agentId: <hash>` → subagent 啟動失敗；若是 `agent_id: <name>@<team>` → teammate 正確

---

## 前置條件（啟動前自檢）

| 條件 | 檢查方式 | 不滿足時 |
|------|---------|---------|
| Claude Code ≥ 2.1.32 | `claude --version` | 退回 `/doit` |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` | 看 `settings.json` 的 `env` | 提示用戶開啟 |
| `~/.claude/agents/` 存在通用隊友類型（`backend` / `frontend` / `mobile` / `qa` / `code-reviewer`） | `ls ~/.claude/agents/` | 提示用戶補建或退回 `/doit` |
| 終端環境（cmux / tmux / Claude 原生）spawn backend 可用 | 見下方「🖥️ 終端環境偵測」 | cmux 缺 shim → 停手要用戶重啟；其他環境直接繼續 |

---

## 🖥️ 終端環境偵測（MANDATORY，前置條件後立即執行）

`/team` 的 teammate 是用 Claude Code 內建 spawn 機制建立的，**底層 backend 隨終端環境變化**。Lead 啟動前必須先偵測，三種環境都是合法的 agent team 啟動方式，不需要降級或魔改：

### 偵測指令（一次 Bash 取得三件事）

```bash
echo "CMUX=${CMUX_AGENT_LAUNCH_KIND:-no}"  # cmux 環境會輸出 "claude"
echo "TMUX=${TMUX:+yes}"                    # tmux session 內會輸出 "yes"
which tmux 2>/dev/null                       # 看 tmux 路徑（cmux shim vs 系統）
```

### 環境矩陣與啟動方式

| 環境 | 偵測訊號 | spawn backend | Lead 行為 |
|------|---------|--------------|----------|
| **① cmux**（teams 模式） | `CMUX_AGENT_LAUNCH_KIND=claude` ∧ `which tmux` 路徑含 cmux 暫存目錄（非 `/opt/homebrew/bin/tmux` 等系統路徑） | cmux split（tmux shim 翻譯） | 走標準 4 步流程 |
| **① cmux**（shim 未就位） | `CMUX_AGENT_LAUNCH_KIND=claude` ∧ `which tmux` 是系統 tmux 路徑 | ❌ spawn 失敗（會建出孤兒 tmux pane） | **立即停手**，依下方「cmux 未就緒復原訊息」回覆用戶 |
| **② tmux** | 無 `CMUX_*` 變數 ∧ `$TMUX` 非空 | tmux pane | 走標準 4 步流程 |
| **③ Claude 原生** | 無 `CMUX_*` 變數 ∧ 無 `$TMUX` | Claude Code 內建（依版本而定） | 走標準 4 步流程 |

### cmux 未就緒復原訊息（情況 ①\* 專用）

偵測到「cmux 環境但 tmux shim 未就位」時，**禁止繼續往下走**（會 spawn 出無回應的 teammate），直接回覆用戶：

> ⚠️ **偵測到 cmux 終端，但目前 Claude 不是用 cmux teams 模式啟動。**
>
> 證據：
> - `CMUX_AGENT_LAUNCH_KIND=claude` ✓
> - `which tmux` = `<實際路徑>`（系統 tmux，非 cmux shim）
>
> 在此狀態下 spawn 出的 teammate 不會跑在 cmux session 內，會永遠不回應。請依以下指令重啟：
>
> ```bash
> # 1. 退出當前 Claude（Ctrl+D 或 /exit）
> # 2. 用 cmux 包裝的 teams 模式重啟並接回原對話
> cmux claude-teams --continue
> ```
>
> 重啟後 PATH 上會自動有 cmux 的 tmux shim，再下 `/team` 即可正常 spawn teammate。

### 啟動指令對照（供用戶參考）

| 想用 | 啟動方式 |
|------|---------|
| cmux + agent team | `cmux claude-teams [--continue]` |
| 原生 tmux + agent team | 先 `tmux new -s mywork`，內部 `claude` |
| Claude 原生 agent team | 直接 `claude`（無 tmux / 無 cmux） |

> **隊友類型是語言中立的角色**：`backend` 可能對應 Go / Python / Node / PHP / Ruby / Java / Rust，`frontend` 可能對應 React / Vue / Svelte / Astro 等，`mobile` 可能對應 iOS / Android / RN / Flutter。**實際載入哪個 skill 由隊友自己在啟動時偵測技術棧後動態匹配**，不在這裡寫死。

讀取 `~/.claude/shared/workflow-base.md` 取得專案偵測規則、Serena 工具使用規範與 Skill 對照表，然後執行專案偵測。

---

## 🚀 觸發邏輯

### 🟢 情境 A：用戶未提供具體需求

**判定**：用戶僅輸入 `/team`，後面沒有描述。

**行動**：
1. 執行專案偵測，展示偵測結果並詢問：

> **您好！我是您的 Team Lead，準備為您組建 Agent Team。**
>
> **🔎 偵測結果**：`[從 workflow-base 步驟 0 取得，包含偵測到的技術棧]`
> **🤝 可用隊友類型**：`[ls ~/.claude/agents/ 列出，例：backend, frontend, mobile, qa, code-reviewer]`
>
> **請問需要處理什麼任務？**
>
> 1. ✨ **全端功能開發** - 後端 API + 前端介面 + QA 驗證
> 2. 🔧 **後端功能開發** - 僅後端
> 3. 🎨 **前端功能開發** - 僅前端
> 4. 📱 **iOS 功能開發** - 原生 iOS
> 5. 🐛 **跨端問題修復** - 多隊友協作診斷與修復
> 6. ♻️ **架構重構** - 多隊友並行重構
>
> *請選擇一個項目，或直接描述您的具體需求。*

2. **用戶回覆後**：進入情境 B 流程，但**跳過步驟 2（專案偵測）**，沿用情境 A 結果。

---

### 🔵 情境 B：用戶已提供需求

**判定**：用戶輸入 `/team [需求描述]`，或由情境 A 延續。

**行動**：

1.  **任務類型分流（MANDATORY）**：依 `workflow-base.md` 判定 Code / Config / Docs / Trivial。
2.  **專案偵測**：依 `workflow-base.md` 執行（情境 A 已執行則跳過）。
3.  **上下文檢索**：依 `workflow-base.md` 按任務類型挑工具。
4.  **Skill 載入（給 Lead 用）**：先載入 `karpathy-guidelines`，再依任務內容自動匹配。**注意**：Lead 載入的 Skill **不會繼承給隊友**，每個隊友的 subagent 定義中已要求自行載入。
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
    | 🅱️ 模式：API / Domain / DB 變更 | `backend`（語言中立，隊友自己偵測 Go / Python / Node …） |
    | 涉及頁面 / 組件 / 介面 | `frontend`（框架中立，隊友自己偵測 React / Vue …） |
    | 涉及行動端（任意平台） | `mobile`（平台中立，隊友自己偵測 iOS / Android / RN …） |
    | 涉及前端畫面，需要 E2E 驗證 | `qa` |
    | 任務中等以上複雜度 | `code-reviewer`（最後階段啟動） |

    **規模建議**：3–5 位隊友最佳。每位隊友 5–6 個 task 為理想負載。

7.  **🛰️ 技術棧偵測（MANDATORY，啟動 team 前）**：

    Lead 在組建團隊**之前**必須完成：
    - 確認從 CLAUDE.md / 標誌檔取得的後端目錄、前端目錄、行動端目錄（依任務需要）
    - 不需要列出每個目錄的具體語言（隊友會自己偵測），但要把**目錄絕對路徑**準備好填入啟動指令
    - 若專案僅有單一技術棧子目錄（例：純前端站、純後端 API）→ 在藍圖中明示，避免用戶困惑為何沒派 backend / frontend

8.  **🔌 MCP 工具偵測**：依 `workflow-base.md`「🔌 MCP 工具動態偵測」掃描可用 MCP、匹配任務，結果納入藍圖，並在各隊友啟動 prompt 中標注分配給該隊友的 MCP 工具。
9.  **過度設計檢查（MANDATORY，藍圖前最後一道）**：依 `workflow-base.md` 三題自審。

---

## 📋 團隊任務藍圖與確認 (MANDATORY)

啟動 Agent Team 前，**必須**向用戶展示「團隊任務藍圖」並等待確認：

> ### 🏗️ 團隊任務藍圖：[任務簡稱]
>
> **🔎 偵測結果**：[技術棧 / 子專案 / 工作目錄]
> **📌 任務類型**：[Code / Config / Docs / Trivial]
>
> **🔍 上下文分析**
> - **專案結構**：[Monorepo: backend/go/ + frontend/web/ ...]
> - **涉及路徑**：[相關檔案 / 目錄]
> - **關鍵組件**：[Serena 找到的關鍵函式 / Entity / API]
>
> **🎯 執行目標**
> - [目標 1]
> - [目標 2]
>
> **👥 團隊編制 (Team Roster)**
>
> | 隊友名稱 | Subagent Type | 工作目錄（依本次偵測填入） | 模型 |
> |---------|--------------|--------------------------|------|
> | `be-{feature}` | `backend` | `[偵測到的後端目錄絕對路徑]` | opus |
> | `fe-{feature}` | `frontend` | `[偵測到的前端目錄絕對路徑]` | opus |
> | `mb-{feature}` | `mobile` | `[偵測到的行動端目錄絕對路徑]` | opus |（若有）
> | `qa-{feature}` | `qa` | — | opus |
> | `cr-{feature}` | `code-reviewer` | — | opus |（最後階段，可選）
>
> > 隊友會在啟動時自行偵測技術棧並動態匹配 skill，**這裡不寫死語言**。
>
> **🔌 MCP 工具**（動態偵測結果，僅列相關的）
> - `[mcp名稱]` — [用途]（分配給：[隊友名稱]）
>
> **📊 需求分類**：`🅰️ 純前端` / `🅱️ 後端先行` （標示判斷理由）
>
> **🚩 共享 Task List 結構**
>
> *🅰️ 純前端範例*：
> - 階段 A（owner: `fe-{feature}`）：[任務列表]
> - 階段 B（owner: `qa-{feature}`，blocked-by: 階段 A）：[任務列表]
>
> *🅱️ 後端先行範例*：
> - 階段 A（owner: `be-{feature}`）：契約設計 → 實作 → 測試
> - 階段 B（owner: `fe-{feature}`，blocked-by: 階段 A 契約任務）：依契約實作
> - 階段 C（owner: `qa-{feature}`，blocked-by: 階段 B）：E2E 驗證
>
> **🔗 隊友溝通協定（Blackboard + Mailbox）**
> - **契約檔**：`team/contracts/{feature}.api.md` （後端寫，前端 / iOS 讀）
> - **場景檔**：`team/scenarios/{feature}.qa.md` （Lead 寫，QA 讀）
> - **決策日誌**：`team/decisions/{feature}.log.md` （任何隊友可寫）
> - **跨隊友訊息**：用 `SendMessage` 直接溝通，不需經 Lead
>
> **⏱️ 預估規模**：[小 / 中 / 大]
>
> *確認後將以 Team Lead 身份啟動 Agent Team。(`Y` 確認)*

---

## ✅ 執行階段 (Post-Confirmation)

用戶確認後，**作為 Team Lead 依序執行**：

### 1. 準備共享資源

- 確認 `team/contracts/`、`team/scenarios/`、`team/decisions/` 存在（不存在則建立）
- 撰寫 QA 場景檔 `team/scenarios/{feature}.qa.md`（從藍圖目標展開為可驗證的用戶流程清單）
- 若 🅱️ 模式：在 `team/contracts/{feature}.api.md` 留好骨架（標題 + 預期端點清單），後端隊友據此補完

### 2. 啟動 Agent Team（4 步順序執行，不可跳過任一步）

#### 2-a. 載入協作工具到 Lead session

`TeamCreate` / `SendMessage` / `TaskList` / `TaskCreate` / `TaskUpdate` / `TaskGet` / `TeamDelete` 是 deferred tools，先把 schema 拉進來：

```
ToolSearch query="select:TeamCreate,SendMessage,TaskList,TaskCreate,TaskUpdate,TaskGet,TeamDelete"
```

#### 2-b. **`TeamCreate` 建立 team（關鍵步驟，跳過會整個崩盤）**

```
TeamCreate {
  team_name: "<feature>-team",   // 例：quote-force-team；用 kebab-case
  description: "本次任務目的的一句話",
  agent_type: "team-lead"
}
```

成功會回傳 `team_file_path: ~/.claude/teams/<name>/config.json` + `lead_agent_id: team-lead@<name>`。**Lead session 自此進入 team context，後續 TaskCreate / Agent 自動使用該 team**。

> ⚠️ 沒做這步直接 `Agent`，spawn 出來的是 subagent（無協作工具），整個 workflow 假死。這是 v1/v2 已經踩過的雷。

#### 2-c. 建立共享 task list（指派 owner + blockedBy）

依藍圖每階段建一個 epic task（不要把每個 sub-step 都拆出來；過細的 task 反而干擾 teammate）。建議顆粒度：

- **後端**：1 個 epic + 1 個「補完 API 契約」 task（後者是獨立的 milestone，blocks 前端）
- **前端**：1 個 epic（blocked-by 契約 task）
- **行動端**：1 個 epic（blocked-by 契約 task，與前端並行）
- **QA**：1 個 epic（blocked-by 前端 / 行動端 epic）

每個 task 用 `TaskCreate` 建立後，立刻 `TaskUpdate` 設 `owner:` 與 `addBlockedBy:`。owner 字串必須與下一步即將 spawn 的 teammate `name:` 完全一致（例：`be-{feature}`）。

#### 2-d. 並行 spawn teammate（用 Agent tool，但這次是在 team context 內）

**用 `Agent` tool 一次發送多個 tool call** spawn 所有 teammate（單一訊息多 tool call = 並行）。每個 spawn 必填：

| 參數 | 內容 |
|------|------|
| `subagent_type` | `backend` / `frontend` / `mobile` / `qa` |
| `name` | 與 task owner 字串完全一致（例 `be-{feature}`） |
| `model` | 依藍圖填（`opus` / `sonnet` / `haiku`） |
| `run_in_background` | **必填 `true`**——否則 Lead 會被阻塞、無法後續調度 |
| `prompt` | 自包含的 teammate 任務簡報，至少包含：本人名字、工作目錄、契約 / 場景 / 決策三檔絕對路徑、`TaskList` 後認領自己的 task、SSRF / 安全約束、idle 行為說明、回報格式 |

> ⚠️ **回應格式驗證**：spawn 後 runtime 回應必須是 `agent_id: <name>@<team-name>`（例：`be-quote-force@quote-force-team`）。若回應是 `agentId: <hash>` → 你**沒在 team context 內**或**忘了 TeamCreate**，spawn 出來的是 subagent，立即停手檢查。

> ⚠️ **prompt 一定要自包含**：每個 teammate 是獨立 Claude session，看不到 Lead 的對話歷史。需要的所有上下文（路徑、約束、預設帳密策略、模型決策）都要寫進 prompt。

> ⚠️ **不要在 prompt 裡寫死 skill 名稱**：teammate `.md` 已要求自行偵測技術棧、動態載入 skill。

#### 2-e. 期間如何延續對話

teammate spawn 後跑到 idle / 完成（idle 是常態，不是錯誤）。**要派新任務或補資訊**：

- ✅ `SendMessage(to: "<name>", message: "...")` ── 同一個 teammate context 延續，by-name 喚醒
- ❌ 再 call `Agent({name: "<name>", ...})` ── 起全新實例、丟失原 context

#### 2-f. 溝通協定（寫進每位 teammate 的 prompt）

- teammate 在 team context 內**自動有** SendMessage / TaskList / TaskCreate / TaskUpdate / TaskGet — 不必教它們 ToolSearch
- 前端 / 行動端遇契約缺項 → 直接 SendMessage 給 be-{feature}，不必經 Lead
- QA 失敗 → 由 qa-{feature} 自行分析並 SendMessage 派修對應隊友
- 任何 teammate 想加任務 → TaskCreate + 適當 addBlocks / addBlockedBy

#### 2-g. Dev server 生命週期（小雷）

`backend.md` / `frontend.md` 教 teammate idle 時自啟 dev server 在 background bash。但**那個 bash 綁在 teammate process 上**，teammate 一結束（或 reaper 收）bash 也跟著死。因此：

- 若 QA 是「下一輪」才 spawn / 喚醒，Lead 進 QA 階段前要自己重啟雙端 server
- 或在 teammate prompt 中**改成回報 server 啟動指令而非自己啟動**，由 Lead 在自己 session 起 background bash（pid 不會隨子 agent 死）

### 3. 監督與調度

- 用 `TaskList` 定期檢查進度
- 收到隊友 idle 通知 → 確認任務完成、檢視回報
- 收到 Mailbox 訊息（隊友需要 Lead 介入）→ 處理後回覆
- 全部完成 → （可選）啟動 `cr-{feature}` 跑代碼審查 → 撰寫完成回報 → **清理團隊**

### 4. 錯誤處理迴圈

QA 失敗時，**優先讓隊友自主處理**：
- QA 隊友依其定義會自己 SendMessage 派回對應隊友
- Lead 只在以下情況介入：場景設計本身有問題、跨多端的衝突、隊友卡住超過合理時間

需要 Lead 介入時：
- 用 `SendMessage(to: "<name>", message: "...")` 直接派任務給**仍可被 by-name 喚醒的**已存在隊友（避免失去上下文）
- 隊友 idle 之後 SendMessage 仍能投遞到 inbox，下次它被喚醒時看到
- **不要**再 call `Agent({name: "<name>", ...})`——那會 spawn 全新實例、丟掉所有先前對話
- 修復後讓 QA 隊友重跑驗證（同樣用 SendMessage 喚醒）

### 5. 完成回報

**回報前先執行**：依 `workflow-base.md`「📋 CLAUDE.md 一致性檢查」對照本次變更，找出地圖漂移時加「📋 CLAUDE.md 更新建議」段。

> ### ✅ 團隊任務完成報告
>
> **偵測結果**：[依藍圖中記錄的偵測結果填入]
>
> **修改的檔案清單**
> - Backend（[偵測到的技術棧]）: [檔案列表]
> - Frontend（[偵測到的框架]）: [檔案列表]
> - Mobile（[偵測到的平台]）: [檔案列表]（若有）
>
> **新增的測試案例**
> - [測試案例列表]
>
> **測試結果**
> - `make test`：[pass/fail 數量]
> - QA E2E：[PASS/FAIL]
>
> **API 契約變更**
> - 契約檔：`team/contracts/{feature}.api.md`
> - [新增 / 修改的端點列表]
>
> **重要決策**（從 `team/decisions/{feature}.log.md` 摘錄）
> - [決策列表]
>
> **各隊友偵測結果與載入的 Skill**（彙整自各隊友回報）
> - be-{feature}（後端：[實際偵測技術棧]）: [skill 清單]
> - fe-{feature}（前端：[實際偵測框架]）: [skill 清單]
> - mb-{feature}（行動端：[實際偵測平台]）: [skill 清單]（若有）
> - qa-{feature}: [skill 清單]
> - cr-{feature}: [skill 清單]（若有）

### 6. 清理團隊（最後一步，2 段流程）

#### 6-a. 對每位 teammate 發 `shutdown_request`

```
SendMessage {
  to: "<teammate-name>",
  message: { type: "shutdown_request", reason: "task completed" }
}
```

teammate 收到後 idle 並回 `shutdown_response { approve: true }`，然後優雅退出。每位都要單獨發一次。

#### 6-b. `TeamDelete` 移除 team 目錄

```
TeamDelete {}
```

無參數（會用 current team context）。會清掉 `~/.claude/teams/<name>/` 與 `~/.claude/tasks/<name>/`。

> ⚠️ **TeamDelete 會在仍有 active teammate 時失敗** — 必須先全部 shutdown。
> ⚠️ 必須由 Lead 執行清理。Teammate 不應執行清理。每個 session 一次只能管理一個 team，下次任務開始前要先清。

---

## 🛡️ 已知限制與對應

| 限制 | 對應方式 |
|------|---------|
| 每 session 只能一個 team | 每次 `/team` 結尾必須清理 |
| 不能巢狀 team（隊友不能再開 team） | 跨領域子任務由 Lead 拆，不要讓隊友自開 team |
| `/resume` 不還原 in-process 隊友 | 長任務建議 tmux 模式 |
| Token 成本明顯較高 | 「需求分類」必做，純前端絕對不開 team |
| Project-level team config 不存在 | 隊員配置每次由 Lead 動態建立，不能預先 hardcode |

---

## 🆘 隊友定義缺失時

若 `~/.claude/agents/` 缺所需 subagent type：
1. 提示用戶可建立檔案（範本參考其他 ~/.claude/agents/*.md）
2. 或退回 `/doit` 改由你親自處理
