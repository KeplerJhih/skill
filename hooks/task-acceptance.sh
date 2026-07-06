#!/bin/bash
# TaskCompleted hook — 在隊員把 task 標 completed 時做驗收檢查
#
# 輸入：JSON via stdin
# 輸出：
#   exit 0 → 允許完成
#   exit 2 → 拒絕完成，stderr 回饋給隊員（會被要求繼續工作）
#
# 規則：
# 1. 若 task subject 含「契約」「contract」 → 必須有契約檔產出
#    （在專案內任一 contracts/ 目錄遞迴搜尋 .api.md，近 2 小時內有變動即通過）
# 2. 永遠記錄到 audit log（~/.claude/logs/，不寫專案目錄）
#
# 2026-07-06 修正：subject/owner 改用遞迴找 key（與 task-quality-gate.sh 一致）。
# 舊版寫死 d['task']['subject'] 解析失敗 → subject 永遠空 → 契約檢查從未生效。
# 另加診斷：解析失敗時記 payload 頂層 keys，方便對照實際 schema 迭代。
#
# 2026-07-06 v2（/team 模擬實測後修正）：
# - 觸發正則從 (契約|api|endpoint|backend|domain|schema) 收斂為 (契約|contract)——
#   舊正則讓純實作/前端 task 也被契約 gate 誤攔（實測卡死依賴鏈）。
# - 契約路徑從寫死 team/contracts/ 改為專案內遞迴匹配 *contracts/*.api.md
#   （prune node_modules/.git/vendor，maxdepth 5）——支援子專案/monorepo 佈局。
# - audit log 改寫到 ~/.claude/logs/task-audit.log（行內帶專案路徑），
#   移除在每個專案根 mkdir team/ 的副作用（慢性目錄污染）。

set -eo pipefail

LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/task-audit.log"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

PAYLOAD="$(cat || true)"

if [[ -z "$PAYLOAD" ]]; then
  exit 0
fi

extract() {
  # $1: 逗號分隔的候選 key 清單，遞迴搜尋第一個非空字串值
  printf '%s' "$PAYLOAD" | python3 -c "
import sys, json
KEYS = '$1'.split(',')
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
    print(find(json.load(sys.stdin), KEYS))
except Exception:
    print('')
" 2>/dev/null || echo ""
}

SUBJECT="$(extract 'task_subject,subject')"
OWNER="$(extract 'task_owner,owner,teammate_name')"

TS="$(date '+%Y-%m-%d %H:%M:%S')"
echo "[$TS] [$PROJECT_DIR] TaskCompleted: owner=$OWNER subject=$SUBJECT" >> "$LOG"

# 診斷：subject 解析失敗時記錄 payload 頂層結構（不阻擋，供日後對照實際 schema）
if [[ -z "$SUBJECT" ]]; then
  KEYS_DUMP="$(printf '%s' "$PAYLOAD" | python3 -c "import sys,json; print(sorted(json.load(sys.stdin).keys()))" 2>/dev/null | head -c 300 || echo "unparseable")"
  echo "[$TS] [$PROJECT_DIR] TaskCompleted: ⚠️ subject 解析失敗，payload 頂層 keys=$KEYS_DUMP" >> "$LOG"
  exit 0
fi

# 檢查：明確的契約任務必須有契約檔（專案內任一 contracts/ 目錄，近 2 小時內有變動）
if echo "$SUBJECT" | grep -qiE "(契約|contract)"; then
  if ! find "$PROJECT_DIR" -maxdepth 5 \( -name node_modules -o -name .git -o -name vendor \) -prune -o -type f -path '*contracts/*.api.md' -mmin -120 -print 2>/dev/null | grep -q .; then
    echo "此任務為契約任務，但專案內（任一 contracts/ 目錄）最近 2 小時無 .api.md 檔案被建立或修改。" >&2
    echo "請確認契約檔已寫入並包含端點、請求 / 回應 schema、錯誤碼、認證需求，再標記任務完成。" >&2
    echo "（若契約檔實際已寫在其他位置，請回報 team-lead 調處，不要反覆重試。）" >&2
    exit 2
  fi
fi

exit 0
