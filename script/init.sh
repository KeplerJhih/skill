#!/bin/bash
# 專案 bootstrap / 範本同步：在「專案根目錄」執行
#
# 用法：
#   cd /path/to/project
#   bash ~/.claude/script/init.sh            # run.sh / sleep.sh 同步範本；CLAUDE.md 補缺
#   bash ~/.claude/script/init.sh --mcp      # 另加根目錄 .mcp.json（補缺）
#   bash ~/.claude/script/init.sh --force    # 自訂過的 run.sh / sleep.sh 也強制覆蓋（覆蓋前印 diff）
#
# 語義（2026-07-09 起）：
#   run.sh / sleep.sh ＝ 工具箱管理檔——內容等於任一「範本 git 歷史版本」（即未手改的舊拷貝）
#   → 自動刷新到現行範本；內容自訂過 → 警示跳過，--force 才覆蓋。
#   CLAUDE.md / .mcp.json ＝ 專案內容——只補缺，永不覆蓋。
set -euo pipefail

TOOLKIT="$HOME/.claude"
TPL="$TOOLKIT/shared/templates"
DEST="$(pwd)"

MCP=0; FORCE=0
for a in "$@"; do
  case "$a" in
    --mcp)   MCP=1;;
    --force) FORCE=1;;
    *) echo "❌ 未知參數：${a}（支援 --mcp / --force）"; exit 1;;
  esac
done

case "$DEST" in
  "$HOME"|"$TOOLKIT"|"$TOOLKIT/"*)
    echo "❌ 請在專案根目錄執行（目前在 ${DEST} ）"; exit 1;;
esac

# 列出範本檔在工具箱 git 的所有歷史版本 blob（含現行磁碟版）；git 不可用時輸出可能為空
known_blobs() { # $1: 工具箱 repo 相對路徑
  git -C "$TOOLKIT" log --all --format='%H' -- "$1" 2>/dev/null | while read -r c; do
    git -C "$TOOLKIT" ls-tree "$c" -- "$1" 2>/dev/null | awk '{print $3}'
  done
  git hash-object "$TOOLKIT/$1" 2>/dev/null || true
}

sync_managed() { # $1: 範本檔名（templates/ 下）  $2: 目的地絕對路徑
  local tpl="$TPL/$1" dest="$2" rel="${2#$DEST/}" blob
  if [ ! -e "$dest" ]; then
    cp "$tpl" "$dest" && echo "✅ 建立：$rel"
    return
  fi
  if cmp -s "$tpl" "$dest"; then
    echo "✔️  已最新：$rel"
    return
  fi
  blob="$(git hash-object "$dest" 2>/dev/null || true)"
  if [ -n "$blob" ] && known_blobs "shared/templates/$1" | grep -qx "$blob"; then
    cp "$tpl" "$dest" && echo "🔄 更新（舊範本版 → 現行範本）：$rel"
  elif [ "$FORCE" = 1 ]; then
    echo "⚠️  強制覆蓋自訂內容：${rel}（原內容 diff 如下，可由終端回溯）"
    diff -u "$dest" "$tpl" || true
    cp "$tpl" "$dest" && echo "✅ 已覆蓋：$rel"
  else
    echo "⚠️  跳過：$rel 內容與所有範本版本皆不同（疑似自訂）；確要同步請加 --force"
  fi
}

copy_if_missing() { # $1: 來源  $2: 目的地
  if [ -e "$2" ]; then
    echo "⏭️  已存在，跳過：${2#$DEST/}"
  else
    cp "$1" "$2" && echo "✅ 建立：${2#$DEST/}"
  fi
}

mkdir -p "$DEST/.claude"
sync_managed run.sh   "$DEST/.claude/run.sh"
sync_managed sleep.sh "$DEST/.claude/sleep.sh"
copy_if_missing "$TPL/CLAUDE.md.template" "$DEST/CLAUDE.md"
if [ "$MCP" = 1 ]; then
  copy_if_missing "$TPL/mcp.json" "$DEST/.mcp.json"
fi
chmod +x "$DEST/.claude/run.sh" "$DEST/.claude/sleep.sh" 2>/dev/null || true

echo ""
echo "🚀 完成。啟動：./.claude/run.sh"
echo "   CLAUDE.md 為範本時，首次 session 會引導補完專案地圖"
[ "$MCP" = 1 ] || echo "ℹ️  需要 serena / gcloud 等 MCP 時：bash ~/.claude/script/init.sh --mcp（複製後刪掉用不到的 server）"
