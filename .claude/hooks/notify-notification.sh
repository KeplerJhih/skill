#!/bin/bash
# Hook: Notification event — Claude 等待用戶回應時觸發
# stdin 接收 JSON，解析後動態產生通知訊息

INPUT=$(cat)
MESSAGE=$(echo "$INPUT" | jq -r '.notification_message // empty')

if [ -z "$MESSAGE" ]; then
  MESSAGE="需要您的確認"
fi

terminal-notifier -title "Claude" -message "$MESSAGE" -sound default
exit 0
