#!/bin/bash

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
printf "║  📂 工作目錄: %-45s ║\n" "$(pwd)"
if [ -n "$CMUX_BUNDLE_ID" ] && command -v cmux >/dev/null 2>&1; then
  printf "║  🚀 啟動模式: %-45s ║\n" "cmux claude-teams (agent team ready)"
else
  printf "║  🚀 啟動模式: %-45s ║\n" "claude (standard)"
fi
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if [ -n "$CMUX_BUNDLE_ID" ] && command -v cmux >/dev/null 2>&1; then
  # 顯式 in-process：cmux claude-teams 預設注入 --teammate-mode auto（CLI 參數覆蓋 settings.json），
  # auto 在 TMUX shim 下走 tmux 路徑，shim 不支援 respawn-pane（CC 2.1.201 實測）→ named spawn 必敗
  exec cmux claude-teams --teammate-mode in-process --dangerously-skip-permissions "$@"
else
  exec claude --dangerously-skip-permissions "$@"
fi
