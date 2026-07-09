---
description: 自動建立 Pull Request — 偵測 branch 變更、依 git-pr skill 產生內容、gh CLI 建立
argument-hint: [base_branch]
---

# 自動建立 Pull Request

一鍵自動偵測當前 branch 的變更，產生 PR Title/Description，並透過 `gh` CLI 建立 PR。

**引數**：`$ARGUMENTS`（可選，格式：`[base_branch]`，未指定時自動偵測 repo 預設分支）

---

## 執行流程

### Step 1：前置檢查

依序執行以下檢查，任一失敗即停止並告知使用者：

```bash
# 1. 確認在 git repo 中
git rev-parse --is-inside-work-tree

# 2. 確認 gh CLI 可用
gh --version

# 3. 確認 gh 已登入
gh auth status
```

### Step 2：偵測分支與差異

```bash
# 取得當前 branch
CURRENT_BRANCH=$(git branch --show-current)

# base branch：使用者指定 or 自動偵測 repo 預設分支
BASE_BRANCH="$ARGUMENTS"
[ -z "$BASE_BRANCH" ] && BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's|^origin/||')
[ -z "$BASE_BRANCH" ] && BASE_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)
[ -z "$BASE_BRANCH" ] && BASE_BRANCH=master   # 都偵測不到才退回，並向使用者確認

# 檢查是否有未提交變更
git status --short
```

- 若 `CURRENT_BRANCH` 等於 `BASE_BRANCH`，告知使用者「請先切換到 feature branch 再執行」後結束。
- 若有未提交變更，**提醒使用者**但繼續執行（僅 warn，不阻擋）。

確認有 commit 差異：

```bash
git log --oneline $BASE_BRANCH..HEAD
```

若無差異，告知「當前 branch 與 `$BASE_BRANCH` 沒有差異」後結束。

### Step 3：檢查遠端狀態

```bash
# 確認是否已推送到遠端
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null
```

- 若尚未追蹤遠端 branch，後續會自動 push。
- 若已追蹤，檢查本地是否領先遠端，需要時自動 push。

### Step 4：檢查是否已有 PR

```bash
gh pr view --json number,title,url 2>/dev/null
```

- 若此 branch 已有開啟的 PR，告知使用者「此 branch 已有 PR：[URL]」，詢問是否要更新 PR description，而非重複建立。

### Step 5：蒐集變更資訊

```bash
# commit 摘要
git log --oneline $BASE_BRANCH..HEAD

# 詳細 commit 訊息
git log --format="%h %s%n%b" $BASE_BRANCH..HEAD

# 變更檔案統計
git diff --stat $BASE_BRANCH..HEAD

# 完整 diff
git diff $BASE_BRANCH..HEAD
```

### Step 6：產生 PR Title 與 Description

載入 `git-pr` skill（`Skill("git-pr")`），以 Step 5 蒐集的變更資訊為輸入，依其規範產生 Title 與 Description。

> **單一來源**：Title 的 type 對照與規則、Description 三段結構、格式禁令（無連結 / 無 URI / 無檔案路徑），一律以 `git-pr` skill 及其 `references/pr-template.md` 為準，本 command 不複寫。

### Step 7：推送並建立 PR

先向使用者展示產生的 Title 與 Description 預覽，等待確認後執行：

```bash
# 推送到遠端（若尚未推送）
git push -u origin $CURRENT_BRANCH

# 建立 PR（HEREDOC 傳遞 body 確保格式正確）
gh pr create --base $BASE_BRANCH --title "$TITLE" --body "$(cat <<'EOF'
$DESCRIPTION
EOF
)"
```

### Step 8：回報結果

建立成功後，輸出：

```
✅ PR 已建立！
🔗 $PR_URL
📌 $TITLE
🎯 Base: $BASE_BRANCH ← $CURRENT_BRANCH
```

---

## 邊界情況處理

| 情境 | 處理方式 |
|------|---------|
| 不在 git repo 中 | 提示錯誤並結束 |
| `gh` 未安裝或未登入 | 提示安裝/登入指令並結束 |
| 當前在 base branch 上 | 提示切換到 feature branch |
| 無 commit 差異 | 提示並結束 |
| 已有開啟的 PR | 詢問是否更新 description |
| 有未提交變更 | 警告但不阻擋 |
| push 失敗 | 顯示錯誤訊息，建議手動處理 |
