#!/bin/bash
# TaskCreated hook — 在隊員建立 task 時做品質檢查
#
# 輸入：JSON via stdin（包含 task subject、description、metadata 等）
# 輸出：
#   exit 0  → 允許建立
#   exit 2  → 拒絕建立，stderr 內容會回饋給建立者
#
# 規則（v1，溫和但有用）：
# 1. subject 太短（< 6 字）→ 拒絕，要求補完
# 2. description 為空 → 拒絕
# 3. 永遠記錄到 audit log（~/.claude/logs/，不寫專案目錄）
#
# 2026-07-06 v2：audit log 改寫到 ~/.claude/logs/task-audit.log（行內帶專案路徑），
# 移除在每個專案根 mkdir team/ 的副作用；並修正 debug 行在 $TS 定義前引用的 bug。

set -eo pipefail

LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/task-audit.log"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

PAYLOAD="$(cat || true)"

if [[ -z "$PAYLOAD" ]]; then
  exit 0
fi

SUBJECT="$(printf '%s' "$PAYLOAD" | python3 -c "
import sys, json
KEYS = ['task_subject', 'subject']
def find(d, keys):
    if isinstance(d, dict):
        for k in keys:
            if k in d and isinstance(d[k], str) and d[k]:
                return d[k]
        for v in d.values():
            r = find(v, keys)
            if r:
                return r
    elif isinstance(d, list):
        for v in d:
            r = find(v, keys)
            if r:
                return r
    return ''
try:
    d = json.load(sys.stdin)
    print(find(d, KEYS))
except Exception:
    print('')
" 2>/dev/null || echo "")"
DESC="$(printf '%s' "$PAYLOAD" | python3 -c "
import sys, json
KEYS = ['task_description', 'description']
def find(d, keys):
    if isinstance(d, dict):
        for k in keys:
            if k in d and isinstance(d[k], str) and d[k]:
                return d[k]
        for v in d.values():
            r = find(v, keys)
            if r:
                return r
    elif isinstance(d, list):
        for v in d:
            r = find(v, keys)
            if r:
                return r
    return ''
try:
    d = json.load(sys.stdin)
    print(find(d, KEYS))
except Exception:
    print('')
" 2>/dev/null || echo "")"

TS="$(date '+%Y-%m-%d %H:%M:%S')"

# Debug: 若 subject 仍空，記錄完整 payload 以利診斷（截斷到 1KB）
if [[ -z "$SUBJECT" ]]; then
  echo "[$TS] [$PROJECT_DIR] TaskCreated DEBUG payload (subject not found): ${PAYLOAD:0:1024}" >> "$LOG"
fi

echo "[$TS] [$PROJECT_DIR] TaskCreated: $SUBJECT" >> "$LOG"

if [[ ${#SUBJECT} -lt 6 ]]; then
  echo "Task subject 過短（< 6 字），請補完成更具描述性的標題（例如「實作購物車 add-to-cart API」而非「加 API」）。" >&2
  exit 2
fi

if [[ -z "$DESC" ]]; then
  echo "Task description 為空。請補上：要做什麼、驗收條件、相關檔案路徑。" >&2
  exit 2
fi

exit 0
