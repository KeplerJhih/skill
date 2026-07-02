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
  exec cmux claude-teams --dangerously-skip-permissions "$@"
else
  exec claude --dangerously-skip-permissions "$@"
fi
