#!/bin/bash
# Hook: SessionStart — claude has started a new session in this terminal.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=event-base.sh
source "$DIR/event-base.sh"
post_event "session_start"
exit 0
