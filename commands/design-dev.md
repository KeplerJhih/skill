---
description: Design Developer workflow — 依設計稿實作前端（frontend + frontend-design skill）
argument-hint: [設計稿路徑或需求]
---

# Command: /design-dev (Design Developer Workflow)

此指令用於啟動 **設計驅動開發流程**。結合 Pencil MCP 設計工具與 `frontend-design` Skill 美學指南，從視覺設計到代碼實作一條龍完成。

**⚠️ 核心原則：設計先行、視覺確認、批准後動。** 嚴禁在未獲得用戶明確確認 (`Yes`/`Y`) 前進行任何代碼修改。

---

## 🔧 工具鏈 (Toolchain)

| 工具 | 用途 | 階段 |
|------|------|------|
| **Pencil MCP** | 設計原型、元件佈局、設計稿操作 | 設計階段 |
| **frontend-design Skill** | 美學指導、創意方向、設計語言 | 設計思考 |
| **Chrome DevTools MCP** | 截圖驗證、佈局檢查 | 驗證階段 |
| **frontend Skill** | React/TypeScript/Tailwind 實作規範 | 開發階段 |

### Pencil MCP 工具清單

| 工具 | 功能 |
|------|------|
| `mcp__pencil__batch_design` | 建立、修改、操作設計元素（insert / copy / update / replace / move / delete） |
| `mcp__pencil__batch_get` | 讀取設計元件、搜尋元素、檢視元件階層 |
| `mcp__pencil__get_screenshot` | 渲染設計稿預覽截圖 |
| `mcp__pencil__snapshot_layout` | 分析佈局結構、偵測定位問題與重疊元素 |
| `mcp__pencil__get_editor_state` | 取得當前編輯器狀態與選取資訊（`include_schema: true` 取得當前 schema） |
| `mcp__pencil__get_guidelines` | 取得設計規範（topic: code / table / tailwind / landing-page / slides / design-system / mobile-app / web-app） |
| `mcp__pencil__get_variables` | 讀取設計 Token（色彩、字型、間距） |
| `mcp__pencil__export_nodes` / `export_html` | 匯出節點 / HTML（代碼實作對照用） |

> ⚠️ **Schema 為準**：Pencil MCP 工具隨版本演進（`set_variables`、`search_all_unique_properties`、`get_style_guide*` 等舊工具已移除）。使用前先 `get_editor_state(include_schema: true)` 取得當前 schema；本文件與實際 schema 不符時，一律以實際為準。

### Pencil MCP 技術限制（必讀）

#### 屬性地雷

| 項目 | 錯誤寫法 | 正確寫法 | 後果 |
|------|----------|----------|------|
| 文字顏色 | `color: "#1B4D5C"` | `fill: "#1B4D5C"` | `color` 被靜默忽略，文字不可見 |
| 圖示 | `{type: "icon", icon: "house"}` | 用文字/Emoji 替代（如 `"租"`、`"🔍"`） | icon 類型不穩定，常報 "Node has no type" |
| 百分比寬度 | `width: "90%"` | `width: 250`（固定像素） | 百分比會轉為 `fit_content`，寬度歸零 |
| 字重 | `fontWeight: 700`（數字） | `fontWeight: "bold"`（字串） | 數字值可能被忽略存為 `"normal"` |
| 佈局方向 | 省略 `layout` 屬性 | `layout: "vertical"` 明確指定 | Frame 預設為 `horizontal`，省略會排版錯亂 |
| 容器寬度 | 不設定子元素寬度 | `width: "fill_container"` | 子元素不會自動填滿父容器 |

#### Design Variables

- 先以 `mcp__pencil__get_variables` 檢視既有 Token；建立 / 修改 Token 的操作以當前 schema 為準（`batch_design` 支援時用之）
- 命名帶 `$` 前綴，在屬性中以 `"$variable-name"` 引用（如 `fill: "$slate-teal"`）

#### batch_design 最佳實踐

- 每次呼叫最多 **25 個操作**，超過應分批
- Insert / Copy / Replace 操作**必須**指定 binding name（如 `foo=I(...)`）
- 容器 Frame 先用 `placeholder: true` 建立，再以 Frame ID 插入子元素
- `fill_container`：填滿父容器；`fit_content`：依內容自動調整
- 優先使用 Pencil MCP 直接建立設計，**不需要** HTML 中介檔案

---

## 📁 設計稿存放位置

所有 Pencil 設計稿 (`.pen` 檔案) **統一存放**在專案根目錄的 `design/` 下（專案 CLAUDE.md 另有宣告則從專案）：

```text
<project-root>/
├── design/                    # ← 所有設計稿存放於此（與 .claude/ 同層）
│   ├── dashboard.pen          # 儀表板頁面設計
│   ├── notification-settings.pen
│   └── ...
├── .claude/                   # Claude 配置
├── frontend/                  # 前端代碼
├── backend/                   # 後端代碼
└── ...
```

**命名規範**：
- 檔名使用 **kebab-case**，與對應的頁面/元件名稱一致
- 範例：`notification-settings.pen`、`domain-detail.pen`、`login.pen`

**規則**：
- 新建設計稿時，**必須**存放在 `design/` 目錄
- 開啟現有設計稿時，優先從 `design/` 目錄查找
- 嚴禁將 `.pen` 檔案散落在其他目錄

---

## 🚀 觸發邏輯 (Trigger & Behavior)

### 🟢 情境 A：用戶未提供具體需求 (Empty Input)
**判定標準**：用戶僅輸入 `/design-dev`，後面沒有描述。

**你的行動**：

> **您好！我是您的 Design Developer。**
>
> **請問您想設計什麼？**
>
> 1. 🎨 **新頁面設計 (New Page)** — 從零開始設計一個完整頁面。
> 2. 🧩 **元件設計 (Component)** — 設計可重用的 UI 元件。
> 3. ♻️ **頁面改版 (Redesign)** — 改善現有頁面的視覺與體驗。
> 4. 📐 **佈局調整 (Layout)** — 調整現有頁面的排版與 RWD。
>
> *請選擇一個項目，或直接描述您的設計需求。*

用戶回覆後：視同「情境 B」。

---

### 🔵 情境 B：用戶已提供需求 (With Input)
**判定標準**：用戶輸入 `/design-dev [需求描述]`，或由情境 A 延續而來。

**你的行動**：依序執行以下四個階段。

---

## 📋 階段一：設計思考 (Design Thinking)

1. **激活 `frontend-design` Skill**（MANDATORY）：
   使用 `Skill tool` 載入 `frontend-design`，獲取美學指導框架。

2. **分析需求**：
   - 此介面解決什麼問題？目標用戶是誰？
   - 確定美學方向（基調）：極簡、奢華、工業、俏皮、編輯風…
   - 技術限制：依專案實際偵測（讀 package.json / 專案 CLAUDE.md；框架與版本一律以專案為準）。
   - 差異化：什麼讓這個設計令人難忘？

3. **檢查現有設計**（若為改版）：
   - 使用 `mcp__pencil__batch_get` 讀取現有設計元件。
   - 使用 `mcp__pencil__get_editor_state` 了解當前畫布狀態。
   - 使用 `mcp__pencil__get_variables` 讀取現有設計 Token。

4. **產出設計方案**，向用戶展示：

> ### 🎨 設計方案：[頁面/元件名稱]
>
> **🎯 設計目標**
> - [目標 1]
> - [目標 2]
>
> **🖌️ 美學方向**
> - **基調**：[選擇的風格方向]
> - **配色**：[主色 / 強調色 / 背景]
> - **字型**：[標題字型 / 內文字型]
> - **特色**：[讓設計獨特的關鍵元素]
>
> **📐 佈局規劃**
> - **桌面版** (≥1024px)：[描述]
> - **平板版** (≥768px)：[描述]
> - **手機版** (<768px)：[描述]
>
> **🧩 元件拆分**
> 1. [元件 A] — [用途]
> 2. [元件 B] — [用途]
>
> *確認設計方向後，將在 Pencil 中建立設計稿。(`Y` 確認)*

等待用戶確認 (`Y`/`Yes`) 後才進入階段二。

---

## 🖌️ 階段二：Pencil 設計 (Design in Pencil)

用戶確認設計方案後，使用 Pencil MCP 工具建立設計稿：

1. **讀取專案設計規格**（若存在）：
   使用 `Read tool` 讀取 `design/docs/design-system.md`，取得專案配色、字型、Token 定義。
   若檔案不存在，在階段二結束前建立。

2. **建立 / 開啟設計稿**：
   - 新建：在 `design/` 目錄建立 `.pen` 檔案，命名為 `{頁面名稱}.pen`（kebab-case）。
   - 改版：從 `design/` 目錄開啟對應的現有 `.pen` 檔案。

3. **取得設計規範**（建議）：
   根據設計類型，使用 `mcp__pencil__get_guidelines` 取得對應規範：
   - 網頁應用 → `topic: "web-app"`
   - 落地頁 → `topic: "landing-page"`
   - 手機應用 → `topic: "mobile-app"`
   - 設計系統 → `topic: "design-system"`

   若需要風格靈感，改用 `get_guidelines` 的其他 topic 或參考既有 `.pen` 檔的風格。

4. **設定設計 Token**：
   先以 `mcp__pencil__get_variables` 檢視既有 Token；配色、字型、間距等 Token 的建立 / 修改依當前 schema 以 `batch_design` 操作。

5. **建立設計元素**：
   使用 `mcp__pencil__batch_design` 逐步建立：
   - 頁面框架 (Frame)
   - 導航列 / 側邊欄（若適用）
   - 主要內容區塊
   - 互動元素（按鈕、輸入框、卡片等）
   - RWD 斷點變體

   **⚠️ 建立元素時必須遵守：**
   - 所有文字節點必須設定 `fill` 屬性（非 `color`）
   - 不使用 `{type: "icon"}`，改用文字/Emoji
   - 寬度一律用固定像素，不用百分比
   - Frame 明確指定 `layout: "vertical"` 或 `"horizontal"`

6. **文字可見性驗證**（MANDATORY）：
   每完成一個頁面後，立即執行：
   - 使用 `mcp__pencil__get_screenshot` 檢視該頁截圖，確認所有文字可見
   - 對可疑節點用 `mcp__pencil__batch_get` 檢查其 `fill` 屬性，缺失立即用 `batch_design` 的 `U()` 補上
   - **不要等全部頁面做完才檢查**，逐頁驗證能及早發現問題

7. **預覽驗證**：
   使用 `mcp__pencil__get_screenshot` 截取設計稿預覽，展示給用戶。

8. **佈局檢查**：
   使用 `mcp__pencil__snapshot_layout` 檢查是否有定位問題或元素重疊。

9. **展示設計稿結果**，向用戶確認：

> ### 🖼️ 設計稿完成
>
> [附上 Pencil 截圖]
>
> **變更摘要**：
> - 建立了 [N] 個元件
> - 設定了 [N] 組設計 Token
> - 涵蓋桌面 / 平板 / 手機三種斷點
>
> **⚠️ 確認後將進入代碼實作階段。**
> *確認設計稿後，開始撰寫 React/Tailwind 代碼。(`Y` 確認)*

**🔒 等待用戶確認 (`Y`/`Yes`) 後才進入階段三。嚴禁跳過此確認步驟。**

---

## ⚙️ 階段三：代碼實作 (Implementation)

**⚠️ 此階段必須在階段二確認後才能開始。**

1. **激活 `frontend` Skill**（MANDATORY）：
   使用 `Skill tool` 載入 `frontend`，遵循 React/TypeScript/Tailwind 實作規範。

2. **依設計稿實作**：
   - 在前端目錄（依專案 CLAUDE.md 的 `{FRONTEND_DIR}`，預設 `frontend/main`）的 `src/` 下建立或修改對應檔案。
   - 依照 `frontend` Skill 的目錄結構：
     - 頁面 → `pages/`
     - 原子元件 → `components/ui/`
     - 佈局元件 → `components/layout/`
   - 嚴格遵循設計稿的配色、字型、間距、佈局。
   - 確保 RWD 回應式設計（Mobile First → `md:` → `lg:` 斷點）。

3. **TypeScript 檢查**：
   執行 `cd {FRONTEND_DIR} && npx tsc --noEmit` 確認無型別錯誤。

4. **Lint 檢查**：
   執行 `cd {FRONTEND_DIR} && make lint` 確認無程式碼問題。

---

## ✅ 階段四：驗證與回報 (Verification & Report)

1. **視覺驗證**（若開發伺服器已啟動）：
   使用 `mcp__chrome-devtools__take_screenshot` 截取實際頁面截圖。
   使用 `mcp__chrome-devtools__take_snapshot` 檢查可及性樹狀結構。

2. **RWD 跑版檢查**：
   - [ ] 375px（手機）→ 768px（平板）→ 1920px（桌面）無重疊、無橫向捲軸
   - [ ] 按鈕與連結點擊範圍 ≥ 44x44px
   - [ ] 長文字區塊有 `break-words` 或 `truncate`

3. **完成回報**：

> ### ✅ 設計開發完成：[頁面/元件名稱]
>
> **🎨 設計**
> - 美學方向：[風格]
> - 設計稿路徑：`design/[名稱].pen`
> - Pencil 設計稿：[已建立 / 已更新]
>
> **⚙️ 實作**
> - 修改檔案：[檔案清單]
> - TypeScript：通過
> - Lint：通過
>
> **📱 RWD 檢查**
> - 桌面版：✅
> - 平板版：✅
> - 手機版：✅

---

## 🚨 重要規則

1. **雙重確認制**：設計方案確認一次（階段一 → 二），設計稿確認一次（階段二 → 三）。任何一次未獲 `Y`/`Yes`，**嚴禁**進入下一階段。
2. **Pencil 必須運行**：使用 Pencil MCP 前，先確認 Pencil 應用程式已開啟。若工具調用失敗，提示用戶啟動 Pencil。
3. **不要猜測設計**：對美學方向或佈局有疑問時，展示選項讓用戶選擇。
4. **設計即文檔**：Pencil 設計稿即為前端視覺規格書，代碼實作必須忠實還原。
5. **Pencil 技術限制必讀**：文字用 `fill`（非 `color`）、不用 icon 類型、不用百分比寬度。詳見本文件「Pencil MCP 技術限制」章節。
6. **逐頁驗證文字**：每完成一個頁面，立即用 `get_screenshot` + `batch_get` 檢查文字可見性與 `fill` 屬性。發現缺失立即修復，**禁止延遲到所有頁面完成後才檢查**。

ARGUMENTS: 使用 Pencil MCP 設計原型並結合 frontend-design Skill 美學指南，經設計方案確認與設計稿確認兩道審批後，實作為 React/Tailwind 代碼
