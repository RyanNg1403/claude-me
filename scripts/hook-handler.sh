#!/bin/bash
# me-agent SessionEnd hook handler
# Must exit within 1.5 seconds (Claude Code's SessionEnd timeout).
# Reads session info from stdin, queues it, and spawns extraction in background.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
DATA_DIR="$CLAUDE_HOME/me-agent"
QUEUE_FILE="$DATA_DIR/.queue"
LOG_DIR="$DATA_DIR/logs"
LOG_FILE="$LOG_DIR/me-agent.log"

# Create log dir if needed
mkdir -p "$LOG_DIR"

# Read hook input from stdin (JSON)
INPUT="$(cat)"

if [ -z "$INPUT" ]; then
  exit 0
fi

# Extract fields
CWD="$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null)"
SESSION_ID="$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null)"
TRANSCRIPT="$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('transcript_path',''))" 2>/dev/null)"

if [ -z "$CWD" ]; then
  exit 0
fi

# Append to queue (one JSON object per line)
echo "{\"cwd\":\"$CWD\",\"session_id\":\"$SESSION_ID\",\"transcript_path\":\"$TRANSCRIPT\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> "$QUEUE_FILE"

# Spawn extraction in background and exit immediately
nohup bash "$SCRIPT_DIR/extract.sh" --from-hook >> "$LOG_FILE" 2>&1 &

exit 0
