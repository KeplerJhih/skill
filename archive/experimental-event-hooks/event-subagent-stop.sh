#!/bin/bash
# Hook: SubagentStop — a subagent (Agent/Task tool) has finished.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=event-base.sh
source "$DIR/event-base.sh"
post_event "subagent_stop"
exit 0
