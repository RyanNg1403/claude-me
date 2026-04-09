#!/bin/bash
# claude-me uninstaller
# Removes hook, symlink, CLAUDE.md hint, and data directory.
# Confirmation is handled by the oclif command before calling this script.
#
# Usage:
#   uninstall.sh --yes    Run full uninstall (called by clm uninstall after confirmation)

set -euo pipefail

CONFIRMED=false
for arg in "$@"; do
  [[ "$arg" == "--yes" ]] && CONFIRMED=true
done

if [[ "$CONFIRMED" != "true" ]]; then
  echo "This script should be called via 'clm uninstall'. Run that instead."
  exit 1
fi

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SKILLS_DIR="$CLAUDE_HOME/skills"
SYMLINK_TARGET="$SKILLS_DIR/claude-me"
SETTINGS_FILE="$CLAUDE_HOME/settings.json"
DATA_DIR="$CLAUDE_HOME/claude-me"
GLOBAL_CLAUDE_MD="$CLAUDE_HOME/CLAUDE.md"

echo "Uninstalling claude-me..."

# ---------------------------------------------------------------------------
# 1. Remove SessionEnd hook from settings.json
# ---------------------------------------------------------------------------
if [[ -f "$SETTINGS_FILE" ]] && command -v jq &>/dev/null; then
  if jq -e '.hooks.SessionEnd' "$SETTINGS_FILE" &>/dev/null; then
    tmp="$(mktemp)"
    jq '
      .hooks.SessionEnd = [
        .hooks.SessionEnd[] |
        select(.hooks | any(.command | contains("claude-me")) | not)
      ] |
      if .hooks.SessionEnd == [] then del(.hooks.SessionEnd) else . end
    ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
    echo "  Removed SessionEnd hook from settings.json"
  else
    echo "  No SessionEnd hook found"
  fi
else
  echo "  WARNING: Could not update settings.json (jq not found or file missing)"
fi

# ---------------------------------------------------------------------------
# 2. Remove symlink
# ---------------------------------------------------------------------------
if [[ -L "$SYMLINK_TARGET" ]]; then
  rm "$SYMLINK_TARGET"
  echo "  Removed symlink: $SYMLINK_TARGET"
else
  echo "  No symlink found"
fi

# ---------------------------------------------------------------------------
# 3. Remove CLAUDE.md hint (global)
# ---------------------------------------------------------------------------
if [[ -f "$GLOBAL_CLAUDE_MD" ]] && grep -qF "claude-me" "$GLOBAL_CLAUDE_MD" 2>/dev/null; then
  tmp="$(mktemp)"
  # Remove the claude-me section (from ## User Preferences to next ## or EOF)
  awk '
    /^## User Preferences \(claude-me\)/ { skip=1; next }
    /^## / && skip { skip=0 }
    skip { next }
    { print }
  ' "$GLOBAL_CLAUDE_MD" > "$tmp"
  # If file is now empty (only whitespace), delete it
  if [[ ! -s "$tmp" ]] || [[ -z "$(tr -d '[:space:]' < "$tmp")" ]]; then
    rm "$GLOBAL_CLAUDE_MD"
    echo "  Removed $GLOBAL_CLAUDE_MD"
  else
    mv "$tmp" "$GLOBAL_CLAUDE_MD"
    echo "  Removed hint from $GLOBAL_CLAUDE_MD"
  fi
  rm -f "$tmp"
else
  echo "  No CLAUDE.md hint found"
fi

# ---------------------------------------------------------------------------
# 4. Remove data directory
# ---------------------------------------------------------------------------
if [[ -d "$DATA_DIR" ]]; then
  rm -rf "$DATA_DIR"
  echo "  Removed data: $DATA_DIR"
else
  echo "  No data directory found"
fi

echo ""
echo "claude-me fully uninstalled."
