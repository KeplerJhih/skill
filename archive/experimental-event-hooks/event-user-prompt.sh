#!/bin/bash
# Hook: UserPromptSubmit — user has sent a prompt to claude.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=event-base.sh
source "$DIR/event-base.sh"
post_event "user_prompt"
exit 0
