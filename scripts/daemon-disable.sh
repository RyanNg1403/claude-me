#!/bin/bash
# claude-me daemon disable — unregister the daily notification LaunchAgent
#
# Safe to run when the daemon isn't enabled (no-op + informative message).

set -euo pipefail

PLIST_LABEL="com.claude-me.daily-notify"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"

if [[ ! -f "$PLIST_PATH" ]]; then
  echo "claude-me daemon not registered (no plist at $PLIST_PATH)"
  exit 0
fi

if launchctl list "$PLIST_LABEL" >/dev/null 2>&1; then
  launchctl unload "$PLIST_PATH" 2>/dev/null || true
  echo "  Unloaded LaunchAgent"
fi

rm -f "$PLIST_PATH"
echo "claude-me daemon disabled"
echo "  Removed: $PLIST_PATH"
