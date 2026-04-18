#!/bin/bash
# Hook: Stop event — Claude 完成回應時觸發
# stdin 接收 JSON，解析後動態產生通知訊息

INPUT=$(cat)
STOP_REASON=$(echo "$INPUT" | jq -r '.stop_reason // empty')

case "$STOP_REASON" in
  "end_turn")
    MESSAGE="任務已完成"
    ;;
  "max_tokens")
    MESSAGE="回應已達長度上限，可能需要繼續"
    ;;
  *)
    MESSAGE="任務已完成"
    ;;
esac

terminal-notifier -title "Claude" -message "$MESSAGE" -sound default
exit 0
