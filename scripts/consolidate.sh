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
SYSTEM_PROMPT_FILE=""
cleanup() {
  local exit_code=$?
  rm -f "$SYSTEM_PROMPT_FILE"
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

# Copy corpus to staging dir (outside ~/.claude/ to avoid sandbox block).
# Haiku modifies the copy freely, then we diff and apply changes.
STAGING_DIR="$(mktemp -d)"
cp -R "$CORPUS_DIR"/* "$STAGING_DIR/"

SYSTEM_PROMPT_FILE="$(mktemp)"
{
  cat "$ME_AGENT_DIR/prompts/consolidation.md"
  cat <<SYEOF

---

Working directory: $STAGING_DIR

This is a writable copy of the corpus. Read, modify, delete, and create files here freely.

Steps:
1. Read all .md files in each subdirectory (skip ME.md files — those are indexes rebuilt automatically)
2. Analyze for duplicates, contradictions, and misplaced entries
3. Use Write to update files, Bash (rm) to delete files, Bash (mv) to move files between categories
4. Only modify files inside $STAGING_DIR.

Category subdirectories:
- $STAGING_DIR/interaction-style/
- $STAGING_DIR/rules/
- $STAGING_DIR/patterns/
- $STAGING_DIR/projects/

If no changes are needed, just say so.
SYEOF
} > "$SYSTEM_PROMPT_FILE"

log "Calling claude -p --model $consolidation_model (with tools)"

USER_MSG="Read all corpus files and consolidate now."
input_chars=$(( $(wc -c < "$SYSTEM_PROMPT_FILE") + ${#USER_MSG} ))
RESPONSE_FILE="$(mktemp)"

if ! echo "$USER_MSG" | claude -p \
  --model "$consolidation_model" \
  --tools "Read,Write,Edit,Bash,Glob" \
  --system-prompt-file "$SYSTEM_PROMPT_FILE" \
  --dangerously-skip-permissions \
  2>&1 | tee -a "$LOG_FILE" > "$RESPONSE_FILE"; then
  log "ERROR: claude -p failed"
  rm -rf "$STAGING_DIR" "$RESPONSE_FILE"
  exit 1
fi

output_chars=$(wc -c < "$RESPONSE_FILE")
record_cost "consolidation" "$consolidation_model" "$input_chars" "$output_chars"
rm -f "$RESPONSE_FILE"

# Apply changes: sync staging back to corpus
# Delete files that haiku removed
for category in interaction-style rules patterns projects; do
  corpus_cat="$CORPUS_DIR/$category"
  staging_cat="$STAGING_DIR/$category"
  [[ -d "$corpus_cat" ]] || continue

  for f in "$corpus_cat"/*.md; do
    [[ -f "$f" ]] || continue
    fname="$(basename "$f")"
    [[ "$fname" == "ME.md" ]] && continue
    if [[ ! -f "$staging_cat/$fname" ]]; then
      rm "$f"
      log "Deleted $category/$fname"
    fi
  done
done

# Copy new or updated files from staging
for category in interaction-style rules patterns projects; do
  staging_cat="$STAGING_DIR/$category"
  corpus_cat="$CORPUS_DIR/$category"
  [[ -d "$staging_cat" ]] || continue
  mkdir -p "$corpus_cat"

  for f in "$staging_cat"/*.md; do
    [[ -f "$f" ]] || continue
    fname="$(basename "$f")"
    [[ "$fname" == "ME.md" ]] && continue
    if [[ ! -f "$corpus_cat/$fname" ]] || ! diff -q "$f" "$corpus_cat/$fname" &>/dev/null; then
      cp "$f" "$corpus_cat/$fname"
      log "Updated $category/$fname"
    fi
  done
done

# Move pending interview questions if haiku generated them
QUESTIONS_FILE="$DATA_DIR/pending-questions.json"
if [[ -f "$STAGING_DIR/pending-questions.json" ]]; then
  mv "$STAGING_DIR/pending-questions.json" "$QUESTIONS_FILE"
  question_count="$(jq 'length' "$QUESTIONS_FILE" 2>/dev/null || echo 0)"
  log "Generated $question_count interview question(s)"
fi

rm -rf "$STAGING_DIR"

# ---------------------------------------------------------------------------
# Rebuild all indexes (haiku modified files, we rebuild the ME.md indexes)
# ---------------------------------------------------------------------------
for subfolder in "$CORPUS_DIR"/*/; do
  [[ -d "$subfolder" ]] && rebuild_subfolder_index "$subfolder"
done
rebuild_top_index

log "Consolidation applied changes to $file_count file corpus"
notify_pending_questions
