# 共用工作流程基礎 (Shared Workflow Base)

> 此檔案被 `/doit` 與 `/team` 共用。修改時請同時考慮兩端影響。

---

## 🔎 專案偵測 (Project Detection)

### 偵測方式（按優先順序）

1. **Serena 優先**：呼叫 `mcp__serena__list_memories` 查看是否有 `architecture` 記憶；若有則 `mcp__serena__read_memory` 讀取，快速掌握專案結構。
2. **Serena 符號掃描**：呼叫 `mcp__serena__list_dir` 掃描根目錄與 `backend/`、`frontend/` 子目錄，確認技術棧。
3. **Fallback**：若 Serena 不可用，才使用 Glob 工具掃描標誌檔。

### 偵測對照表

| 標誌檔 | 判定為 | Skill 名稱 | 測試指令 |
|--------|--------|-----------|---------|
| `go.mod` 或 `backend/go/` 存在 | Go 後端 | `backend-development-go` | `cd backend/go && make test` |
| `requirements.txt` + (`wsgi.py` 或 `app/__init__.py`) 或 `backend/python/` 存在 | Python/Flask 後端 | `backend-development-python` | `cd backend/python && make test` |
| `package.json` 含 React 相關依賴 | React 前端 | `frontend-development` | — |
| `native/ios/` 存在且含 `.xcodeproj` 或 `Package.swift` | Native iOS | `native-ios-development` | Xcode build/test via `xcodebuild` |

### 偵測規則

1. 從工作目錄向下搜尋，優先檢查 `backend/go/`、`backend/python/` 子目錄
2. 若兩者皆存在，則為**多後端 Monorepo**，根據用戶需求決定啟用哪個
3. 偵測結果記為 `{BACKEND_SKILL}` 和 `{BACKEND_DIR}`，後續所有引用皆使用此變數
4. 額外檢查 `native/ios/` 目錄，若存在則記為 `{NATIVE_IOS}=true`、`{NATIVE_IOS_DIR}=native/ios/`
5. 在任務藍圖中**必須**標示偵測到的所有技術棧（含 Native iOS）

---

## 🔍 上下文檢索（Serena 優先）

**優先 Serena**：
- `mcp__serena__read_memory`：讀取 `architecture` 記憶，掌握專案結構。
- `mcp__serena__find_symbol`：按名稱搜尋相關的 struct / interface / function / component。
- `mcp__serena__get_symbols_overview`：掃描目標檔案的頂層符號，快速掌握結構。
- `mcp__serena__find_referencing_symbols`：追溯調用鏈，理解影響範圍。
- `mcp__serena__search_for_pattern`：搜尋非代碼檔（YAML、Markdown、SQL migration 等）。

**Fallback**：若 Serena 回傳空結果或不可用，使用 Grep / Glob 搜尋。

**目標**：識別涉及的 API 端點、組件、Entity 與資料庫 Schema。

---

## ⚠️ Skill 載入規則（MANDATORY）

> **核心原則：自動判斷、按需載入、不可跳過。**
>
> Skill 檔案包含完整的實作規範、配套步驟與注意事項（如 `.gitignore` 設定、測試要求等），**光看既有程式碼無法取代 Skill 的完整指引**。

### 載入方式

1. 根據任務內容，**自動判斷**需要哪些 Skill（從系統提供的可用 Skill 清單中匹配）
2. **列出**將載入的 Skill 清單，讓用戶知道
3. 使用 `Skill tool` 逐一載入

### 載入時機

- `/doit`：分析完成後、**制定藍圖前**載入，使 Skill 規範能指導藍圖制定
- `/team`：分析完成後、**制定藍圖前**載入；此外每個 Agent 的 prompt **開頭**仍必須包含 Skill 載入指令，確保 Agent 自身也擁有規範上下文

### 禁止事項

- ❌ 跳過 Skill 直接靠既有程式碼推斷步驟 → 會遺漏配套設定
- ❌ 不分青紅皂白載入所有 Skill → 浪費上下文、干擾重點
- ✅ 分析任務 → 自動匹配相關 Skill → 列出清單 → 載入 → 制定藍圖

---

## 🛠️ Serena 優先的代碼操作

**代碼探索與編輯優先使用 Serena 工具**：
- **讀取符號**：`mcp__serena__find_symbol` + `include_body=True` 讀取目標函式/方法。
- **編輯代碼**：
  - 整個符號替換 → `mcp__serena__replace_symbol_body`
  - 局部修改（幾行內） → `mcp__serena__replace_content`（支援 regex）
  - 新增代碼 → `mcp__serena__insert_after_symbol` / `mcp__serena__insert_before_symbol`
- **Fallback**：Serena 不可用時才使用 Edit / Write 工具。

---

## 🧪 QA 前端驗證觸發條件

> 此規則供 `/doit` 與 `/team` 判斷**何時需要 QA**。具體測試方式由 `qa` Skill 定義。

| 有涉及 | 需要 QA |
|--------|---------|
| 前端頁面 / 組件 / UI 變更 | ✅ 需要 — 載入 `qa` skill 執行 |
| 純後端 API / DB / 腳本 | ❌ 不需要 |
| DevOps / Makefile / CI/CD | ❌ 不需要 |
| 文檔 / Skill 編輯 | ❌ 不需要 |
