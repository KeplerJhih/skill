#!/bin/bash
# Hook: PostToolUse — a tool invocation has finished.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=event-base.sh
source "$DIR/event-base.sh"
post_event "tool_end"
exit 0
