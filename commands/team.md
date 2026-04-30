# Command: /team (Agent Team Workflow)

此指令啟動 **官方 Agent Team 多 Claude 實例協作模式**（Claude Code ≥ 2.1.32）。作為 **Team Lead**，你的職責是分析需求、制定團隊藍圖、用 `Agent` tool 配 `name:` + `run_in_background: true` spawn 出常駐隊友。每位隊友是獨立 Claude 實例，可彼此 `SendMessage` 直接對話、共享 task list、自動 idle 通知。

**⚠️ 核心原則：需求分類、契約優先、Mailbox 對話、品質門。** 嚴禁未獲用戶明確確認 (`Yes`/`Y`) 前啟動團隊。

**🔑 與 `/doit` 區別**：`/doit` 是單人 Tech Lead 模式（你親自編碼）；`/team` 是多 Claude 實例團隊模式（隊友自主協作，你監督調度）。

**⚠️ 啟動機制（重要，不要踩雷）**：
- ✅ **正確**：用 `Agent` tool spawn，必填 `name:`（讓隊友可被 `SendMessage` by name 喚醒）+ `run_in_background: true`（讓隊友不阻塞 Lead）+ `model:`（依藍圖填）+ `subagent_type:` + 帶足上下文的 `prompt:`
- ✅ **後續延續對話**：對「同一位」隊友後續派工用 `SendMessage(to: "<name>")`；**不要再 call `Agent` 起一次同名隊友**——那會建立全新 context 失去先前對話
- ❌ **錯誤**：把「請建立一個 agent team...」當作純文字輸出，期待 harness 自動 spawn——這只是文字，不會起任何隊友

---

## 前置條件（啟動前自檢）

| 條件 | 檢查方式 | 不滿足時 |
|------|---------|---------|
| Claude Code ≥ 2.1.32 | `claude --version` | 退回 `/doit` |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` | 看 `settings.json` 的 `env` | 提示用戶開啟 |
| `.claude/agents/` 存在通用隊友類型（`backend` / `frontend` / `mobile` / `qa` / `code-reviewer`） | `ls .claude/agents/` | 提示用戶補建或退回 `/doit` |

> **隊友類型是語言中立的角色**：`backend` 可能對應 Go / Python / Node / PHP / Ruby / Java / Rust，`frontend` 可能對應 React / Vue / Svelte / Astro 等，`mobile` 可能對應 iOS / Android / RN / Flutter。**實際載入哪個 skill 由隊友自己在啟動時偵測技術棧後動態匹配**，不在這裡寫死。

讀取 `.claude/shared/workflow-base.md` 取得專案偵測規則、Serena 工具使用規範與 Skill 對照表，然後執行專案偵測。

---

## 🚀 觸發邏輯

### 🟢 情境 A：用戶未提供具體需求

**判定**：用戶僅輸入 `/team`，後面沒有描述。

**行動**：
1. 執行專案偵測，展示偵測結果並詢問：

> **您好！我是您的 Team Lead，準備為您組建 Agent Team。**
>
> **🔎 偵測結果**：`[從 workflow-base 步驟 0 取得，包含偵測到的技術棧]`
> **🤝 可用隊友類型**：`[ls .claude/agents/ 列出，例：backend, frontend, mobile, qa, code-reviewer]`
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

8.  **過度設計檢查（MANDATORY，藍圖前最後一道）**：依 `workflow-base.md` 三題自審。

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

### 2. 啟動 Agent Team（兩階段：先建共享 task list，再 spawn 常駐隊友）

#### 2-a. 先載入協作工具

`SendMessage` / `TaskList` / `TaskCreate` / `TaskUpdate` / `TaskGet` 是 deferred tools，需要先用 `ToolSearch` 把 schema 拉進來才能呼叫：

```
ToolSearch query="select:SendMessage,TaskList,TaskCreate,TaskUpdate,TaskGet"
```

#### 2-b. 建立共享 task list（指派 owner + blockedBy）

依藍圖每階段建一個 epic task（不是把每個 sub-step 都拆出來；過細的 task 反而干擾隊友）。建議顆粒度：

- **後端**：1 個 epic + 1 個「補完 API 契約」 task（後者是獨立的 milestone，blocks 前端）
- **前端**：1 個 epic（blocked-by 契約 task）
- **行動端**：1 個 epic（blocked-by 契約 task，與前端並行）
- **QA**：1 個 epic（blocked-by 前端 / 行動端 epic）

每個 task 用 `TaskCreate` 建立後，立刻 `TaskUpdate` 設 `owner:` 與 `addBlockedBy:`。owner 字串必須與下一步即將 spawn 的隊友 `name:` 完全一致（例：`be-{feature}`）。

#### 2-c. 並行 spawn 常駐隊友

**用 `Agent` tool 一次發送多個 tool call** spawn 所有隊友（單一訊息多 tool call = 並行）。每個 spawn 必填：

| 參數 | 內容 |
|------|------|
| `subagent_type` | `backend` / `frontend` / `mobile` / `qa` |
| `name` | 與 task owner 字串完全一致（例 `be-{feature}`） |
| `model` | 依藍圖填（`opus` / `sonnet` / `haiku`） |
| `run_in_background` | **必填 `true`**——否則 Lead 會被阻塞、無法後續調度 |
| `prompt` | 自包含的隊友任務簡報，至少包含：本人名字、工作目錄、契約 / 場景 / 決策三檔絕對路徑、`TaskList` 後認領自己的 task、SSRF / 安全約束、idle 行為說明、回報格式 |

> ⚠️ **prompt 一定要自包含**：每個隊友是獨立 Claude 實例，看不到 Lead 的對話歷史。需要的所有上下文（路徑、約束、預設帳密策略、模型決策）都要寫進 prompt。

> ⚠️ **不要在 prompt 裡寫死 skill 名稱**：隊友 `.md` 已要求自行偵測技術棧、動態載入 skill。

#### 2-d. 期間如何延續對話

隊友 spawn 後會跑到 idle / 完成。**要派新任務或補資訊**：

- ✅ `SendMessage(to: "<name>", message: "...")` ── 同一個隊友 context 延續
- ❌ 再 call `Agent({name: "<name>", ...})` ── 起新實例、失去原 context

#### 2-e. 溝通協定（寫進每位隊友的 prompt）

- 前端 / 行動端遇契約缺項 → 直接 SendMessage 給 be-{feature}，不必經 Lead
- QA 失敗 → 由 qa-{feature} 自行分析並 SendMessage 派修對應隊友
- 任何隊友想加任務 → TaskCreate + 適當 addBlocks / addBlockedBy

#### 2-f. Dev server 生命週期（小雷）

`backend.md` / `frontend.md` 教隊友 idle 時自啟 dev server 在 background bash。但**那個 bash 綁在隊友 agent process 上**，agent 一結束（或 reaper 收）bash 也跟著死。因此：

- 若 QA 是「下一輪」才 spawn / 喚醒，Lead 進 QA 階段前要自己重啟雙端 server
- 或在隊友 prompt 中**改成回報 server 啟動指令而非自己啟動**，由 Lead 在自己 session 起 background bash（pid 不會隨子 agent 死）

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

### 6. 清理團隊（最後一步）

```
Clean up the team
```

> ⚠️ 必須由 Lead 執行清理。隊友不應執行清理。每個 session 一次只能管理一個 team，下次任務開始前要先清。

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

若 `.claude/agents/` 缺所需 subagent type：
1. 提示用戶可建立檔案（範本參考其他 .claude/agents/*.md）
2. 或退回 `/doit` 改由你親自處理
