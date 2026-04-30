#!/bin/bash
# TaskCompleted hook — 在隊員把 task 標 completed 時做驗收檢查
#
# 輸入：JSON via stdin
# 輸出：
#   exit 0 → 允許完成
#   exit 2 → 拒絕完成，stderr 回饋給隊員（會被要求繼續工作）
#
# 規則：
# 1. 若 task subject 含「契約」「API」「Backend」「endpoint」 → 必須有契約檔產出
#    （檢查 team/contracts/ 至少存在一個 .api.md，且本次 session 內被修改過）
# 2. 永遠記錄到 audit log

set -eo pipefail

LOG_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/team"
CONTRACTS_DIR="$LOG_DIR/contracts"
mkdir -p "$LOG_DIR" "$CONTRACTS_DIR"
LOG="$LOG_DIR/audit.log"

PAYLOAD="$(cat || true)"

if [[ -z "$PAYLOAD" ]]; then
  exit 0
fi

SUBJECT="$(printf '%s' "$PAYLOAD" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('task',{}).get('subject') or d.get('subject') or '')" 2>/dev/null || echo "")"
OWNER="$(printf '%s' "$PAYLOAD" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('task',{}).get('owner') or d.get('owner') or '')" 2>/dev/null || echo "")"

TS="$(date '+%Y-%m-%d %H:%M:%S')"
echo "[$TS] TaskCompleted: owner=$OWNER subject=$SUBJECT" >> "$LOG"

# 檢查：契約相關任務必須有契約檔
if echo "$SUBJECT" | grep -qiE "(契約|api|endpoint|backend|domain|schema)"; then
  if ! find "$CONTRACTS_DIR" -name "*.api.md" -mmin -120 2>/dev/null | grep -q .; then
    echo "此任務看起來與 API 契約相關，但 team/contracts/ 在最近 2 小時內無 .api.md 檔案被建立或修改。" >&2
    echo "請確認契約檔已寫入並包含端點、請求 / 回應 schema、錯誤碼、認證需求，再標記任務完成。" >&2
    exit 2
  fi
fi

exit 0
