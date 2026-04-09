#!/bin/bash
# me-agent installer
# Creates symlink to ~/.claude/skills/, sets up data directory, registers SessionEnd hook
#
# Usage:
#   install.sh            Add CLAUDE.md hint to ~/.claude/CLAUDE.md (all projects)
#   install.sh --project  Add CLAUDE.md hint to current project (./CLAUDE.md) instead

set -euo pipefail

PROJECT=false
CALLER_CWD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)   PROJECT=true; shift ;;
    --cwd)       CALLER_CWD="$2"; shift 2 ;;
    *)           echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

ME_AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SKILLS_DIR="$CLAUDE_HOME/skills"
SYMLINK_TARGET="$SKILLS_DIR/me-agent"
SETTINGS_FILE="$CLAUDE_HOME/settings.json"
DATA_DIR="$CLAUDE_HOME/me-agent"
HOOK_COMMAND="bash $SYMLINK_TARGET/scripts/hook-handler.sh"

echo "Installing me-agent..."

# ---------------------------------------------------------------------------
# 1. Create symlink (skill code → repo)
# ---------------------------------------------------------------------------
mkdir -p "$SKILLS_DIR"

if [[ -L "$SYMLINK_TARGET" ]]; then
  existing="$(readlink "$SYMLINK_TARGET")"
  if [[ "$existing" == "$ME_AGENT_DIR" ]]; then
    echo "  Symlink already exists and points to this directory"
  else
    echo "  Updating symlink: $existing -> $ME_AGENT_DIR"
    rm "$SYMLINK_TARGET"
    ln -s "$ME_AGENT_DIR" "$SYMLINK_TARGET"
  fi
elif [[ -d "$SYMLINK_TARGET" ]]; then
  echo "  WARNING: $SYMLINK_TARGET is a real directory, not a symlink."
  echo "  Please remove it manually and re-run install.sh"
  exit 1
else
  ln -s "$ME_AGENT_DIR" "$SYMLINK_TARGET"
  echo "  Created symlink: $SYMLINK_TARGET -> $ME_AGENT_DIR"
fi

# ---------------------------------------------------------------------------
# 2. Create data directory (corpus + logs, outside repo)
# ---------------------------------------------------------------------------
mkdir -p "$DATA_DIR/corpus/"{interaction-style,projects,rules,patterns}
mkdir -p "$DATA_DIR/logs"

# Create ME.md scaffolds if they don't exist yet
for subdir in interaction-style projects rules patterns; do
  target="$DATA_DIR/corpus/$subdir/ME.md"
  if [[ ! -f "$target" ]]; then
    echo "# $subdir" > "$target"
    echo "" >> "$target"
    echo "<!-- No entries yet -->" >> "$target"
  fi
done

if [[ ! -f "$DATA_DIR/corpus/ME.md" ]]; then
  cat > "$DATA_DIR/corpus/ME.md" <<'SCAFFOLD'
# Me Agent

> Cross-project preferences, patterns, and behaviors accumulated from Claude Code usage.

SCAFFOLD
fi

echo "  Data directory: $DATA_DIR"

# ---------------------------------------------------------------------------
# 3. Make scripts executable
# ---------------------------------------------------------------------------
chmod +x "$ME_AGENT_DIR/scripts/"*.sh
echo "  Made scripts executable"

# ---------------------------------------------------------------------------
# 4. Register SessionEnd hook in settings.json
# ---------------------------------------------------------------------------
if [[ ! -f "$SETTINGS_FILE" ]]; then
  echo '{}' > "$SETTINGS_FILE"
fi

if grep -q "me-agent/scripts/hook-handler.sh" "$SETTINGS_FILE" 2>/dev/null; then
  echo "  SessionEnd hook already registered"
else
  if command -v jq &>/dev/null; then
    HOOK_JSON=$(cat <<EOF
{
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_COMMAND"
          }
        ]
      }
    ]
  }
}
EOF
)
    tmp="$(mktemp)"
    jq --argjson hook "$HOOK_JSON" '
      .hooks //= {} |
      .hooks.SessionEnd //= [] |
      .hooks.SessionEnd += $hook.hooks.SessionEnd |
      .env //= {} |
      .env.CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS //= "3000"
    ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
    echo "  Registered SessionEnd hook in settings.json"
    echo "  Set SessionEnd timeout to 3s"
  else
    echo "  WARNING: jq not found. Please manually add the SessionEnd hook to $SETTINGS_FILE:"
    echo "  {\"hooks\":{\"SessionEnd\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"$HOOK_COMMAND\"}]}]}}"
  fi
fi

# ---------------------------------------------------------------------------
# 5. Add CLAUDE.md hint
# ---------------------------------------------------------------------------
read -r -d '' CLAUDE_MD_HINT << 'HINT' || true
## User Preferences (claude-me)

Frequently look up ~/.claude/me-agent/corpus/ME.md before important decisions or implementations to align with user preferences. Run /me-agent for full context.
HINT

if [[ "$PROJECT" == "true" ]]; then
  # Use caller's cwd if provided (oclif runs scripts from scripts/ dir)
  CLAUDE_MD_FILE="${CALLER_CWD:-.}/CLAUDE.md"
else
  CLAUDE_MD_FILE="$CLAUDE_HOME/CLAUDE.md"
fi

if [[ -f "$CLAUDE_MD_FILE" ]] && grep -qF "me-agent/corpus/ME.md" "$CLAUDE_MD_FILE" 2>/dev/null; then
  echo "  CLAUDE.md hint already present in $CLAUDE_MD_FILE"
else
  # Append with a blank line separator
  if [[ -f "$CLAUDE_MD_FILE" ]] && [[ -s "$CLAUDE_MD_FILE" ]]; then
    echo "" >> "$CLAUDE_MD_FILE"
  fi
  echo "$CLAUDE_MD_HINT" >> "$CLAUDE_MD_FILE"
  echo "  Added hint to $CLAUDE_MD_FILE"
fi

# Create notes directory
mkdir -p "$DATA_DIR/notes"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "me-agent installed successfully!"
echo ""
echo "  Skill:  $SYMLINK_TARGET -> $ME_AGENT_DIR"
echo "  Data:   $DATA_DIR  (corpus, logs — your personal data)"
echo ""
echo "Usage:"
echo "  /me-agent              Load your preference corpus into context"
echo "  /me-agent sync         Extract preferences from all active projects"
echo "  /me-agent consolidate  Merge and clean up corpus entries"
echo ""
echo "The SessionEnd hook will automatically extract preferences after each session."
