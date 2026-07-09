# 通用工作原則（user 層，所有專案生效）

- **角色定位**：不要盲猜，凡事有問題先看代碼再回報；不要硬凹，有錯就修正。
- **調用即審視**：調用 skills / commands / agents 時，發現內容有**誤導、過時、自相矛盾或可優化**之處，主動提出具體方案——不打斷當前任務，於完成回報時附帶「工具箱優化建議」段，由用戶決定是否採納。
- **層級關係**：本檔與專案根目錄 `CLAUDE.md` 疊加生效；內容衝突時以專案層（更具體）為準。
- **工具箱**：正本在 `~/.claude`（git repo，remote: github.com/KeplerJhih/skill）。修改 skills / commands / agents 後記得 commit + push；**各專案不得放工具箱拷貝**（會遮蔽全域版本造成漂移），專案差異寫在該專案 CLAUDE.md。
- **工具箱全局性（核心概念）**：`~/.claude` 是**全局的**——skills / commands / agents / shared 服務所有專案，內容不得寫死特定專案名、路徑或場景。特定專案使用的內容放**專案級**（該專案的 `.claude/skills/` 等，與全局同名即覆蓋全局版）；必要時該專案另行安排專案級 repo 管理。**判斷標準**：換一台機器 / 換一個專案開 session 該名詞仍成立（真實雲資源、叢集名）→ 可寫；不成立（某專案的檔案安排、當下對話的例子）→ 不可寫。
- **標準流程入口**：`/doit`（單人 Tech Lead）、`/team`（多 Agent 團隊）。兩者共用 `~/.claude/shared/workflow-base.md`；`/team` 隊友（`agents/*`）另共用 `~/.claude/shared/teammate-base.md`（協作工具載入 / 三鐵律 / 終止流程，第零步 Read）。
- **新專案 bootstrap / 範本同步**：在專案根目錄執行 `bash ~/.claude/script/init.sh`——`run.sh` / `sleep.sh` 為工具箱管理檔：內容等於範本 git 歷史任一版本（未手改）即自動刷新到現行版，自訂過則警示跳過（`--force` 強制覆蓋、覆蓋前印 diff）；`CLAUDE.md` 與 `.mcp.json`（`--mcp` 選配）為專案內容，只補缺不覆蓋。範本修正後到各專案跑一次 init.sh 即可傳播。
