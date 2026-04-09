#!/bin/bash
# me-agent consolidation pipeline
# Reads all corpus files, uses haiku to merge/dedup/prune, then applies changes.
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
  rm -f "$MANIFEST_FILE" "$PROMPT_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Build manifest of all corpus files
# ---------------------------------------------------------------------------
MANIFEST_FILE="$(mktemp)"
PROMPT_FILE="$(mktemp)"
RESPONSE_FILE="$(mktemp)"

file_count=0

for subfolder in "$CORPUS_DIR"/*/; do
  [[ -d "$subfolder" ]] || continue
  category="$(basename "$subfolder")"

  for topic_file in "$subfolder"/*.md; do
    [[ -f "$topic_file" ]] || continue
    [[ "$(basename "$topic_file")" == "ME.md" ]] && continue

    fname="$(basename "$topic_file")"
    content="$(cat "$topic_file")"

    {
      echo "---FILE: $category/$fname---"
      echo "$content"
      echo ""
    } >> "$MANIFEST_FILE"

    file_count=$((file_count + 1))
  done
done

if [[ $file_count -eq 0 ]]; then
  log "No corpus files to consolidate"
  exit 0
fi

log "Consolidating $file_count corpus file(s)"

# ---------------------------------------------------------------------------
# Build prompt and call model
# ---------------------------------------------------------------------------
consolidation_model="$(get_config_value consolidation_model)"
consolidation_model="${consolidation_model:-haiku}"

{
  cat "$ME_AGENT_DIR/prompts/consolidation.md"
  echo ""
  echo "---"
  echo ""
  echo "## Current Corpus Contents"
  echo ""
  cat "$MANIFEST_FILE"
} > "$PROMPT_FILE"

log "Calling claude -p --model $consolidation_model"

if ! claude -p --model "$consolidation_model" < "$PROMPT_FILE" > "$RESPONSE_FILE" 2>/dev/null; then
  log "ERROR: claude -p failed"
  exit 1
fi

# ---------------------------------------------------------------------------
# Parse response and apply actions
# ---------------------------------------------------------------------------

# Extract JSON from response
json_content="$(cat "$RESPONSE_FILE")"

# Strip markdown fences if present
json_content="$(echo "$json_content" | sed -n '/^{/,/^}/p')"
if [[ -z "$json_content" ]]; then
  json_content="$(sed -n '/```json/,/```/p' "$RESPONSE_FILE" | sed '1d;$d')"
fi

if [[ -z "$json_content" ]]; then
  log "Could not parse consolidation response"
  exit 1
fi

action_count="$(echo "$json_content" | jq '.actions | length' 2>/dev/null || echo 0)"

if [[ "$action_count" -eq 0 ]]; then
  log "No consolidation changes needed"
  exit 0
fi

log "Applying $action_count consolidation action(s)"

for i in $(seq 0 $((action_count - 1))); do
  action="$(echo "$json_content" | jq -r ".actions[$i].action")"

  case "$action" in
    delete)
      path="$(echo "$json_content" | jq -r ".actions[$i].path")"
      reason="$(echo "$json_content" | jq -r ".actions[$i].reason")"
      target="$CORPUS_DIR/$path"
      if [[ -f "$target" ]]; then
        rm "$target"
        log "Deleted $path: $reason"
      fi
      ;;

    update)
      path="$(echo "$json_content" | jq -r ".actions[$i].path")"
      name="$(echo "$json_content" | jq -r ".actions[$i].frontmatter.name")"
      description="$(echo "$json_content" | jq -r ".actions[$i].frontmatter.description")"
      content="$(echo "$json_content" | jq -r ".actions[$i].content")"
      target="$CORPUS_DIR/$path"
      {
        echo "---"
        echo "name: $name"
        echo "description: $description"
        echo "---"
        echo ""
        echo "$content"
      } > "$target"
      log "Updated $path"
      ;;

    create)
      path="$(echo "$json_content" | jq -r ".actions[$i].path")"
      name="$(echo "$json_content" | jq -r ".actions[$i].frontmatter.name")"
      description="$(echo "$json_content" | jq -r ".actions[$i].frontmatter.description")"
      content="$(echo "$json_content" | jq -r ".actions[$i].content")"
      target="$CORPUS_DIR/$path"
      target_dir="$(dirname "$target")"
      mkdir -p "$target_dir"
      {
        echo "---"
        echo "name: $name"
        echo "description: $description"
        echo "---"
        echo ""
        echo "$content"
      } > "$target"
      log "Created $path"
      ;;

    move)
      from="$(echo "$json_content" | jq -r ".actions[$i].from")"
      to="$(echo "$json_content" | jq -r ".actions[$i].to")"
      src="$CORPUS_DIR/$from"
      dst="$CORPUS_DIR/$to"
      if [[ -f "$src" ]]; then
        mkdir -p "$(dirname "$dst")"
        mv "$src" "$dst"
        log "Moved $from → $to"
      fi
      ;;

    *)
      log "Unknown action: $action"
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Rebuild all indexes
# ---------------------------------------------------------------------------
for subfolder in "$CORPUS_DIR"/*/; do
  [[ -d "$subfolder" ]] && rebuild_subfolder_index "$subfolder"
done
rebuild_top_index

log "Consolidation applied $action_count action(s)"
