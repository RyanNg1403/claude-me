#!/bin/bash
# claude-me daemon status — show daemon registration state

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "$SCRIPT_DIR/utils.sh"

PLIST_LABEL="com.claude-me.daily-notify"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"

HOUR="$(get_config_value daemon_hour)"
MINUTE="$(get_config_value daemon_minute)"
HOUR="${HOUR:-9}"
MINUTE="${MINUTE:-0}"
SCHEDULE_STR="$(printf '%02d:%02d' "$HOUR" "$MINUTE")"

if [[ ! -f "$PLIST_PATH" ]]; then
  echo "claude-me daemon: DISABLED"
  echo "  Plist not found: $PLIST_PATH"
  echo ""
  echo "To enable: clm daemon enable"
  exit 0
fi

# launchctl list <label> exits 0 iff the label is exactly loaded.
# Avoids substring matches against unrelated labels.
if launchctl list "$PLIST_LABEL" >/dev/null 2>&1; then
  echo "claude-me daemon: ENABLED (loaded)"
else
  echo "claude-me daemon: REGISTERED but NOT LOADED"
fi

echo "  Schedule:  every day at $SCHEDULE_STR"
echo "  Plist:     $PLIST_PATH"
echo "  Log:       $LOG_DIR/daemon.log"

if command -v terminal-notifier &>/dev/null; then
  tn_version="$(terminal-notifier -version 2>&1 | head -1 || echo "unknown")"
  echo "  Backend:   $tn_version"
else
  echo "  Backend:   MISSING (brew install terminal-notifier)"
fi
