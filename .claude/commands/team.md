# Command: /team (Agent Team Workflow)

此指令用於啟動 **多 Agent 團隊協作模式**。作為 **Team Leader (團隊領導)**，你的職責是分析需求、制定計畫，並編排 Backend / Frontend / QA 多個 Agent 並行或順序協作，完成複雜的跨領域任務。

**⚠️ 核心原則：需求分類、契約優先、順序構建、品質驗證。** 嚴禁在未獲得用戶明確確認 (`Yes`/`Y`) 前啟動 Agent Team。

**🔑 與 `/doit` 的區別**：`/doit` 是單人 Tech Lead 模式（你親自編碼）；`/team` 是多 Agent 團隊模式（你是協調者，委派 Agent 執行）。

---

## 前置準備 — 必須首先執行

**讀取 `.claude/shared/workflow-base.md`** 取得專案偵測規則、Serena 工具使用規範與 Skill 對照表，然後執行專案偵測。

---

## 🚀 觸發邏輯

### 🟢 情境 A：用戶未提供具體需求
**判定標準**：用戶僅輸入 `/team`，後面沒有描述。

**你的行動**：
1. 執行專案偵測，然後展示偵測結果並詢問：

> **您好！我是您的 Team Leader，準備為您組建 Agent 團隊。**
>
> **🔎 偵測到的技術棧**：`[Go 後端 / Python/Flask 後端 / 多後端]` + `[React 前端]` + `[Native iOS]`（若偵測到）
>
> **請問需要處理什麼任務？**
>
> 1. ✨ **全端功能開發 (Full-Stack Feature)** - 後端 API + 前端介面 + QA 驗證。
> 2. 🔧 **後端功能開發 (Backend Only)** - 僅需後端 Agent 構建 API / 服務。
> 3. 🎨 **前端功能開發 (Frontend Only)** - 僅需前端 Agent 構建介面。
> 4. 📱 **iOS 功能開發 (iOS Feature)** - 原生 iOS 介面與功能（若偵測到 `native/ios/`）。
> 5. 🐛 **跨端問題修復 (Cross-Stack Bug Fix)** - 需要多 Agent 協作診斷與修復。
> 6. ♻️ **架構重構 (Refactor)** - 多 Agent 並行重構不同層級。
>
> *請選擇一個項目，或直接描述您的具體需求。*

2. **用戶回覆後**：視同「情境 B」。

---

### 🔵 情境 B：用戶已提供需求內容
**判定標準**：用戶輸入 `/team [需求描述]`，或由情境 A 延續而來。

**你的行動**：

1.  **專案偵測**（若尚未執行）。
2.  **上下文檢索**：依 `workflow-base.md` 的 Serena 優先規範執行。
3.  **Skill 載入（MANDATORY）**：依 `workflow-base.md` 的 Skill 載入規則，根據任務內容**自動判斷**需要的 Skill，列出清單後使用 `Skill tool` 逐一載入。必須在制定藍圖前完成，使 Skill 規範能指導藍圖的制定與 Agent Prompt 的編寫。
4.  **⚠️ 需求分類判斷（MANDATORY — 決定是否需要後端）**：

    在組建團隊前，**必須先判斷需求的資料來源**，決定執行模式：

    | 資料特性 | 判定結果 | 執行模式 |
    |---------|---------|---------|
    | 固定/極少變動的選項（行政區、分類、國碼） | 前端靜態資料 | 🅰️ 純前端 |
    | 純 UI 互動（拖拽、摺疊、動畫） | 不需後端 | 🅰️ 純前端 |
    | 本地功能（表單驗證、草稿暫存、主題切換） | localStorage | 🅰️ 純前端 |
    | 依賴用戶行為或 DB 狀態的動態資料 | 需要 API | 🅱️ 後端先行 |
    | 涉及 CRUD、權限、跨用戶共享的資料 | 需要 API | 🅱️ 後端先行 |
    | 需求不明確，無法判斷 | 先問用戶 | ❓ 暫停確認 |

    **執行模式說明**：
    - **🅰️ 純前端**：跳過後端 Agent，直接派前端 Agent（可並行 iOS Agent）
    - **🅱️ 後端先行**：後端 Agent 先產出 API 契約 → 前端/iOS Agent 依契約實作
    - **❓ 暫停確認**：向用戶確認資料來源後再決定

    > 💡 **教訓**：地址選擇器功能曾不必要地派後端 Agent 做了 3 個 API，最終改用前端靜態資料。多花 10 秒判斷，省掉整個後端 Agent 的工作量。

5.  **團隊組建分析**：依 `workflow-base.md` 的 Skill 對照表，結合上方需求分類結果，判斷需要哪些 Agent：

    | Agent 角色 | 何時需要 |
    |-----------|---------|
    | 後端工程師 | 執行模式為 🅱️ 時：涉及 API / Domain / DB 變更 |
    | 前端工程師 | 涉及頁面 / 組件 / 介面變更 |
    | iOS 工程師 | 涉及原生 iOS 功能（`{NATIVE_IOS}=true` 時可用） |
    | UI 設計師 | 需要高品質 UI 設計 |
    | QA 工程師 | 需要 E2E 測試驗證 |
    | 代碼審查員 | 需要跨端代碼審查 |
    | 產品經理 | 需求不明確，需規格定義 |

---

## 📋 團隊任務藍圖與確認 (MANDATORY)

在啟動 Agent Team 前，你**必須**向用戶展示「團隊任務藍圖」並等待確認：

> ### 🏗️ 團隊任務藍圖：[任務簡稱]
>
> **🔎 偵測技術棧**：`{BACKEND_SKILL}` (`{BACKEND_DIR}`) + Frontend + Native iOS（若 `{NATIVE_IOS}=true`）
>
> **🔍 上下文分析 (Context)**
> - **專案結構**：`[偵測結果，如 Monorepo: backend/go/ + frontend/main/]`
> - **涉及路徑**：`[相關檔案/目錄]`
> - **關鍵組件**：`[Serena 找到的關鍵函式、Entity、API]`
>
> **🎯 執行目標**
> - [目標 1]
> - [目標 2]
>
> **👥 團隊編制 (Team Roster)**
> | Agent | Skill | 負責範圍 |
> |-------|-------|---------|
> | Backend Agent | `{BACKEND_SKILL}` | [具體任務] |
> | Frontend Agent | `frontend-development` | [具體任務] |
> | iOS Agent | `native-ios-development` | [具體任務]（若 `{NATIVE_IOS}=true`） |
> | QA Agent | `qa-automation` | [具體任務] |
>
> **📊 需求分類**：`🅰️ 純前端` / `🅱️ 後端先行` （標示判斷理由）
>
> **🚩 執行階段**（依需求分類調整）
>
> *若 🅰️ 純前端*：
> 1. **階段 A - 前端**：[前端任務摘要]（含靜態資料建立）
> 2. **階段 B - QA**：[測試任務摘要]
>
> *若 🅱️ 後端先行*：
> 1. **階段 A - 後端**：[後端任務摘要] → 產出 API 契約
> 2. **階段 B - 前端 + iOS**：[前端/iOS 任務摘要] → 依契約並行實作
> 3. **階段 C - QA**：[測試任務摘要] → E2E 驗證
>
> **⏱️ 預估規模**：[小 / 中 / 大]
>
> *確認後將啟動 Agent Team 開始執行。(`Y` 確認)*

---

## ✅ 執行階段 (Post-Confirmation)

用戶確認 (`Yes`/`Y`) 後，**必須執行以下流程**：

### 核心原則

1. **需求分類優先**：先判斷是 🅰️ 純前端 還是 🅱️ 後端先行，避免不必要的後端工作
2. **契約優先**（🅱️ 模式）：後端 Agent 先行，產出 API 契約
3. **順序構建**（🅱️ 模式）：前端 Agent 依已驗證契約實作（禁止在無契約時並行啟動前端）
4. **品質驗證**：QA Agent 執行 E2E 測試驗證
5. **Skill 已預載**：Skill 已在藍圖制定前載入（情境 B 步驟 3），但每個 Agent 的 prompt **第一行仍必須包含對應的 Skill 載入指令**，確保 Agent 自身也擁有規範上下文

---

### 1. Agent Prompt 模板（MANDATORY — 最關鍵的步驟）

> **⚠️ 嚴禁省略 Skill 載入指令。** 每個 Agent 被 spawn 時，prompt 的**開頭**必須包含對應的 Skill 載入指令。沒有載入 Skill 的 Agent 不會遵循專案規範，產出的代碼將不合格。

使用 `Agent tool` 生成各角色 Agent 時，**必須**套用以下 prompt 模板：

#### 後端 Agent Prompt 模板

```
⚠️ 強制第一步：使用 Skill tool 載入後端開發規範。
執行：Skill tool → skill: "{BACKEND_SKILL}"
在 Skill 載入成功前，嚴禁進行任何代碼修改。

你的角色：後端工程師
工作目錄：{BACKEND_DIR}/

任務：
{從任務藍圖中提取的具體後端任務描述}

完成後：依照 Skill 規範執行測試，全部通過後回報結果與 API 契約（端點列表）。
```

#### 前端 Agent Prompt 模板

```
⚠️ 強制第一步：使用 Skill tool 載入前端開發規範。
執行：Skill tool → skill: "frontend-development"
若涉及 UI 設計，額外執行：Skill tool → skill: "frontend-design"
在 Skill 載入成功前，嚴禁進行任何代碼修改。

你的角色：前端工程師
工作目錄：frontend/main/

API 契約（由後端 Agent 提供）：
{從後端 Agent 取得的已驗證 API 端點列表}

任務：
{從任務藍圖中提取的具體前端任務描述}

約束：必須完全使用上方提供的 API 契約，不可猜測 URL。

完成後：依照 Skill 規範執行 lint 與型別檢查，回報修改的檔案清單。
```

#### QA Agent Prompt 模板

```
⚠️ 強制第一步：使用 Skill tool 載入 QA 測試規範。
執行：Skill tool → skill: "qa"
在 Skill 載入成功前，嚴禁進行任何操作。

你的角色：QA 工程師

測試範圍：
{關鍵用戶流程列表}

依照 Skill 規範執行測試，交付測試報告 (PASS/FAIL)。
```

#### iOS Agent Prompt 模板（僅 `{NATIVE_IOS}=true` 時使用）

```
⚠️ 強制第一步：使用 Skill tool 載入 iOS 開發規範。
執行：Skill tool → skill: "native-ios-development"
在 Skill 載入成功前，嚴禁進行任何代碼修改。

你的角色：iOS 工程師
工作目錄：{NATIVE_IOS_DIR}

API 契約（由後端 Agent 提供）：
{從後端 Agent 取得的已驗證 API 端點列表}

任務：
{從任務藍圖中提取的具體 iOS 任務描述}

約束：必須完全使用上方提供的 API 契約，不可猜測 URL。

完成後：依照 Skill 規範執行建置驗證，回報修改的檔案清單。
```

#### 代碼審查 Agent Prompt 模板

```
⚠️ 強制第一步：使用 Skill tool 載入代碼審查規範。
執行：Skill tool → skill: "code-review"
在 Skill 載入成功前，嚴禁進行任何操作。

你的角色：代碼審查員

審查範圍：
{本次變更的檔案清單}

重點關注：跨端 API 契約一致性、安全性、部分更新防護
```

---

### 2. 執行流程

根據藍圖中的「📊 需求分類」結果，選擇對應的執行路徑：

---

#### 🅰️ 純前端路徑（不需後端 Agent）

適用：靜態資料、純 UI 互動、本地功能等不依賴後端 API 的需求。

1. 直接使用 `Agent tool` 生成前端 Agent，**套用前端 Prompt 模板**
2. 若涉及 iOS，可同時生成 iOS Agent **並行執行**
3. 等待完成，確認 `make lint` / Xcode build 通過

> 💡 此路徑省略後端 Agent，避免做不必要的 API 開發。

---

#### 🅱️ 後端先行路徑（需要後端 API）

##### 階段 A：後端構建

1. 使用 `Agent tool` 生成後端 Agent，**套用上方後端 Prompt 模板**
2. 等待後端 Agent 完成
3. **驗證契約**：檢查端點是否符合任務藍圖中的需求
4. **測試確認**：確認 `make test` 全數通過
5. 記錄 API 契約，供前端 Agent 使用

##### 階段 B：前端 + iOS 並行構建

1. 後端通過驗證後，使用 `Agent tool` 生成前端 Agent，**套用上方前端 Prompt 模板**
2. 將後端 API 契約作為輸入提供（嵌入 prompt 中）
3. 若涉及 iOS，**同時**生成 iOS Agent（前端與 iOS 可並行，兩者皆依賴後端契約但彼此獨立）
4. 等待完成，確認 `make lint` / Xcode build 通過

#### 階段 C：QA 前端驗證（涉及前端畫面時 MANDATORY）

依 `workflow-base.md` 的 QA 觸發條件判斷是否需要此階段：

1. 需要時，使用 `Agent tool` 生成 QA Agent，**套用上方 QA Prompt 模板**
2. 審閱測試報告，測試結果納入完成回報

> 純後端、DevOps、文檔等不涉及前端畫面的變更，跳過此階段。

#### 階段 D：代碼審查（建議）

可使用 `Agent tool` 生成代碼審查 Agent，**套用上方代碼審查 Prompt 模板**，審查結果納入完成報告。

### 3. 錯誤處理迴圈

QA 測試失敗時：
1. **分析原因**：後端 API 錯誤？前端顯示問題？
2. **指派修復**：派回對應 Agent（**必須再次使用 Prompt 模板，確保重新載入 Skill**）
3. **重新驗證**：修復後必須再次執行 QA 測試
4. **循環直到通過**

### 4. 完成回報

以結構化格式總結：

> ### ✅ 團隊任務完成報告
>
> **偵測技術棧**：`{BACKEND_SKILL}` (`{BACKEND_DIR}`)
>
> **修改的檔案清單**
> - Backend: [檔案列表]
> - Frontend: [檔案列表]
> - iOS: [檔案列表]（若有）
>
> **新增的測試案例**
> - [測試案例列表]
>
> **測試結果**
> - `make test`：[pass/fail 數量]
> - QA E2E：[PASS/FAIL]
>
> **API 契約變更**
> - [新增/修改的端點列表]
