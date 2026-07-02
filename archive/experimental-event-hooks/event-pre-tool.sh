#!/bin/bash
# Hook: PreToolUse — claude is about to invoke a tool. Carries
# tool_name / tool_input / tool_use_id; backend uses these to maintain
# active_tools and (for Agent/Task) subagents.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=event-base.sh
source "$DIR/event-base.sh"
post_event "tool_start"
exit 0
