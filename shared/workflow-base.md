# 共用工作流程基礎 (Shared Workflow Base)

> **📍 全域唯一正本**（`~/.claude/shared/workflow-base.md`）：被所有專案的 `/doit` 與 `/team` 共用。修改時請同時考慮兩端影響。專案差異寫在各專案 CLAUDE.md，**不得**另存專案級拷貝（會造成漂移）。

---

## 🎯 任務類型分流（第一步，MANDATORY）

任務開始時先判定類型，**決定後續流程的深淺**。判定不準時往最重的（Code）走。

| 類型 | 判定 | 後續流程 |
|------|------|---------|
| 🔴 **Code** | 改 / 新增函式、類別、介面、資料結構；跨檔案重構；理解調用鏈 | 完整流程，Serena 主力 |
| 🟡 **Config** | 改 yaml/json/toml/Makefile/Dockerfile/.env/k8s manifest 等設定 | Read + Edit 為主，必要時 Grep |
| 🟢 **Docs** | 改 md/txt/註解；無程式邏輯變動 | Read + Edit |
| ⚪ **Trivial** | typo / 單行修改 / 純註解 | 直接 Edit，跳過下方多數步驟 |
| ❓ **不確定** | 跨類型或範圍不清 | 按 Code 處理 |

---

## 🗺️ 專案偵測（依任務類型調整深度）

### 步驟 0：讀取 CLAUDE.md（MANDATORY，所有類型）

CLAUDE.md 是專案地圖的 **single source of truth**。

1. **必讀**：根 `./CLAUDE.md`（如存在）→ 取得專案地圖、變數宣告、慣例
2. **必讀**：任務涉及的子目錄 `CLAUDE.md` → 取得局部規範
3. **解析變數**：抽取 CLAUDE.md 宣告的工作目錄變數（`{*_DIR}`），後續流程使用

### 步驟 1：自動掃描 CLAUDE.md（條件性，僅 Code/跨子專案任務）

**僅在以下情況執行** Glob `**/CLAUDE.md`（深度限 3，排除 `node_modules`、`vendor`、`.git`、`archive`、`deprecated`）：

- 任務範圍跨多個子專案
- 根 CLAUDE.md 不存在（需要建立臨時地圖）
- 任務本身就是維護專案地圖

掃出後對賬：

| 狀況 | 處理 |
|------|------|
| 已登錄存在 | ✅ 依根 CLAUDE.md 描述使用 |
| 未登錄存在 | 🔍 提示「發現未登錄子專案」，建議補進根地圖 |
| 已登錄缺失 | ⚠️ 提示「可能已重構」 |
| 根地圖不存在 | 🟡 將 glob 結果視為臨時地圖，建議建立（範本：`~/.claude/shared/templates/CLAUDE.md.template`） |

**Trivial / Docs / 單一子專案的 Config 任務跳過此步驟**——小範圍改動不需要對賬整個地圖。

### 步驟 2：補強偵測（按任務類型）

CLAUDE.md 仍有資訊缺口時：

| 任務類型 | 補強方式 |
|---------|---------|
| 🔴 Code（Serena 可用） | `list_memories` → `read_memory(architecture)`（如有）→ `list_dir` → `get_symbols_overview` |
| 🔴 Code（Serena 不可用） | `Glob` 標誌檔 + `Read` 主要進入點（main / index / app 等）+ `Grep` 關鍵函式 |
| 🟡 Config | `Glob` 標誌檔（`*.yaml`、`Makefile`、`docker-compose*.yml`、`*.tf` 等）+ Read 對應檔案 |
| 🟢 Docs | 直接 Read 目標檔案，不做偵測 |
| ⚪ Trivial | 跳過 |

### 偵測規則

1. CLAUDE.md 是真實來源——它的描述優於檔案系統推論
2. CLAUDE.md 與檔案系統衝突時，以 CLAUDE.md 為準並提示更新
3. Skill 名稱由「可用 Skill 清單」動態匹配，**不寫死於本檔案**
4. 任務藍圖必須標示偵測到的內容與來源（CLAUDE.md / Serena / Glob）

---

## 🔍 上下文檢索（按任務類型挑工具）

依「任務類型分流」結果挑工具，**不重複列舉**：

### 🔴 Code 任務

> **原則**：Serena 可用時優先（symbol-aware，更精準）；不可用時 native 工具完全夠用，**不要因為缺 Serena 就跳過任務**。

| 用途 | Serena 可用（優先） | Serena 不可用 / 回傳空（fallback） |
|------|-------------------|----------------------------------|
| 找符號（函式 / 類別 / 介面） | `mcp__serena__find_symbol` (`include_body=True`) | `Grep` 符號名稱 + `Read` 對應行 |
| 看檔案頂層結構 | `mcp__serena__get_symbols_overview` | `Read` 整檔（短檔）或 `Grep` ^func/^class（長檔）|
| 追調用鏈 / 影響範圍 | `mcp__serena__find_referencing_symbols` | `Grep -r` 符號名 |
| 搜散佈各處的關鍵字 | `mcp__serena__search_for_pattern` | `Grep` |
| 讀架構記憶 | `mcp__serena__read_memory` | （無對應）改用 `Read` 根 / 子 CLAUDE.md |

**判斷 Serena 是否可用**：呼叫 `mcp__serena__list_memories` 或 `mcp__serena__list_dir` 看是否成功；失敗 / timeout / 拒絕存取 → 切 fallback，不重試。

### 🟡 Config 任務

| 用途 | 工具 |
|------|------|
| 找特定字串 | `Grep` |
| 看檔案內容 | `Read` |
| 找散佈各處的設定模式 | `mcp__serena__search_for_pattern`（yaml/Makefile 也支援） |

### 🟢 Docs 任務

| 用途 | 工具 |
|------|------|
| 讀目標檔案 | `Read` |
| 找相關文檔 | `Grep` 或 `Glob` |

### ⚪ Trivial 任務

不檢索，直接執行。

---

## ⚠️ Skill 載入規則（MANDATORY）

> **核心原則：強制安全網 + 自動判斷、按需載入、不可跳過。**
>
> Skill 檔案包含完整的實作規範、配套步驟與注意事項，**光看既有程式碼無法取代 Skill 的完整指引**。

### 步驟 1：強制載入「通用安全網」（每次必載）

**每次 /doit /team 都必須最先載入**：

- `karpathy-guidelines`（或同等用途的 `simplify`）

**理由**：防止過度設計、不必要抽象、跳過重點。這個 Skill 是 LLM 動手前的自我檢查機制，**不可跳過**。

### 步驟 2：自動判斷「任務專屬 Skill」

1. 根據任務內容，**自動判斷**需要哪些 Skill：對照「可用 Skill 清單」每個 Skill 的 **description**，挑出 description 與任務契合的 Skill
2. 取得該 Skill 的 **name**（呼叫 Skill tool 用的 ID）
3. **列出**將載入的 Skill 清單（name + 用途），讓用戶知道
4. 使用 `Skill tool` 逐一載入

> **匹配機制**：description 用來判斷契合度，name 用來呼叫。例：任務「寫 React 表單」→ description 含「React/TypeScript」的 Skill → name 是 `frontend`（載入 ID = skill 目錄名），**以實際清單為準**。

### 步驟 3：Agent 自行載入（僅 /team）

`/team` spawn 出的 Agent 是**獨立 context**，host 載入的 Skill 不會繼承。所以每個 Agent 的 prompt 都包含「**第一步（強制）：從可用 Skill 清單匹配並載入相關 Skill（可 1 個或多個）**」指令——**不指定具體 skill name**，由 Agent 自行依任務動態匹配。

**為什麼不在 prompt 寫死 skill name**：
- 同一角色可能要載多個 skill（例：前端任務同時要 `frontend` + `frontend-design` + `figma:implement-design`）
- 不同專案的 skill 命名版本不同
- 寫死 = 限制了「按需載入」的彈性

**Host 仍要做的**：步驟 2 動態匹配出的 skill 是**給 host 自己制定藍圖用**，不傳給 Agent。Agent 自己會在拿到任務後再做一次匹配。

**Agent 回報**：每個 Agent 完成後在回報中列出「本次載入的 Skill 清單」，供 host 審視判斷是否合理；不合理時可請 Agent 重做（再次 spawn）。

### 載入時機

- `/doit`：分析完成後、**制定藍圖前**載入，使 Skill 規範能指導藍圖制定
- `/team`：分析完成後、**制定藍圖前**載入；此外每個 Agent 的 prompt **開頭**仍必須包含 Skill 載入指令，確保 Agent 自身也擁有規範上下文

### 禁止事項

- ❌ 跳過 `karpathy-guidelines` 的強制載入 → 失去過度設計的安全網
- ❌ 跳過 Skill 直接靠既有程式碼推斷步驟 → 會遺漏配套設定
- ❌ 不分青紅皂白載入所有 Skill → 浪費上下文、干擾重點
- ✅ 強制安全網 → 分析任務 → 自動匹配 → 列出清單 → 載入 → 制定藍圖

---

## 🔌 MCP 工具動態偵測（Skill 載入後、藍圖前）

> 此段落被 `/doit` 與 `/team` 共用。

### 偵測流程

1. **列舉可用 MCP**：從 system-reminder 的 deferred tools 清單提取 `mcp__<server-name>__` 前綴，去重得到當前已連線的 MCP server 清單
2. **任務匹配**：根據任務需求與偵測到的技術棧，篩選出**與本次任務相關**的 MCP 工具
3. **列出結果**：在藍圖「🔌 MCP 工具」欄展示匹配結果及用途

### 匹配原則

- **按需匹配**：只選與本次任務直接相關的 MCP，不要全部列出
- **智能推斷**（參考示例，非窮舉，以當前環境實際可用者為準）：
  - 代碼分析 / 精準編輯 → `serena`
  - 查文檔 / 版本遷移 → `context7`
  - 前端 UI 測試 / E2E → `chrome-devtools`
  - iOS 開發 / 測試 → `xcodebuild`、`ios-simulator`
  - 架構圖 / 流程圖 → `drawio-mcp`
  - GCP / AWS / 阿里雲資源 → `gcloud-mcp`、`awslabs.*`、`alibabacloud`
  - Figma 設計稿 → `figma`
- **不寫死**：出現新的 MCP server 也應能自動識別並匹配

### `/team` 額外規則

每個隊友的啟動 prompt 應包含分配給該隊友的 MCP 工具清單（名稱 + 用途），使隊友知道有哪些工具可用。

---

## 🚫 過度設計檢查（藍圖前 MANDATORY）

> **目的**：防止為了「以後可能用到」「看起來更靈活」而引入沒人要求的抽象層。
>
> **時機**：制定藍圖前最後一道檢查。對每個「設定項 / env var / 參數 / 介面 / 抽象層」逐一過。

### 三題自審

對每個計畫加入的變更項目，逐一回答：

1. **必要性**：移除這個變更會有什麼壞處？
   - 沒明顯壞處 → **從藍圖中移除**

2. **抽象成本**：引入後，預期會有幾個真實使用者會自訂這個值？
   - 少於 1 個（自己也不會改） → **從藍圖中移除**

3. **預設值反問**：如果預設值就是唯一合理的值（路徑慣例、約定俗成的命名）
   - 預設值 = 唯一合理值 → **不該加成設定項，直接寫死**

### 經典反例（這些都是踩過的雷）

- ❌ `GCP_KEY_PATH=./secrets/gcp-key.json` 預設值 = 唯一合理路徑 → 不該加 env var
- ❌ 為「未來可能多個」加 list 參數 → YAGNI（You Ain't Gonna Need It）
- ❌ 包裝原本簡單的工具函式為 class → 沒帶來任何好處
- ❌ 為了「分層」把 30 行檔案拆成 3 個檔 → 增加閱讀成本
- ❌ 加「未來可擴充」的設定鉤子但沒有第二個使用者 → 純粹增加複雜度
- ❌ 工具箱內容（skills / commands / agents / templates / workflow-base 等 `~/.claude` 全域檔案）寫死當下對話的專案名詞、路徑或場景 → 跨專案重用時誤導；確屬專案特定的內容放該專案 `.claude/` 層

### 黃金原則

> **Convention over Configuration（慣例優先於設定）**：
> 能用目錄結構、命名規則、檔名約定的事，就不要做成設定項。
> 設定項只在「有兩個以上合理選擇」時才存在的價值。

---

## 🛠️ 編輯工具選擇（依任務類型）

避免「殺雞用牛刀」——簡單修改用簡單工具。

| 場景 | Serena 可用 | Serena 不可用 |
|------|-----------|---------------|
| 🔴 Code：整個函式 / 類別替換 | `mcp__serena__replace_symbol_body` | `Edit`（old_string 涵蓋整個函式） |
| 🔴 Code：在特定符號前後新增 | `mcp__serena__insert_after_symbol` / `insert_before_symbol` | `Edit`（old_string 用前後 anchor 文字） |
| 🔴 Code：跨檔案 / 散佈式修改 | `mcp__serena__replace_content`（regex） | `Edit` (`replace_all=true`) 或多次 Edit |
| 🟡 Config：改幾行設定 | — | `Edit` |
| 🟢 Docs：改文字 | — | `Edit` |
| ⚪ Trivial：typo / 單行 | — | `Edit` |
| 🆕 新建檔案 | — | `Write` |

**原則**：
- 能用 `Edit` 解決的小修改，**不要繞道 Serena**——Serena 強項是 symbol-aware 操作，對 yaml/Makefile/md 不適用
- Serena 不在時，用 native `Edit` 直接做，**不要因為「沒 Serena」就停下來**

---

## 🧪 QA 前端驗證觸發條件

> 此規則供 `/doit` 與 `/team` 判斷**何時需要 QA**。具體測試方式由 `qa` Skill 定義。

| 有涉及 | 需要 QA |
|--------|---------|
| 前端頁面 / 組件 / UI 變更 | ✅ 需要 — 載入 `qa` skill 執行 |
| 純後端 API / DB / 腳本 | ❌ 不需要 |
| DevOps / Makefile / CI/CD | ❌ 不需要 |
| 文檔 / Skill 編輯 | ❌ 不需要 |

---

## 📋 CLAUDE.md 一致性檢查（完成回報前 MANDATORY）

> **目的**：本次修改可能讓專案地圖與實際狀態漂移。完成任務前自審，主動提出 CLAUDE.md 更新建議。
>
> **時機**：所有變更實作完、測試通過後，**生成完成回報前**執行。

### 觸發條件（任一成立 → 必須檢查）

| 變更類型 | 檢查重點 |
|---------|---------|
| 新增 / 刪除 / 重命名目錄 | 根 CLAUDE.md 子專案地圖是否同步 |
| 新增 / 刪除 / 改名環境變數 | `.env.example` 與相關 CLAUDE.md 慣例段是否同步 |
| 新增依賴 / 技術棧（如新加 Python 服務） | 子專案地圖的「主要技術」「對應 Skill」欄位 |
| 新增禁區（不能 commit 的檔案、目錄） | 根 CLAUDE.md 禁區清單 + `.gitignore` |
| 改變部署 / 啟動方式（新 Makefile target、新指令） | 「快速啟動」段 |
| 新增規範 / 慣例 | 「跨子專案慣例」段 |
| 修改 API 契約 | 根 CLAUDE.md 指定的契約文件路徑 + 子 CLAUDE.md 對應段 |

### 不觸發（避免雜訊）

- 純 bug 修復、不改變介面或結構
- 重構單一檔案內部
- 新增程式內部函式 / 類別
- 修改既有設定值（不改 key 名）
- 文件 typo / 排版

### 執行方式

1. 對照本次變更清單，逐一過上面的觸發條件
2. 找到漂移時，在**完成回報**最後加一段「📋 CLAUDE.md 更新建議」，依嚴重度分組：

```markdown
📋 CLAUDE.md 更新建議

### 🟢 建議（小漂移）
- `<sub>/CLAUDE.md` 的 <段落名>：補上本次新增的 <設定/做法> 說明

### 🟡 推薦（中度漂移）
- 根 `CLAUDE.md` 子專案地圖：登錄本次新增的 <服務/目錄/技術棧>

### 🔴 必要（重大漂移，不更新會誤導）
- 根 `CLAUDE.md` <禁區清單/變數區塊/啟動方式>：補上本次 <新增/變更/移除> 的內容
```

**注意**：實際輸出時，把 `<>` 佔位符替換成本次任務的具體內容（檔案路徑、目錄名、變更項目等）。

3. **不自動修改 CLAUDE.md**——列建議，由用戶決定是否一併更新（避免單純的程式碼任務變成連帶改文件的大型 PR）

### 嚴重度判定

- 🟢 **建議**：補完更精準，不更新也不會誤導
- 🟡 **推薦**：未來讀 CLAUDE.md 的人會少一些資訊，但不會走錯路
- 🔴 **必要**：不更新會讓 CLAUDE.md 變成錯誤指引（例如刪掉的目錄還列在地圖上）
