#!/bin/bash
# claude-me daemon enable — register the daily notification LaunchAgent
#
# Fills out the plist template using the schedule from config.json
# (daemon_hour / daemon_minute), writes it to ~/Library/LaunchAgents/,
# loads it via launchctl, then fires a test notification immediately so
# macOS shows the one-time notification permission prompt while the user
# is paying attention.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "$SCRIPT_DIR/utils.sh"

PLIST_LABEL="com.claude-me.daily-notify"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
NOTIFY_SCRIPT="$SCRIPT_DIR/notify-daily.sh"
DAEMON_LOG="$LOG_DIR/daemon.log"
TEMPLATE="$SCRIPT_DIR/daemon-plist.template"

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
if ! command -v terminal-notifier &>/dev/null; then
  echo "ERROR: terminal-notifier not installed." >&2
  echo "  Run: brew install terminal-notifier" >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
  echo "ERROR: plist template not found: $TEMPLATE" >&2
  exit 1
fi

if [[ ! -f "$NOTIFY_SCRIPT" ]]; then
  echo "ERROR: notify-daily.sh not found: $NOTIFY_SCRIPT" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Read + validate schedule from config
# ---------------------------------------------------------------------------
HOUR="$(get_config_value daemon_hour)"
MINUTE="$(get_config_value daemon_minute)"
HOUR="${HOUR:-9}"
MINUTE="${MINUTE:-0}"

if ! [[ "$HOUR" =~ ^[0-9]+$ ]] || (( HOUR < 0 || HOUR > 23 )); then
  echo "ERROR: invalid daemon_hour in config.json: $HOUR (must be 0-23)" >&2
  exit 1
fi
if ! [[ "$MINUTE" =~ ^[0-9]+$ ]] || (( MINUTE < 0 || MINUTE > 59 )); then
  echo "ERROR: invalid daemon_minute in config.json: $MINUTE (must be 0-59)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Prepare directories
# ---------------------------------------------------------------------------
mkdir -p "$LOG_DIR"
mkdir -p "$(dirname "$PLIST_PATH")"

# ---------------------------------------------------------------------------
# Unload existing plist if present (idempotent re-enable)
# ---------------------------------------------------------------------------
# Use exact-label lookup, not substring grep, so we don't false-positive on
# unrelated labels containing "com.claude-me.daily-notify" as a substring.
if launchctl list "$PLIST_LABEL" >/dev/null 2>&1; then
  launchctl unload "$PLIST_PATH" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Render template → plist
# ---------------------------------------------------------------------------
# Using | as sed delimiter since paths contain /
sed \
  -e "s|__LABEL__|$PLIST_LABEL|g" \
  -e "s|__SCRIPT__|$NOTIFY_SCRIPT|g" \
  -e "s|__HOUR__|$HOUR|g" \
  -e "s|__MINUTE__|$MINUTE|g" \
  -e "s|__LOG__|$DAEMON_LOG|g" \
  "$TEMPLATE" > "$PLIST_PATH"

# ---------------------------------------------------------------------------
# Load the agent
# ---------------------------------------------------------------------------
launchctl load "$PLIST_PATH"

SCHEDULE_STR="$(printf '%02d:%02d' "$HOUR" "$MINUTE")"

echo "claude-me daemon enabled"
echo "  Schedule:  every day at $SCHEDULE_STR"
echo "  Plist:     $PLIST_PATH"
echo "  Log:       $DAEMON_LOG"
echo ""
echo "Firing one test notification now so macOS prompts for notification"
echo "permission while you're paying attention. Click 'Allow' if asked —"
echo "future daily notifications will then appear silently."
echo ""

sleep 1
bash "$NOTIFY_SCRIPT"

echo ""
echo "Daemon is live. It will next fire at $SCHEDULE_STR local time."
echo "Disable any time with: clm daemon disable"
