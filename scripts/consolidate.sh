#!/bin/bash
# me-agent consolidation pipeline
# Gives haiku direct tool access to read, merge, and clean up corpus files.
#
# Usage:
#   consolidate.sh            Check interval, run if due
#   consolidate.sh --force    Skip interval check, run now

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
FORCE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=true; shift ;;
    *)       echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Gate checks
# ---------------------------------------------------------------------------
if [[ "$FORCE" != "true" ]]; then
  if ! is_consolidation_due; then
    log "Consolidation not due yet, skipping"
    exit 0
  fi
fi

if ! acquire_lock; then
  log "Could not acquire lock, skipping"
  exit 0
fi

log "Starting consolidation"

# Ensure lock is released on exit
cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "Consolidation failed (exit $exit_code), rolling back lock"
    rollback_lock
  else
    release_lock
    log "Consolidation complete, lock released"
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Count corpus files (skip if empty)
# ---------------------------------------------------------------------------
file_count=0
for subfolder in "$CORPUS_DIR"/*/; do
  [[ -d "$subfolder" ]] || continue
  for topic_file in "$subfolder"/*.md; do
    [[ -f "$topic_file" ]] || continue
    [[ "$(basename "$topic_file")" == "ME.md" ]] && continue
    file_count=$((file_count + 1))
  done
done

if [[ $file_count -eq 0 ]]; then
  log "No corpus files to consolidate"
  exit 0
fi

log "Consolidating $file_count corpus file(s)"

# ---------------------------------------------------------------------------
# Build prompt and call haiku with tool access
# ---------------------------------------------------------------------------
consolidation_model="$(get_config_value consolidation_model)"
consolidation_model="${consolidation_model:-haiku}"

PROMPT="$(cat "$ME_AGENT_DIR/prompts/consolidation.md")

---

Corpus directory: $CORPUS_DIR

You have direct tool access. Use Read to examine corpus files, Write to update them, and Bash to delete or move files.

Steps:
1. Read all .md files in each subdirectory of $CORPUS_DIR (skip ME.md files — those are indexes, not entries)
2. Analyze for duplicates, contradictions, and misplaced entries
3. Use Write to update files, Bash (rm) to delete files, Bash (mv) to move files between categories
4. Only modify files inside $CORPUS_DIR. Do not touch any other files.

Category subdirectories:
- $CORPUS_DIR/interaction-style/
- $CORPUS_DIR/rules/
- $CORPUS_DIR/patterns/
- $CORPUS_DIR/projects/

If no changes are needed, just say so."

log "Calling claude -p --model $consolidation_model (with tools)"

if ! echo "$PROMPT" | claude -p \
  --model "$consolidation_model" \
  --tools "Read,Write,Edit,Bash,Glob" \
  --dangerously-skip-permissions \
  >> "$LOG_FILE" 2>&1; then
  log "ERROR: claude -p failed"
  exit 1
fi

# ---------------------------------------------------------------------------
# Rebuild all indexes (haiku modified files, we rebuild the ME.md indexes)
# ---------------------------------------------------------------------------
for subfolder in "$CORPUS_DIR"/*/; do
  [[ -d "$subfolder" ]] && rebuild_subfolder_index "$subfolder"
done
rebuild_top_index

log "Consolidation applied changes to $file_count file corpus"
