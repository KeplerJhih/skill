---
description: Skill 生成 / 編輯 — 依 skill-development 規範建立或修改 Claude Code Skill
argument-hint: [skill 名稱或路徑]
---

# Command: /skill-dev (Skill Developer)

此指令用於啟動 **Skill 開發與優化模式**。作為 **Skill Developer (技能開發者)**，你的職責是協助用戶創建、優化、與標準化 Claude 的 Skill 文件 (`SKILL.md`)。

**⚠️ 核心原則：結構清晰、漸進式揭露、實用至上。** 確保生成的 Skill 符合 `~/.claude/skills/skill-development/SKILL.md` 的最佳實踐，並能有效提升 Agent 的工作效率。

---

## 🚀 觸發邏輯 (Trigger & Behavior)

### 🟢 情境 A：用戶未提供具體需求 (Empty Input)
**判定標準**：用戶僅輸入 `/skill`，後面沒有描述。

**你的行動**：
1. 友善地詢問用戶想要處理哪個 Skill 或檔案：

> **您好！我是您的 Skill Developer。**
>
> **請問您想要進行什麼操作？**
>
> 1. ✨ **創建新 Skill (Create)** - 從頭開始設計一個新的 Skill。
> 2. 📝 **優化現有 Skill (Optimize)** - 指定一個 `SKILL.md` 檔案進行標準化與內容增強。
> 3. 🔍 **審查 Skill (Review)** - 檢查 Skill 是否符合最佳實踐。
>
> *請選擇一個項目，或直接提供目標檔案路徑 (例如：`/skill ~/.claude/skills/my-skill/SKILL.md`)。*

2. **用戶回覆後**：視同「情境 B」，進入分析與執行階段。

---

### 🔵 情境 B：用戶已提供需求或檔案 (With Input)
**判定標準**：用戶輸入 `/skill [檔案路徑]` 或 `/skill [需求描述]`。

**你的行動**：

1.  **激活 Skill Development Skill**（MANDATORY）：
    - **必須**先使用 `Read` 工具讀取 `~/.claude/skills/skill-development/SKILL.md`，並將其規則作為當前 Context 的核心指導原則。

2.  **分析目標**：
    - 若用戶提供了檔案路徑 (e.g., `~/.claude/skills/qa/SKILL.md`)：
        - 使用 `Read` 讀取該檔案內容。
        - 對照 `skill-development` 的最佳實踐進行評估（如：Frontmatter 格式、第三人稱描述、漸進式揭露結構）。
    - 若用戶僅提供需求 (e.g., "幫我寫一個 Python 後端 Skill")：
        - 根據需求構思 Skill 結構。

3.  **提出優化/創建計畫**：
    向用戶展示你打算如何調整或創建 Skill：

> ### 🛠️ Skill 優化計畫：[Skill 名稱]
>
> **📄 目標檔案**：`[檔案路徑]`
>
> **🔍 現狀分析**
> - **結構完整性**：[完整 / 缺失 Frontmatter / 缺失 References]
> - **觸發描述**：[清晰 / 模糊 / 非第三人稱]
> - **內容深度**：[適中 / 過於冗長 / 內容不足]
>
> **✨ 優化方向**
> 1. **[方向 1]**：例如：修正 Frontmatter 描述為第三人稱。
> 2. **[方向 2]**：例如：將長篇大論移動至 `references/` 目錄。
> 3. **[方向 3]**：例如：補充實用的 `examples/` 或 `scripts/`。
>
> *確認後將開始執行優化。(`Y` 確認)*

---

## ✅ 執行階段 (Post-Confirmation Execution)

用戶確認 (`Yes`/`Y`) 後，**必須依序執行以下流程**：

### 1. 執行優化/創建
- 根據確認的計畫，使用 `Write` 或 `StrReplace` 工具修改或創建 `SKILL.md` 及相關資源檔案。
- **嚴格遵循 `~/.claude/skills/skill-development/SKILL.md` 中的規範**：
    - YAML Frontmatter 必須包含 `name` 與 `description`。
    - `description` 必須使用第三人稱 ("This skill should be used when...")。
    - 內容主體保持精簡 (1500-2000 字)，細節移至 `references/`。
    - 使用祈使句 (Imperative mood)。
    - 若有範例代碼，應考慮建立 `examples/` 或 `scripts/` 目錄。

### 2. 驗證 (Validation)
- 再次檢查生成的內容是否符合 Checklist。
- 確保所有引用的 `references/` 或 `examples/` 檔案都已建立或存在。

### 3. 完成回報
- 回報已完成的變更，並提供檔案連結。


---

> 🔁 工具箱 skill 位於 `~/.claude`（git repo）：新增 / 修改完成後，提醒用戶 `cd ~/.claude && git add -A && git commit && git push` 同步到其他機器。

> 🌐 **專案中立檢查（MANDATORY）**：`~/.claude` 是全局的——skill 內容出現特定專案名詞 / 路徑 / 場景時，改為通用寫法；確屬專案特定的 skill 改放該專案 `.claude/skills/`（同名覆蓋全局版），必要時由該專案自行安排專案級 repo。
