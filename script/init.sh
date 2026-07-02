#!/bin/bash
# 專案 bootstrap：在「專案根目錄」執行，把工具箱範本複製到當前目錄
#
# 用法：
#   cd /path/to/project
#   bash ~/.claude/script/init.sh          # 基本：run.sh / sleep.sh / CLAUDE.md
#   bash ~/.claude/script/init.sh --mcp    # 另加根目錄 .mcp.json（serena / gcloud 等）
#
# 原則：只補缺，絕不覆蓋已存在的檔案。
set -euo pipefail

TPL="$HOME/.claude/shared/templates"
DEST="$(pwd)"

case "$DEST" in
  "$HOME"|"$HOME/.claude"|"$HOME/.claude/"*)
    echo "❌ 請在專案根目錄執行（目前在 ${DEST} ）"; exit 1;;
esac

copy() {
  if [ -e "$2" ]; then
    echo "⏭️  已存在，跳過：${2#$DEST/}"
  else
    cp "$1" "$2" && echo "✅ 建立：${2#$DEST/}"
  fi
}

mkdir -p "$DEST/.claude"
copy "$TPL/run.sh"             "$DEST/.claude/run.sh"
copy "$TPL/sleep.sh"           "$DEST/.claude/sleep.sh"
copy "$TPL/CLAUDE.md.template" "$DEST/CLAUDE.md"
if [ "${1:-}" = "--mcp" ]; then
  copy "$TPL/mcp.json" "$DEST/.mcp.json"
fi
chmod +x "$DEST/.claude/run.sh" "$DEST/.claude/sleep.sh" 2>/dev/null || true

echo ""
echo "🚀 完成。啟動：./.claude/run.sh"
echo "   CLAUDE.md 目前是範本，首次 /doit 會引導補完專案地圖"
[ "${1:-}" = "--mcp" ] || echo "ℹ️  需要 serena / gcloud 等 MCP 時：bash ~/.claude/script/init.sh --mcp（複製後刪掉用不到的 server）"
