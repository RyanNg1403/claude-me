#!/bin/bash
# claude-me SessionEnd hook handler
# Must exit within 3 seconds (configured by install.sh).
# Reads session info from stdin, queues it, and spawns extraction in background.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
DATA_DIR="$CLAUDE_HOME/claude-me"
QUEUE_FILE="$DATA_DIR/.queue"
LOG_DIR="$DATA_DIR/logs"
LOG_FILE="$LOG_DIR/claude-me.log"

# Create log dir if needed
mkdir -p "$LOG_DIR"

# Read hook input from stdin (JSON)
INPUT="$(cat)"

if [ -z "$INPUT" ]; then
  exit 0
fi

# Extract cwd using jq (safe JSON parsing, no string interpolation issues)
if command -v jq &>/dev/null; then
  CWD="$(echo "$INPUT" | jq -r '.cwd // empty')"
else
  CWD="$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null)"
fi

if [ -z "$CWD" ]; then
  exit 0
fi

# Construct queue entry safely via jq (handles special chars in paths)
if command -v jq &>/dev/null; then
  QUEUE_ENTRY="$(echo "$INPUT" | jq -c '{cwd: .cwd, session_id: .session_id, transcript_path: .transcript_path, timestamp: now | strftime("%Y-%m-%dT%H:%M:%SZ")}')"
else
  # Fallback: use python for safe JSON construction
  QUEUE_ENTRY="$(echo "$INPUT" | python3 -c "
import sys,json
from datetime import datetime,timezone
d=json.load(sys.stdin)
print(json.dumps({'cwd':d.get('cwd',''),'session_id':d.get('session_id',''),'transcript_path':d.get('transcript_path',''),'timestamp':datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}))" 2>/dev/null)"
fi

echo "$QUEUE_ENTRY" >> "$QUEUE_FILE"

# Spawn extraction in background and exit immediately
nohup bash "$SCRIPT_DIR/extract.sh" --from-hook >> "$LOG_FILE" 2>&1 &

exit 0
