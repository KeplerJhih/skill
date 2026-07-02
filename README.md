# Claude Code 工具箱

個人 Claude Code 全局工具箱：skills / commands / agents / hooks 的正本，設計成直接作為 `~/.claude` 的 git checkout 使用。

## 安裝

```bash
git clone https://github.com/KeplerJhih/skill.git ~/.claude
cd ~/.claude && bash setup.sh   # 合併 settings.toolkit.json 進 settings.json（既有個人設定保留）
```

## 結構

| 目錄 / 檔案 | 用途 |
|------|------|
| `skills/` | 領域知識包（k8s、terraform、GCP/AWS/阿里雲、DBA、部署…），漸進揭露式載入 |
| `commands/` | Slash commands（`/doit`、`/team`、`/gcp`、`/aws`、`/aliyun`、`/pr`…） |
| `agents/` | 多 Agent 團隊角色定義（team-lead、backend、frontend、devops、qa…） |
| `hooks/` | 通知與流程 hooks |
| `shared/` | `/doit` 與 `/team` 共用的 workflow 基底 + 新專案範本 |
| `script/init.sh` | 新專案 bootstrap（複製 run.sh / sleep.sh / CLAUDE.md 範本，只補缺不覆蓋） |
| `archive/` | 未啟用的歷史成果，保留備查 |

## 核心原則

- **全局性**：工具箱內容不寫死特定專案名或路徑；專案特定內容放該專案的 `.claude/`（同名覆蓋全局版）。
- **單一正本**：各專案不放工具箱拷貝，避免版本漂移；修改後 commit + push 同步其他機器。

詳見 [CLAUDE.md](CLAUDE.md)。
