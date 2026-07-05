---
name: update-md
version: 1.0.0
description: 當使用者輸入「update md」、「更新文檔」、「更新 md」、「記錄踩坑」、「寫進 CLAUDE.md」等指令時觸發。收斂當前對話 / 最近 commits 內的踩坑與設計決策,組織成精煉的「踩坑日誌」entry,**先回報草稿等使用者確認**再寫入專案對應的 CLAUDE.md。檔案過長時提議拆到子專案 docs/ 目錄之後引用。
color: yellow
---

# update-md — CLAUDE.md 踩坑日誌維護

## 核心職責

把當前對話 / 最近 commits 中的**踩坑、設計取捨、非顯而易見的決策**收斂成精煉的「踩坑日誌」entry,**只寫入 CLAUDE.md 的「踩坑歷史」段**(`## 踩坑歷史` / `## 踩坑日誌` / `## Pitfalls` 等 H2 標題)。

**這不是 changelog** — git commit 已經是 changelog。CLAUDE.md 是「下次開發回來看,能讓人少踩坑」的索引。

---

## 🔒 Scope Lock(每次觸發都先讀一遍)

**本 skill 只動「踩坑歷史」H2 段**,段外一律不碰:

- ✅ **能動**:`## 踩坑歷史`(或 `## 踩坑日誌` / `## Pitfalls` / `## 踩坑紀錄` 等同義 H2)段內的 bullet / 子段
- ✅ **per-feature 慣例檔**(無統一踩坑段、改採「每功能一個 H2 段 + 踩坑內嵌」,判定見 Step 2-B):可動範圍 = 本次**新增**的功能 H2 段本身;既有功能段仍不可動
- ❌ **不能動**:架構說明、命名慣例、技術棧、目錄結構、API 契約等其他段落 — 即使看到過時也只能「列建議」由 user 主動 opt-in
- ❌ **不能動**:CLAUDE.md 以外的任何檔(代碼、設定、其他 md),除非是拆分到 `docs/pitfall/` 的情境(Step 5)
- ❌ **不主動建段**:若踩坑段不存在,先問 user 要不要建,不擅自插入

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

### Step 2: 識別目標 CLAUDE.md 位置 + 定位踩坑段(自動偵測,不寫死路徑)

#### 2-A. 定位 CLAUDE.md 檔

依以下順序定位,**不假設專案結構**(找到一個就停,不要繼續找):

1. **讀根 `./CLAUDE.md`**(若存在)→ 看是否有子專案地圖(markdown 表格列子目錄 + 對應 CLAUDE.md)。
   - 有地圖且本次變更對應到某子專案 → 用該子 CLAUDE.md,進 2-B
   - 沒地圖 / 地圖找不到對應 → 進步驟 2
2. **直讀代碼目錄內 CLAUDE.md**(地圖型 fallback 失敗時):
   - 改動集中在單一子目錄 → 從變更檔案所在路徑往上找最近的 `CLAUDE.md`(例如改 `backend/python/app/x.py` → 找 `backend/python/CLAUDE.md`)
   - 改動跨多個子目錄 → 根 `./CLAUDE.md`(沒有就走首建分支)
   - 改動只在 `~/.claude/skills/<name>/`（工具箱 skill） → 對應的 `SKILL.md`(**不是 CLAUDE.md**)
   - **若使用者明確說「在 X 目錄用」/「就改這個專案的」→ 直接用 `X/CLAUDE.md`**,跳過步驟 1 的地圖查找
3. **檢查目標檔是否存在**(用 `ls <target>` 或 `wc -l <target>` 探測):
   - 存在 → 進 2-B 定位踩坑段
   - 不存在 → 走「首建分支」(見 Step 2.5)

> **設計取捨**:`./CLAUDE.md` 是「全專案地圖」、各子目錄 `CLAUDE.md` 是「實際踩坑現場」、user 層 `~/.claude/CLAUDE.md` 是「通用工作原則」(**不寫專案踩坑**)。Monorepo / 多子專案用地圖定位;單一專案 / 直接在代碼目錄內用時走第 2 步直讀,不繞遠路。

#### 2-B. 定位「踩坑歷史」H2 段(scope lock 的關鍵)

用 `Grep` 找目標 CLAUDE.md 內符合的 H2 標題,**正則建議**:

```bash
grep -nE '^## (踩坑|Pitfalls|踩坑歷史|踩坑日誌|踩坑紀錄|踩坑記錄)' <target>
```

判定結果:

- **找到 1 個** → 記下行號,該行到「下一個 `## ` 或檔尾」就是**唯一可動範圍**。Step 6/7 的 Edit `old_string` 必須落在此範圍內
- **找到多個**(例如同檔有「## 踩坑歷史」+「## 已解決踩坑」)→ 列出來請 user 指定要寫進哪一個,不自選
- **找不到,但檔內多個功能 H2 段內嵌踩坑子段** → 視為 **per-feature 慣例**(每功能一段、踩坑內嵌)。偵測:`grep -cE '^\*\*踩(坑|雷)|^\*\*設計取捨' <target>` ≥ 2。此時**跳過 Step 2.6 的「建統一踩坑段」詢問**,直接提議「新增本次功能的 H2 段」;段標題、插入位置與草稿仍走 Step 6 確認,不擅自寫入。唯一可動範圍 = 本次新增的功能段(Step 5.5 過時掃描與 Step 5 長度檢查對新段免跑)
- **找不到且無 per-feature 跡象** → 走「Step 2.6 新增踩坑段分支」(不主動插入)

### Step 2.5: 首建 CLAUDE.md 分支(目標檔不存在時)

**先詢問使用者是否要建立**,絕不主動建檔:

```
目前 <target absolute path> 不存在,本次踩坑要寫進去需先建立 CLAUDE.md。是否建立?

A. 是 — 以 `~/.claude/shared/templates/CLAUDE.md.template` 為骨架,本次踩坑作為首條 entry
B. 否,我先別寫了(中止流程)
C. 是,但這個路徑不對 — 我告訴你正確位置
```

**使用者選 A**:
- 若 template 存在 → 讀 template + 替換占位符(`{PROJECT_NAME}` 等用 dir name 或 `package.json`/`go.mod`/`Cargo.toml` 等 manifest 推論)
- 若 template 不存在（罕見，如新機器尚未同步）→ 用最小骨架:`# <ProjectName>\n\n` + 「## <feature> 踩坑」一段
- 用 `Write` 工具寫入(此情境唯一 Write 合法用法,見 Step 7)

**使用者選 B**:中止,不寫任何檔。

**使用者選 C**:重新走 Step 2.5 用新路徑。

### Step 2.6: 新增「踩坑歷史」段分支(目標檔存在但無踩坑段時)

**先詢問**,絕不主動插入:

```
<target> 內找不到「## 踩坑歷史」相關 H2 段,是否新增?

A. 是 — 在檔尾新增 `## 踩坑歷史` H2 段,本次踩坑作為首條 entry
B. 是,但用其他段標題(例如 `## Pitfalls`)— 請告訴我要用什麼
C. 是,但插在指定位置 — 請告訴我要放在哪段之後
D. 否,我先別寫了(中止流程)
```

選 A/B/C 後再進 Step 3。**永遠不主動決定段標題或位置**。

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

- **單一段落 ≤ 150 字**
- 列「為什麼這樣設計、碰過什麼坑、新檔案放哪裡」
- 用 markdown bullet,簡短直白
- 對技術細節精確引用 — i18n key 名、struct 名、modifier 名、檔案路徑
- 引用具體檔案絕對路徑,而非「某個 view」這種模糊指涉

### Step 5: 檢查踩坑段長度(僅補丁分支)

> **首建分支跳過本步驟** — 新建檔不必檢查長度。
>
> **本步驟只看「踩坑歷史」H2 段**,不掃整檔其他段 — scope lock 規則。

**兩條觸發條件**(任一達標 → 主動提議拆分):

1. **踩坑段行數**:從 `## 踩坑歷史` 到下個 `## ` 之間 > 400 行
2. **踩坑段字數**:該 H2 段字數 > 1500 字(中文 1 字符算 1)

抓踩坑段長度的做法(假設踩坑段標題為 `## 踩坑歷史`):
```bash
awk '/^## 踩坑歷史/{flag=1; next} /^## /{flag=0} flag' <target> | wc -lm
```

**拆分動作**(拆到 `docs/pitfall/` 主題目錄,不是 `docs/` 根):

- 把踩坑段內的「子主題 H3 段」抽到 CLAUDE.md 所在子專案的 `docs/pitfall/<topic>.md`
  - 例如:`backend/python/docs/pitfall/db-migration.md`、`native/ios/orua/docs/pitfall/icloud-sync.md`
- CLAUDE.md 的「踩坑歷史」段內只留**一句摘要 + 相對路徑連結**:
  - 例如:`- iCloud 同步踩坑 → 詳見 [docs/pitfall/icloud-sync.md](docs/pitfall/icloud-sync.md)`
- 若 `docs/pitfall/` 目錄不存在,先建立(`mkdir -p`)
- **拆分對象限定踩坑相關 H3** — 不要把其他段的內容順手搬到 `docs/pitfall/`

**不要主動拆** — 給使用者選擇:`A. 拆到 docs/pitfall/ / B. 直接加進踩坑段 / C. 你決定`。

**為何兩條都要**:行數抓「累積太多 entry」的情況;字數抓「某個 entry 寫太長」的情況 — 後者即使行數沒爆,讀者翻到那段也會被淹沒,獨立成檔比較好讀。

### Step 5.5: 段內偵測過時 entry(限踩坑段內,可選)

**只掃「踩坑歷史」段內的 bullet / 子段**,不掃其他 H2。目的:踩坑段累積過時 entry 比沒寫還糟(誤導)。

**過時訊號**(在踩坑段內找到任一就標記):
- entry 提到的 API / class / function / 檔案名稱,用 `Grep`/`Glob` 在 source code 找不到(被重構/移除)
- 提到「未實作」「待補」「Tier X 未上」的狀態,而 `git log` 顯示後續已完成
- 提到某版本舊行為(「v2.1 重構前」/「v1 schema」),最新版本已無此 case 且無回溯價值
- 跟最近 commit 的實作明顯矛盾
- entry 標題或標籤帶日期且超過 1 年(例如 `(2024-08)`),內容已被後續整合

**動作**:
- 候選清單列出來 → user 每條給「保留 / 刪除 / 縮短」三選
- 同意刪除 → `Edit` 移除對應 bullet(**範圍仍鎖在踩坑段內**)
- 同意縮短 → 協商最簡 wording 後 edit
- **不主動刪** — 即使 Grep 找不到 API,也可能是 skill 沒索引到的檔。先列候選等 user 拍板

### Step 5.6: Out-of-Scope 觀察(僅列建議,不寫進主草稿)

若**順帶看到「踩坑段之外」的其他段疑似過時 / 矛盾**(例如根 CLAUDE.md 的「## 架構」段有舊路徑),**只列建議清單**回報給 user,**絕不寫進本次主草稿、絕不主動 Edit**:

```
📋 段外觀察(本次不動,僅提示):
- <某 H2 段>:<疑似過時的點>(若要修請另外開任務 / 明確指示)
- ...
```

User 若回「順手清一下 X 段」→ 才開新一輪確認流程處理(視為**新任務**,不混入本次踩坑寫入)。這是 scope lock 的核心執行規則。

### Step 6: 草稿 + 確認(MANDATORY)

**絕對先把草稿展示給使用者**,清楚標明:
- 要更新哪個 CLAUDE.md(絕對路徑)
- **本次唯一可動範圍**:`## 踩坑歷史` 段(行 X 到行 Y)— 明示 scope lock
- 要**插入**踩坑段內哪一條 bullet(顯示準備新增的 markdown 內文)
- 要**修改**踩坑段內既有哪一條(diff 風格,標明原本是什麼)
- (若有)拆分到 `docs/pitfall/` 提案
- (若有)Step 5.6 的「段外觀察」清單 — 標明本次**不動**,只給 user 知道

**模板**:

```
✏️ 本次寫入計畫(scope: 僅 <target>:L<start>-L<end> 的 ## 踩坑歷史 段)

[新增]
- bullet 1: ...
- bullet 2: ...

[修改 / 刪除既有]
- 第 X 條原文:...
  → 改為:...

[段外觀察(本次不動)]
- ## 架構 段 L42 提到舊 API foo(),已重構為 bar() — 需要的話另行處理
```

使用者回 `OK` / 給修改建議再實際寫。**不要直接 edit 後再說「順便給你看」**。

### Step 7: 寫入 + commit

**寫入工具(依分支選)**:
- **補丁分支**(目標檔已存在) → `Edit`,**永遠不要對既有 CLAUDE.md 用 Write**,Write 會整檔覆蓋
- **首建分支**(目標檔不存在 + 使用者已同意建立) → `Write`,此情境唯一 Write 合法用法
- **拆分到 `docs/pitfall/<topic>.md`** → 新檔用 `Write`(此檔本就不存在);原 CLAUDE.md 用 `Edit` 替換為摘要+連結

**Edit `old_string` 範圍限制(scope lock 強制執行)**:

- `old_string` **必須完全落在 Step 2-B 鎖定的踩坑段範圍內**(行號 X 到行號 Y)
- 若 `old_string` 跨段(含到其他 H2)→ **立刻中止**,重新縮小範圍
- 一次 Edit 只動一塊,不批次跨 entry 改

**commit message** 風格參考既有 git log:
- 補丁: `docs(<scope>): CLAUDE.md 踩坑歷史補 ...`
- 首建: `docs(<scope>): 首建 CLAUDE.md ...`
- 拆分: `docs(<scope>): 踩坑歷史 <topic> 段拆到 docs/pitfall/`

- **只 add 本次明確改的檔**:目標 CLAUDE.md +(若有)新建的 `docs/pitfall/<topic>.md`
- **不主動 push**,除非使用者要求
- **不開新 branch** — docs 改動直接在 working branch 即可(除非 working branch 是受保護的 main / dev,那要看使用者意願)
- **不 commit 被工具自動 touch 的檔**(例如 Xcode 偷改的 `CURRENT_PROJECT_VERSION`、`.DS_Store`),只 add 明確的 md 檔
- **絕對不用 `git add -A` / `git add .`** — scope lock 在 commit 階段也要守住

---

## 重要原則(每次都要遵守)

1. **Scope Lock — 只動踩坑段** — Edit 範圍嚴格限制在 `## 踩坑歷史` H2 段內;段外問題只「列建議」由 user 主動 opt-in,絕不混入本次寫入
2. **這是踩坑日誌不是 changelog** — write WHY, not WHAT。WHAT 屬於 commit message
3. **寧短勿長** — 單一段落 ≤ 150 字,超過就拆到 `docs/pitfall/`
4. **不重複** — 已在 git log / 既有 CLAUDE.md 段落寫過的不要再寫
5. **諮詢實作端** — 有 active teammate / agent 時必先 SendMessage 問,不憑 Lead 單一視角拍板
6. **不主動建 task** — 這是 atomic doc 更新,不需 TaskCreate
7. **先回報草稿** — 嚴禁未確認直接 edit
8. **不污染 commit** — 只 add 明確要改的 md(目標 CLAUDE.md + 可能的 `docs/pitfall/<topic>.md`),絕不 `-A` / `.`

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
