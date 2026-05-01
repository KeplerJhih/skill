---
name: agent-team
description: Build a project using a coordinated Backend + Frontend + QA agent team. Takes a plan content string. Enforces contract-first development and comprehensive QA.
argument-hint: [plan-content]
color: green
---

# 建立 Agent 團隊進行構建 (Build with Agent Team) - 後端 + 前端 + QA

你是 **領導 Agent (Lead Agent / Team Lead)**，負責協調專案構建。你的目標是編排一個 **後端 teammate**、一個 **前端 teammate** 和一個 **QA teammate** 來構建與驗證計畫中描述的系統。

> ⚠️ **正確啟動順序（必讀）**：本 skill 只描述各角色職責；具體 4 步啟動順序見 `.claude/commands/team.md`：
> 1. `TeamCreate` 建立 team（**沒做這步，後面 spawn 出來的是 subagent，整個 workflow 假死**）
> 2. `TaskCreate` × N 建任務 + `TaskUpdate owner` 指派
> 3. `Agent` spawn teammate（必填 `name:` 與 task owner 對齊；spawn 回應應為 `agent_id: <name>@<team-name>`）
> 4. `SendMessage` 後續派工 / 收完工通知
> 收尾：對每位 teammate 發 `shutdown_request` → `TeamDelete`

## 參數 (Arguments)
- **計畫內容**: `$ARGUMENTS[0]` - 一段詳細描述功能需求、資料模型與步驟的純文字字串 (Markdown 格式)。
- 計畫內容中**必須**包含 `{BACKEND_SKILL}` 和 `{BACKEND_DIR}`（由 `/team` 指令偵測後傳入）。

## 專案偵測結果解讀

從 `$ARGUMENTS[0]` 中提取以下變數，用於決定後端 Agent 的配置：

| 變數 | 值範例 | 用途 |
|------|--------|------|
| `{BACKEND_SKILL}` | `backend-development-go` 或 `backend-development-python` | 後端 Agent 載入的 Skill |
| `{BACKEND_DIR}` | `backend/go` 或 `backend/python` | 後端工作目錄與測試執行路徑 |

若計畫內容未包含偵測結果，使用 Glob 工具自行偵測：
- `go.mod` 或 `backend/go/` → Go 後端
- `requirements.txt` + `wsgi.py` 或 `backend/python/` → Python/Flask 後端

## Skill 載入規則

各 Agent 必須透過 `Skill tool` 載入對應 Skill，使其規則強制生效。

- **自動判斷**：根據任務內容，從系統提供的可用 Skill 清單中自動匹配需要的 Skill
- **列出清單**：載入前列出將載入的 Skill，讓用戶知道
- **逐一載入**：使用 `Skill tool` → `skill: "<skill-name>"` 載入

## 核心理念：契約優先與品質保證 (Contract-First & QA)

你必須強制執行 **契約優先** 的工作流程，並在最後確保 **品質驗證**。

1. **後端 (Backend)** 先行構建並定義 API 契約 (Swagger/OpenAPI)。
2. **你 (領導)** 驗證該契約。
3. **前端 (Frontend)** 後續構建，使用 *已驗證* 的契約。
4. **QA (Quality Assurance)** 最後介入，進行端到端 (E2E) 測試驗證。

## 步驟 1：分析計畫 (Analyze the Plan)

閱讀 `$ARGUMENTS[0]` 傳入的計畫內容。理解功能、資料模型與用戶流程。
**提取 `{BACKEND_SKILL}` 和 `{BACKEND_DIR}`**，確認後端技術棧。
(注意：此步驟不需讀取外部檔案，直接分析參數內容)

## 步驟 2：設置團隊環境 (Set Up Team Environment)

1. 啟用 tmux 分割視窗：`teammateMode: "tmux"`
2. 進入 **委派模式 (Delegate Mode)** (Shift+Tab)。你是協調者，不是編碼者。

## 步驟 3：執行構建 (順序階段)

### 階段 A：後端 Agent (Backend Agent)

生成 **後端 Agent** 並給予以下指示：

1. **角色**：後端工程師。
2. **強制技能**：使用 `Skill tool` → `{BACKEND_SKILL}` 載入後端開發規範。
3. **任務**：
    - 根據計畫內容 (`$ARGUMENTS[0]`) 實作後端。
    - 嚴格遵循 `{BACKEND_SKILL}` Skill 中定義的 DDD 架構、技術堆疊與編碼規則。
    - **交付物**：一個運行中的伺服器，附帶 Swagger/OpenAPI 文檔。
    - **輸出**：向你發布 API 契約 (OpenAPI JSON 或精確的端點列表)。

**你的工作 (領導)：**
- 等待後端 Agent 完成。
- **驗證契約**：檢查實作的端點是否符合計畫需求。
- **約束檢查**：依據偵測到的技術棧驗證：
  - Go 後端：Gin, Viper, GORM, DDD 分層, `cd backend/go && make test` 通過
  - Python 後端：Flask, SQLAlchemy, DDD 分層, `cd backend/python && make test` 通過

### 階段 B：前端 Agent (Frontend Agent)

一旦後端準備就緒且契約經過驗證，生成 **前端 Agent**：

1. **角色**：前端工程師。
2. **強制技能**：使用 `Skill tool` → `frontend-development` 載入前端開發規範。若涉及 UI 設計，額外載入 `Skill tool` → `frontend-design`。
3. **輸入**：提供來自階段 A 的 **已驗證 API 契約**。
4. **任務**：
    - 實作前端介面。
    - 遵循 `frontend-development` Skill 中的 RWD 回應式設計與組件指南。
    - **約束**：必須完全使用提供的 API 契約 (不可猜測 URL)。

## 步驟 4：驗證與整合 (Validation & Integration)

### 階段 C：QA Agent (Quality Assurance)

當前端與後端都準備就緒且服務運行中，生成 **QA Agent**：

1. **角色**：QA 工程師。
2. **強制技能**：使用 `Skill tool` → `qa-automation` 載入 QA 測試規範。
3. **輸入**：計畫內容 (`$ARGUMENTS[0]`) 與前端/後端服務 URL。
4. **任務**：
    - 執行 E2E 測試驗證關鍵流程。
    - 使用 Chrome DevTools MCP 工具模擬用戶操作。
    - **交付物**：測試報告 (PASS/FAIL)。

### 階段 D：錯誤處理與修復 (Error Handling & Fix)

一旦 **QA Agent** 完成測試並回報結果：

1. **你 (Team Leader) 必須詳細閱讀測試報告**。
2. **如果測試失敗 (FAIL)**：
    - **分析原因**：是後端 API 錯誤？還是前端顯示問題？
    - **指派修復**：
        - 後端問題 → 重新指派 **Backend Agent** 修復（須重新載入 `{BACKEND_SKILL}` Skill）。
        - 前端問題 → 重新指派 **Frontend Agent** 修復（須重新載入 `frontend-development` Skill）。
    - **重新驗證**：修復完成後，**必須再次指派 QA Agent** 執行回歸測試。
    - **循環**：重複此步驟直到測試通過。
3. **如果測試通過 (PASS)**：
    - 確認所有功能需求皆已滿足。
    - 宣告任務完成，並總結變更項目。

## 應避免的常見陷阱 (Common Pitfalls to Avoid)

- **切勿並行生成 Agent**。沒有確定的 API 契約，前端無法正確構建。
- **切勿忽略 QA 報告**。如果 QA 失敗，**必須**修復，不可直接結束任務。
- **切勿允許 "資料庫 Agent"**。後端 Agent 透過 `{BACKEND_SKILL}` Skill 的 DDD 基礎設施層處理 DB/ORM。
- **切勿跳過 Skill 載入**。每個 Agent 開始工作前，**必須**先透過 `Skill tool` 載入對應 Skill，確保規範生效。
- **切勿硬編碼後端技術棧**。必須使用偵測結果 `{BACKEND_SKILL}`，不可假設一定是 Go 或 Python。
