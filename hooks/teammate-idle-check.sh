#!/bin/bash
# TeammateIdle hook — 在隊員即將 idle 時記錄並做輕量檢查
#
# 輸入：JSON via stdin
# 輸出：
#   exit 0 → 允許 idle
#   exit 2 → 不允許 idle，stderr 回饋會讓隊員繼續工作
#
# v1 行為：純記錄。不阻擋（避免無限循環）。
# 未來可擴充：檢查是否仍有此 owner 的 pending task 未認領。

set -eo pipefail

LOG_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/team"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/audit.log"

PAYLOAD="$(cat || true)"

NAME="$(printf '%s' "$PAYLOAD" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('teammate',{}).get('name') or d.get('name') or 'unknown')" 2>/dev/null || echo "unknown")"

TS="$(date '+%Y-%m-%d %H:%M:%S')"
echo "[$TS] TeammateIdle: $NAME" >> "$LOG"

exit 0
