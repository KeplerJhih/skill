#!/bin/bash
# UserPromptSubmit hook：偵測 /doit 或 /team 時自動注入閘門提醒（機制強制，不依賴模型自律）
prompt=$(jq -r '.prompt // empty' 2>/dev/null)
case "$prompt" in
  /doit*)
    cat <<'EOF'
🛑 /doit 閘門提醒（UserPromptSubmit hook 自動注入）：在輸出任何用戶可見文字之前，必須依序完成：
1) 以 Skill 工具載入 available skills 清單中名稱含 karpathy-guidelines 的 skill（來自 plugin、名稱帶命名空間，如 andrej-karpathy-skills:karpathy-guidelines——照字面呼叫 "karpathy-guidelines" 會失敗，以清單實際名稱為準）
2) Read("~/.claude/shared/workflow-base.md")
3) 依任務內容載入至少一個專屬 Skill（情境 A 可延後至取得需求後補做）
未完成前不准產出分析、藍圖或詢問。
EOF
    ;;
  /team*)
    cat <<'EOF'
🛑 /team 閘門提醒（UserPromptSubmit hook 自動注入）：在輸出任何用戶可見文字之前，必須依序完成：
1) ToolSearch query="select:SendMessage,TaskList,TaskCreate,TaskUpdate,TaskGet" 載入協作工具 schema（工具 schema 為準，文檔滯後時照實際行為走）
2) Read("~/.claude/shared/workflow-base.md")
3) 以 Skill 工具載入名稱含 karpathy-guidelines 的 skill（plugin 命名空間，以 available skills 清單實際名稱為準），再依任務內容匹配載入專屬 Skill（情境 A 可延後至取得需求後補做）
未完成前不准產出分析、藍圖或詢問。正式 spawn 全 roster 前必跑 pre-flight 探針（team.md 2-c）；探針錯誤含 pane / tmux 字樣 → 停手回報，檢查啟動參數是否被 --teammate-mode 覆蓋（ps -p <pid> -o command=）。
EOF
    ;;
esac
exit 0
