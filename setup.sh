#!/bin/bash
# 新機器一次性設定：把 settings.toolkit.json（hooks / env / plugins）合併進 ~/.claude/settings.json
# 合併策略：既有值優先（不覆蓋本機個人設定，如 model / statusLine），只補缺少的 key
set -e
cd "$(dirname "$0")"

command -v jq >/dev/null || { echo "❌ 需要 jq：brew install jq"; exit 1; }

S="$HOME/.claude/settings.json"
[ -f "$S" ] || echo '{}' > "$S"

jq -s '.[0] * .[1]' settings.toolkit.json "$S" > "$S.tmp" && mv "$S.tmp" "$S"

echo "✅ settings 已合併（既有個人設定保留）。"
echo "   plugins / hooks 需重啟 claude 生效。"
command -v cmux >/dev/null || echo "ℹ️  未安裝 cmux（/team 的 tmux 模式會用到，可選）"
