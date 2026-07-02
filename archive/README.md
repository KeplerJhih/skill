# Archive — 未啟用的歷史成果（2026-07-02 集中化時收割）

- `experimental-event-hooks/`：test/team_agent 開發的 session 事件回報 hook 套件
  （PreToolUse / PostToolUse / SessionStart / SessionEnd / SubagentStop / UserPromptSubmit → post 到後端），
  含當時配套的 settings / run.sh / notify hooks 修改（team_agent-modifications.patch）。未整合進正式 hooks，保留備查。
- `stash-test-domain.patch`：test/domain checkout 的 stash（team.md / agents / frontend skill 的舊世代 WIP），
  多數概念已被後續版本以不同形式實現，保留備查。

## 2026-07-02 skill 健檢歸檔

- `agent-team/`：舊世代 /team 協議（{BACKEND_SKILL} 佔位符、三角色編制），已被 commands/team.md v3（TeamCreate + 五角色 + 隊友自行偵測）取代；其 MCP 偵測段已移植進 workflow-base。
- `product_manager/`：孤兒 skill（零引用、無觸發詞、簡體、含外來「線程管理」概念）。需要 PM skill 時用 /skill-dev 重寫。
