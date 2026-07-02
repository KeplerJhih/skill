#!/bin/bash
# Shared library for Team Agent hook scripts.
#
# Each event-*.sh script sources this file and calls:
#     post_event "<event_type>"
#
# Conventions per CONTRACT.md §7:
#   - Reads the original hook stdin JSON.
#   - Wraps it as: {"wrapper_id": "...", "type": "...", "payload": <original>}
#   - POSTs to ${AGENTCTL_BACKEND:-http://127.0.0.1:8765}/api/events.
#   - All curl calls use -m 1 || true so a missing backend never blocks claude.

set -u

post_event() {
  local event_type="$1"
  local backend="${AGENTCTL_BACKEND:-http://127.0.0.1:8765}"
  local wrapper_id="${AGENTCTL_WRAPPER_ID:-}"

  # Read stdin (the original hook payload). May be empty.
  local input
  input="$(cat || true)"
  if [ -z "$input" ]; then
    input="{}"
  fi

  # Build envelope. Prefer jq when available; fall back to a hand-rolled
  # envelope using bash heredoc (payload is embedded verbatim).
  local body
  if command -v jq >/dev/null 2>&1; then
    body="$(printf '%s' "$input" | jq -c \
      --arg w "$wrapper_id" \
      --arg t "$event_type" \
      '{wrapper_id:$w, type:$t, payload:.}')" || body=""
  fi
  if [ -z "${body:-}" ]; then
    # Minimal fallback envelope. The payload is whatever stdin gave us; if
    # it isn't valid JSON the backend will 400 but we won't break claude.
    body="{\"wrapper_id\":\"${wrapper_id}\",\"type\":\"${event_type}\",\"payload\":${input}}"
  fi

  curl -sS -m 1 -X POST "${backend}/api/events" \
    -H 'Content-Type: application/json' \
    -d "$body" >/dev/null 2>&1 || true
}
