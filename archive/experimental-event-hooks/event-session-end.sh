#!/bin/bash
# Hook: SessionEnd — the claude session has ended cleanly.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=event-base.sh
source "$DIR/event-base.sh"
post_event "session_end"
exit 0
