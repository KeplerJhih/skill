---
name: md-update
description: 當使用者輸入「update md」、「更新文檔」、「更新 md」、「記錄踩坑」、「寫進 CLAUDE.md」等指令時觸發。收斂當前對話 / 最近 commits 內的踩坑與設計決策,組織成精煉的「踩坑日誌」entry,**先回報草稿等使用者確認**再寫入專案對應的 CLAUDE.md。檔案過長時提議拆到 references/ 之後引用。
color: yellow
---

# md-update — CLAUDE.md 踩坑日誌維護

## 核心職責

把當前對話 / 最近 commits 中的**踩坑、設計取捨、非顯而易見的決策**收斂成精煉的「踩坑日誌」entry,寫入正確的 CLAUDE.md。

**這不是 changelog** — git commit 已經是 changelog。CLAUDE.md 是「下次開發回來看,能讓人少踩坑」的索引。

---

## 流程

### Step 1: 識別工作上下文

- 跑 `git log --oneline -10` 看最近改了什麼
- 看 conversation 內的踩坑討論(不在 commit message 裡的內容)
- 識別變更範圍是純子專案還是跨專案

### Step 2: 識別目標 CLAUDE.md(按 `.claude/CLAUDE.md` 維護方針)

| 變更範圍 | 目標 |
|---------|------|
| 純後端(service / provider / handler / DB) | `backend/go/CLAUDE.md` |
| 純 iOS(domain / store / view / i18n) | `native/ios/orua/CLAUDE.md` |
| 純官網 / landing | `frontend/landing/CLAUDE.md` |
| 跨專案的功能總覽 / 端點 / 部署 | `.claude/CLAUDE.md`(根目錄) |
| `.claude/skills/` 變更 | 對應 skill 的 SKILL.md(**不是 CLAUDE.md**) |

### Step 3: 內容篩選 — 該寫進 CLAUDE.md 嗎?

**該寫**:
- 踩坑了,**為什麼**這樣做(API 限制 / SwiftUI 怪行為 / 框架陷阱)
- **設計取捨**(為什麼選 A 不選 B,scope 為什麼這樣畫)
- **新檔案放哪、新慣例是什麼**
- **跟 CLAUDE.md 既有段落矛盾的地方**(要順手修舊段)

**不該寫**:
- 純 add feature 沒踩坑(commit message 已說明)
- 列每個 commit 的細節 / changelog
- 看代碼就能知道的資訊(class 結構、function 簽名等)
- 已經在既有 CLAUDE.md 段落寫過的(避免重複)

### Step 4: 寫法規範

- **單一段落 ≤ 150 字**(從 `.claude/CLAUDE.md` 維護方針引用)
- 列「為什麼這樣設計、碰過什麼坑、新檔案放哪裡」
- 用 markdown bullet,簡短直白
- 對技術細節精確引用 — i18n key 名、struct 名、modifier 名、檔案路徑
- 引用具體檔案絕對路徑,而非「某個 view」這種模糊指涉

### Step 5: 檢查現有 CLAUDE.md 長度

跑 `wc -l <target>`。若 > 700 行,**主動提議拆分**:

- 把較大段(如「SWAGGER 規範」/「LOGGING」/「拖曳實作細節」)抽到 `.claude/skills/<scope>/references/<topic>.md`
- CLAUDE.md 只留**一句摘要 + 連結到 reference 檔**

**不要主動拆** — 給使用者選擇:`A. 拆 / B. 直接加進 CLAUDE.md / C. 你決定`。

### Step 6: 草稿 + 確認(MANDATORY)

**絕對先把草稿展示給使用者**,清楚標明:
- 要更新哪個 CLAUDE.md(絕對路徑)
- 要**插入**哪一段、加哪幾條 bullet(顯示準備新增的 markdown 內文)
- 要**修改**既有哪一段(diff 風格,標明原本是什麼)
- (若有)拆分提案

使用者回 `OK` / 給修改建議再實際寫。**不要直接 edit 後再說「順便給你看」**。

### Step 7: 寫入 + commit

- 用 `Edit` tool 寫入(不用 `Write` — 既有 CLAUDE.md 必須以 Edit 修改)
- commit message 風格參考既有 git log:`docs(<scope>): CLAUDE.md ... 段補 ...`
- **不主動 push**,除非使用者要求
- **不開新 branch** — docs 改動直接在 working branch 即可(除非 working branch 是受保護的 main / dev,那要看使用者意願)
- **不 commit 被工具自動 touch 的檔**(例如 Xcode 偷改的 `CURRENT_PROJECT_VERSION`、`.DS_Store`),只 add 明確的 md 檔

---

## 重要原則(每次都要遵守)

1. **這是踩坑日誌不是 changelog** — write WHY, not WHAT。WHAT 屬於 commit message
2. **寧短勿長** — 單一段落 ≤ 150 字,超過就拆
3. **不重複** — 已在 git log / 既有 CLAUDE.md 段落寫過的不要再寫
4. **不主動建 task** — 這是 atomic doc 更新,不需 TaskCreate
5. **先回報草稿** — 嚴禁未確認直接 edit
6. **不污染 commit** — 只 add 明確要改的 md,不 -A

---

## 範例:好的踩坑日誌條目

```markdown
- **outro Markdown 支援(v2.5 起)**:`Text(.init(loc.t(outroKey)))` 用
  `LocalizedStringKey` 包裝啟用 SwiftUI Markdown 解析,支援 inline
  `[label](url)` 超連結(純 `Text(loc.t(...))` String 不解析)。v2.4 舊
  outro 純文字不含 markdown 字符,改用 `.init()` 不破壞顯示
```

✅ 為什麼好:
- 明說「為什麼」要用 `.init()`(因為 SwiftUI Text 對 String vs LocalizedStringKey 行為不同)
- 帶版本標記(v2.5 起)讓未來看到時知道脈絡
- 引用具體 API 名稱
- 解釋向後相容如何處理(v2.4 舊文案沒破壞)
- ~110 字,精煉

## 反例:壞的踩坑日誌條目

```markdown
- v2.5 新增了 outro 段可以顯示超連結。在 WhatsNewSheet 內改了 Text 的初始化方式。
  使用者可以點擊 link 跳轉到 App Store。
```

❌ 為什麼壞:
- 沒講「為什麼要這樣改」(WHY 缺失)
- 沒講具體 API(`Text(.init(...))` vs `Text(loc.t(...))`)
- 講「使用者可以點擊」是 commit message 該說的,CLAUDE.md 不需要
- 沒帶版本標記
- 跟 git log 100% 重複,沒新資訊量
