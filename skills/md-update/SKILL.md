---
name: md-update
description: 當使用者輸入「update md」、「更新文檔」、「更新 md」、「記錄踩坑」、「寫進 CLAUDE.md」等指令時觸發。收斂當前對話 / 最近 commits 內的踩坑與設計決策,組織成精煉的「踩坑日誌」entry,**先回報草稿等使用者確認**再寫入專案對應的 CLAUDE.md。檔案過長時提議拆到子專案 docs/ 目錄之後引用。
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
- **檢查是否有 active teammate / agent**:看 conversation 是否有 teammate 訊息、`TaskList` 是否有 in_progress、是否剛走完 `/team` workflow

### Step 1.5: 若有 active teammate / agent,先諮詢實作端視角(MANDATORY)

Lead 從 conversation 看到的是「成果 + 對話摘要」,**實作細節的踩坑只有實際寫代碼的 teammate 最清楚**。如果有以下情境之一,先 `SendMessage` 詢問:

- 剛走完 `/team` workflow,teammate 還沒 shutdown
- 對話 context 內有 teammate 工作回報訊息
- 剛 `Agent` spawn 過 subagent 處理任務

**詢問模板**:

```
我們準備把這次工作的踩坑與設計決策寫進 <對應的 CLAUDE.md>。
請列 3-5 條**真正非顯而易見、值得記下來給未來開發者**的內容:

1. 哪些是「看代碼也看不出來」的設計取捨(為什麼選 A 不選 B)
2. 哪些是「不寫進 CLAUDE.md 下次又會踩」的隱形 bug 模式 / 框架陷阱
3. 哪些跟既有 CLAUDE.md 段落矛盾、需要順手修舊段

不必寫 changelog 性質的東西(commit message 已說明)。每條 ≤ 100 字,
精確引用 API 名 / 檔案路徑。
```

**整合策略**:把 teammate 從實作端看到的 + Lead 從 conversation 看到的合在一起,**去重 + 取交集**。若 teammate 沒回應(已 shutdown 等),用 conversation 內既有的訊息回放當作 fallback,但要在草稿標註「來自 Lead 推論,未經 teammate 確認」。

### Step 2: 識別目標 CLAUDE.md 位置(自動偵測,不寫死路徑)

依以下順序定位,**不假設專案結構**:

1. **讀根 `./CLAUDE.md`**(若存在)→ 拿子專案地圖,對照本次變更目錄找對應子 CLAUDE.md。地圖通常以 markdown 表格列出子目錄 + 對應 CLAUDE.md
2. **若無根 CLAUDE.md** → 依變更檔案所在子目錄推論:
   - 改動集中在單一子目錄 → 該子目錄的 CLAUDE.md(例如改 `backend/python/` 內檔 → `backend/python/CLAUDE.md`)
   - 改動跨多個子目錄 → 根 `./CLAUDE.md`
   - 改動只在 `.claude/skills/<name>/` → 對應的 `SKILL.md`(**不是 CLAUDE.md**)
3. **檢查目標檔是否存在**(用 `ls <target>` 或 `wc -l <target>` 探測):
   - 存在 → 走「補丁分支」(Step 5/6/7 原流程)
   - 不存在 → 走「首建分支」(見 Step 2.5)

### Step 2.5: 首建 CLAUDE.md 分支(目標檔不存在時)

**先詢問使用者是否要建立**,絕不主動建檔:

```
目前 <target absolute path> 不存在,本次踩坑要寫進去需先建立 CLAUDE.md。是否建立?

A. 是 — 以 `.claude/shared/templates/CLAUDE.md.template` 為骨架,本次踩坑作為首條 entry
B. 否,我先別寫了(中止流程)
C. 是,但這個路徑不對 — 我告訴你正確位置
```

**使用者選 A**:
- 若 template 存在 → 讀 template + 替換占位符(`{PROJECT_NAME}` 等用 dir name 或 `package.json`/`go.mod`/`Cargo.toml` 等 manifest 推論)
- 若 template 不存在(其他專案 clone skill 時可能沒帶)→ 用最小骨架:`# <ProjectName>\n\n` + 「## <feature> 踩坑」一段
- 用 `Write` 工具寫入(此情境唯一 Write 合法用法,見 Step 7)

**使用者選 B**:中止,不寫任何檔。

**使用者選 C**:重新走 Step 2.5 用新路徑。

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

### Step 5: 檢查現有 CLAUDE.md 長度(僅補丁分支)

> **首建分支跳過本步驟** — 新建檔不必檢查長度。

**兩條觸發條件**(任一達標 → 主動提議拆分):

1. **整檔行數**:`wc -l <target>` > 700 行
2. **單段字數**:**任何 H2 段(`## ...` 起算到下個 `## `)字數 > 450 字** — 用 `wc -m` 算字符數(中文 1 字符算 1,英文 word 也算內部字母數)。**這是強制觸發**,不論整檔行數是否爆。

抓單段字數的快速做法:
```bash
awk '/^## /{if(name) print count, name; name=$0; count=0; next} {count+=length($0)} END {if(name) print count, name}' <target> | sort -rn | head -3
```

**拆分動作**:
- 把超標的段(或新加會超標的段)抽到該 CLAUDE.md 所在子專案的 `docs/<topic>.md`(例如 `native/ios/orua/docs/icloud-sync.md`)
- CLAUDE.md 只留**一句摘要 + 相對路徑連結到 docs/ 檔**(例如 `iCloud 自動同步詳見 docs/icloud-sync.md`)
- 若 `docs/` 目錄不存在,先建立

**不要主動拆** — 給使用者選擇:`A. 拆 / B. 直接加進 CLAUDE.md / C. 你決定`。

**為何兩條都要**:整檔行數只抓「累積太多段」的情況;單段字數抓「某個主題太肥」的情況 — 後者即使整檔才 500 行,讀者翻到那段也會被淹沒,單獨切出去比較好讀。

### Step 5.5: 順手偵測過時 / 不必要段落(MANDATORY)

跑長度檢查的同時,**掃一遍既有段落**找可刪/可縮候選。目的:CLAUDE.md 是給未來開發者的索引,過時資訊比沒寫還糟(誤導)。

**過時訊號**(找到任一就標記):
- 段內提到的 API / class / function / 檔案名稱,用 `Grep`/`Glob` 在 source code 找不到(被重構/移除)
- 提到「未實作」「待補」「Tier X 未上」的狀態,而 `git log` 顯示後續已完成
- 提到某版本舊行為(「v2.1 重構前」/「v1 schema」),最新版本已無此 case 且無回溯價值
- 跟最近 commit 的實作明顯矛盾(舊段沒被同步更新)
- 段標題或標籤帶日期且超過 1 年(例如 `(2024-08)`),內容已被後續整合

**不必要訊號**:
- 純複述代碼結構(class 欄位列表、function 簽名)— 看代碼就知
- 重複 commit message 內容(changelog 性質)
- 設計取捨的「當下脈絡」已無人在意(例如「為了避免某個已廢功能」)

**動作**:
- 候選清單列出來 → 跟使用者確認(每條給「保留 / 刪除 / 縮短」三選)
- 同意刪除 → `Edit` 移除整段或對應 bullet
- 同意縮短 → 協商最簡 wording 後 edit
- **不主動刪** — 即使 Grep 找不到 API,也可能是 skill 沒索引到的檔。先列候選等 user 拍板

### Step 6: 草稿 + 確認(MANDATORY)

**絕對先把草稿展示給使用者**,清楚標明:
- 要更新哪個 CLAUDE.md(絕對路徑)
- 要**插入**哪一段、加哪幾條 bullet(顯示準備新增的 markdown 內文)
- 要**修改**既有哪一段(diff 風格,標明原本是什麼)
- (若有)拆分提案

使用者回 `OK` / 給修改建議再實際寫。**不要直接 edit 後再說「順便給你看」**。

### Step 7: 寫入 + commit

**寫入工具(依分支選)**:
- **補丁分支**(目標檔已存在) → `Edit`,**永遠不要對既有 CLAUDE.md 用 Write**,Write 會整檔覆蓋
- **首建分支**(目標檔不存在 + 使用者已同意建立) → `Write`,此情境唯一 Write 合法用法

**commit message** 風格參考既有 git log:
- 補丁: `docs(<scope>): CLAUDE.md ... 段補 ...`
- 首建: `docs(<scope>): 首建 CLAUDE.md ...`

- **不主動 push**,除非使用者要求
- **不開新 branch** — docs 改動直接在 working branch 即可(除非 working branch 是受保護的 main / dev,那要看使用者意願)
- **不 commit 被工具自動 touch 的檔**(例如 Xcode 偷改的 `CURRENT_PROJECT_VERSION`、`.DS_Store`),只 add 明確的 md 檔

---

## 重要原則(每次都要遵守)

1. **這是踩坑日誌不是 changelog** — write WHY, not WHAT。WHAT 屬於 commit message
2. **寧短勿長** — 單一段落 ≤ 150 字,超過就拆
3. **不重複** — 已在 git log / 既有 CLAUDE.md 段落寫過的不要再寫
4. **諮詢實作端** — 有 active teammate / agent 時必先 SendMessage 問,不憑 Lead 單一視角拍板
5. **不主動建 task** — 這是 atomic doc 更新,不需 TaskCreate
6. **先回報草稿** — 嚴禁未確認直接 edit
7. **不污染 commit** — 只 add 明確要改的 md,不 -A

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
