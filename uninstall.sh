#!/bin/bash
# me-agent uninstaller
# Removes symlink and SessionEnd hook. Optionally purges data.

set -euo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SKILLS_DIR="$CLAUDE_HOME/skills"
SYMLINK_TARGET="$SKILLS_DIR/me-agent"
SETTINGS_FILE="$CLAUDE_HOME/settings.json"
DATA_DIR="$CLAUDE_HOME/me-agent"

PURGE=false
for arg in "$@"; do
  [[ "$arg" == "--purge" ]] && PURGE=true
done

echo "Uninstalling me-agent..."

# ---------------------------------------------------------------------------
# 1. Remove SessionEnd hook from settings.json
# ---------------------------------------------------------------------------
if [[ -f "$SETTINGS_FILE" ]] && command -v jq &>/dev/null; then
  if jq -e '.hooks.SessionEnd' "$SETTINGS_FILE" &>/dev/null; then
    tmp="$(mktemp)"
    jq '
      .hooks.SessionEnd = [
        .hooks.SessionEnd[] |
        select(.hooks | any(.command | contains("me-agent")) | not)
      ] |
      if .hooks.SessionEnd == [] then del(.hooks.SessionEnd) else . end
    ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
    echo "  Removed SessionEnd hook from settings.json"
  else
    echo "  No SessionEnd hook found in settings.json"
  fi
else
  echo "  WARNING: Could not update settings.json (jq not found or file missing)"
  echo "  Please manually remove the me-agent hook from $SETTINGS_FILE"
fi

# ---------------------------------------------------------------------------
# 2. Remove symlink
# ---------------------------------------------------------------------------
if [[ -L "$SYMLINK_TARGET" ]]; then
  rm "$SYMLINK_TARGET"
  echo "  Removed symlink: $SYMLINK_TARGET"
else
  echo "  No symlink found at $SYMLINK_TARGET"
fi

# ---------------------------------------------------------------------------
# 3. Optionally purge data directory
# ---------------------------------------------------------------------------
if [[ "$PURGE" == "true" ]]; then
  if [[ -d "$DATA_DIR" ]]; then
    rm -rf "$DATA_DIR"
    echo "  Purged data directory: $DATA_DIR"
  fi
else
  echo "  Data preserved at $DATA_DIR. Use --purge to remove."
fi

echo ""
echo "me-agent uninstalled."
