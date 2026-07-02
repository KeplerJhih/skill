#!/bin/bash
# SessionStart hook：檢查 ~/.claude 工具箱是否落後 remote，落後就提醒（不自動 pull）
cd "$HOME/.claude" || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
git fetch --quiet origin main 2>/dev/null || exit 0
behind=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo 0)
if [ "${behind:-0}" -gt 0 ]; then
  echo "📦 工具箱 ~/.claude 落後 remote ${behind} 個 commit，記得 cd ~/.claude && git pull"
fi
exit 0
