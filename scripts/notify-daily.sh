#!/bin/bash
# claude-me daily notification — fires one macOS notification about a corpus entry
#
# Path 1 (passive) implementation:
#   - Picks one entry via pick-entry.py (weighted random: stale / unverified / fresh)
#   - Fires a passive terminal-notifier banner with the entry's description
#   - Click on the notification opens the .md file in VS Code via vscode:// URL
#   - Actions (verify / delete) happen via separate CLI commands: clm verify, clm delete
#
# Why passive (not action buttons): terminal-notifier 2.0.0 (current brew release)
# dropped the -actions flag. Rebuilding with a Swift helper app bundle would
# unlock real action buttons — deferred to a future Path 2 upgrade if the
# passive daemon proves engaging.
#
# Callers: the LaunchAgent at ~/Library/LaunchAgents/com.claude-me.daily-notify.plist
# (runs daily per config.json daemon_hour/daemon_minute), or `clm daemon test`
# for a manual fire-right-now.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "$SCRIPT_DIR/utils.sh"

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
if ! command -v terminal-notifier &>/dev/null; then
  log "daemon: terminal-notifier not installed, cannot fire notification"
  echo "terminal-notifier not installed. Run: brew install terminal-notifier" >&2
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  log "daemon: python3 not available, cannot pick entry"
  exit 1
fi

if [[ ! -d "$CORPUS_DIR" ]]; then
  log "daemon: no corpus dir at $CORPUS_DIR, skipping"
  exit 0
fi

# ---------------------------------------------------------------------------
# Pick one entry via the weighted-random picker
# ---------------------------------------------------------------------------
STALE_W="$(get_config_value daemon_stale_weight)"
UNV_W="$(get_config_value daemon_unverified_weight)"
FRESH_W="$(get_config_value daemon_fresh_weight)"
STALE_DAYS="$(get_config_value daemon_stale_threshold_days)"

STALE_W="${STALE_W:-3}"
UNV_W="${UNV_W:-2}"
FRESH_W="${FRESH_W:-1}"
STALE_DAYS="${STALE_DAYS:-30}"

PICKED="$(python3 "$SCRIPT_DIR/pick-entry.py" "$CORPUS_DIR" "$STALE_W" "$UNV_W" "$FRESH_W" "$STALE_DAYS")"

if [[ -z "$PICKED" ]]; then
  log "daemon: empty corpus, nothing to surface"
  exit 0
fi

if [[ ! -f "$PICKED" ]]; then
  log "daemon: picker returned non-existent path: $PICKED"
  exit 1
fi

# ---------------------------------------------------------------------------
# Extract notification fields from frontmatter
# ---------------------------------------------------------------------------
DESCRIPTION="$(get_frontmatter_field "$PICKED" "description")"
REL_PATH="${PICKED#"$CORPUS_DIR"/}"

if [[ -z "$DESCRIPTION" ]]; then
  DESCRIPTION="(no description)"
fi

# VS Code URL scheme: vscode://file<absolute_path>
# $PICKED is already absolute and starts with /, so the concatenation is valid.
VSCODE_URL="vscode://file${PICKED}"

# ---------------------------------------------------------------------------
# Fire the notification
# ---------------------------------------------------------------------------
# Intentionally NOT using -sender. Setting -sender routes the notification
# through that app's notification permission, and if the sender app doesn't
# have permission granted (common for VS Code, which doesn't register with
# macOS notification system until it first opens a notification), the
# banner gets silently eaten. The default terminal-notifier icon is less
# pretty but reliably delivered.
#
# -group claude-me-daily coalesces previous day's notification in Notification
# Center so unread ones don't pile up across days.
log "daemon: firing notification for $REL_PATH"

terminal-notifier \
  -title "claude-me — still true?" \
  -subtitle "$REL_PATH" \
  -message "$DESCRIPTION" \
  -open "$VSCODE_URL" \
  -group "claude-me-daily" \
  >/dev/null 2>&1 || {
    log "daemon: terminal-notifier failed"
    exit 1
  }

log "daemon: notification dispatched"
