#!/bin/bash
# me-agent extraction pipeline
# Reads Claude Code project memory files, filters for cross-project patterns,
# and uses haiku to classify and write to the corpus.
#
# Usage:
#   extract.sh --from-hook     Process latest queue entry (single project)
#   extract.sh --all-active    Scan all active projects
#   extract.sh --project /path Extract from a specific project directory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
MODE=""
TARGET_CWD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-hook)   MODE="hook"; shift ;;
    --all-active)  MODE="all"; shift ;;
    --project)     MODE="single"; TARGET_CWD="$2"; shift 2 ;;
    *)             echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "Usage: extract.sh [--from-hook|--all-active|--project /path]" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Determine target projects
# ---------------------------------------------------------------------------
declare -a PROJECT_SLUGS=()

case "$MODE" in
  hook)
    if [[ ! -f "$QUEUE_FILE" ]]; then
      log "No queue file, nothing to process"
      exit 0
    fi
    # Read last entry from queue
    local_entry="$(tail -1 "$QUEUE_FILE")"
    if [[ -z "$local_entry" ]]; then
      exit 0
    fi
    local_cwd="$(echo "$local_entry" | jq -r '.cwd // empty' 2>/dev/null)"
    if [[ -z "$local_cwd" ]]; then
      log "Queue entry missing cwd, skipping"
      # Remove processed entry
      sed -i '' '$d' "$QUEUE_FILE" 2>/dev/null || sed -i '$d' "$QUEUE_FILE" 2>/dev/null
      exit 0
    fi
    PROJECT_SLUGS+=("$(compute_slug "$local_cwd")")
    # Remove processed entry
    sed -i '' '$d' "$QUEUE_FILE" 2>/dev/null || sed -i '$d' "$QUEUE_FILE" 2>/dev/null
    ;;
  all)
    while IFS= read -r slug; do
      [[ -n "$slug" ]] && PROJECT_SLUGS+=("$slug")
    done < <(get_active_projects)
    ;;
  single)
    PROJECT_SLUGS+=("$(compute_slug "$TARGET_CWD")")
    ;;
esac

if [[ ${#PROJECT_SLUGS[@]} -eq 0 ]]; then
  log "No active projects to process"
  exit 0
fi

log "Extracting from ${#PROJECT_SLUGS[@]} project(s)"

# ---------------------------------------------------------------------------
# Collect candidate memory entries
# ---------------------------------------------------------------------------
CANDIDATES_FILE="$(mktemp)"
PROMPT_FILE=""
RESPONSE_FILE=""
trap 'rm -f "$CANDIDATES_FILE" "$CANDIDATES_FILE.sources" "$PROMPT_FILE" "$RESPONSE_FILE"' EXIT

candidate_count=0

for slug in "${PROJECT_SLUGS[@]}"; do
  memory_dir="$(get_projects_dir)/$slug/memory"

  if [[ ! -d "$memory_dir" ]]; then
    log "No memory dir for $slug, skipping"
    continue
  fi

  for mem_file in "$memory_dir"/*.md; do
    [[ -f "$mem_file" ]] || continue

    fname="$(basename "$mem_file")"
    # Skip MEMORY.md (index file, not a memory)
    [[ "$fname" == "MEMORY.md" ]] && continue
    # Skip internal/system files (prefixed with _)
    [[ "$fname" == _* ]] && continue

    # Parse frontmatter
    mem_type="$(get_frontmatter_field "$mem_file" "type")"

    # Filter: keep user, feedback, and reference types
    case "$mem_type" in
      user|feedback|reference) ;;
      *) continue ;;
    esac

    # Source tracking: skip if we've already processed this file at this mtime
    source_key="$slug/$fname"
    file_mtime="$(get_mtime "$mem_file")"
    if is_already_processed "$source_key" "$file_mtime"; then
      continue
    fi

    # Read full content
    mem_content="$(cat "$mem_file")"

    # Track this source for marking after successful processing
    echo "$source_key $file_mtime" >> "$CANDIDATES_FILE.sources"

    # Append to candidates
    {
      echo "---SOURCE: $slug / $fname---"
      echo "$mem_content"
      echo ""
    } >> "$CANDIDATES_FILE"

    candidate_count=$((candidate_count + 1))
  done
done

if [[ $candidate_count -eq 0 ]]; then
  log "No new candidates found"
  exit 0
fi

log "Found $candidate_count new candidate(s), running extraction"

# ---------------------------------------------------------------------------
# Build prompt and call haiku
# ---------------------------------------------------------------------------
PROMPT_FILE="$(mktemp)"
RESPONSE_FILE="$(mktemp)"

extraction_model="$(get_config_value extraction_model)"
extraction_model="${extraction_model:-haiku}"

{
  cat "$ME_AGENT_DIR/prompts/extraction.md"
  echo ""
  echo "---"
  echo ""
  echo "## Memory Entries to Analyze"
  echo ""
  cat "$CANDIDATES_FILE"
} > "$PROMPT_FILE"

log "Calling claude -p --model $extraction_model"

if ! claude -p --model "$extraction_model" < "$PROMPT_FILE" > "$RESPONSE_FILE" 2>/dev/null; then
  log "ERROR: claude -p failed"
  exit 1
fi

# ---------------------------------------------------------------------------
# Parse response and write corpus files
# ---------------------------------------------------------------------------

# Extract JSON from response (handle potential markdown fences)
json_content="$(sed -n '/^\[/,/^\]/p' "$RESPONSE_FILE")"

if [[ -z "$json_content" ]]; then
  # Try extracting from code fences
  json_content="$(sed -n '/```json/,/```/p' "$RESPONSE_FILE" | sed '1d;$d')"
fi

if [[ -z "$json_content" ]] || [[ "$json_content" == "[]" ]]; then
  log "No cross-project entries identified"
  # Still mark sources as processed so we don't re-scan them
  if [[ -f "$CANDIDATES_FILE.sources" ]]; then
    while IFS=' ' read -r src_key src_mtime; do
      mark_processed "$src_key" "$src_mtime"
    done < "$CANDIDATES_FILE.sources"
  fi
  exit 0
fi

# Parse each entry and write files
entry_count="$(echo "$json_content" | jq 'length' 2>/dev/null || echo 0)"
log "Writing $entry_count corpus entries"

for i in $(seq 0 $((entry_count - 1))); do
  category="$(echo "$json_content" | jq -r ".[$i].category")"
  filename="$(echo "$json_content" | jq -r ".[$i].filename")"
  name="$(echo "$json_content" | jq -r ".[$i].frontmatter.name")"
  description="$(echo "$json_content" | jq -r ".[$i].frontmatter.description")"
  content="$(echo "$json_content" | jq -r ".[$i].content")"

  # Validate category
  case "$category" in
    interaction-style|rules|patterns|projects) ;;
    *) log "Unknown category '$category' for $filename, skipping"; continue ;;
  esac

  target_dir="$CORPUS_DIR/$category"
  target_file="$target_dir/$filename"

  # Skip if file already exists
  if [[ -f "$target_file" ]]; then
    log "File $target_file already exists, skipping"
    continue
  fi

  # Write the corpus entry
  {
    echo "---"
    echo "name: $name"
    echo "description: $description"
    echo "---"
    echo ""
    echo "$content"
  } > "$target_file"

  log "Created $category/$filename"
done

# ---------------------------------------------------------------------------
# Mark processed sources
# ---------------------------------------------------------------------------
if [[ -f "$CANDIDATES_FILE.sources" ]]; then
  while IFS=' ' read -r src_key src_mtime; do
    mark_processed "$src_key" "$src_mtime"
  done < "$CANDIDATES_FILE.sources"
fi

# ---------------------------------------------------------------------------
# Rebuild indexes
# ---------------------------------------------------------------------------
for subfolder in "$CORPUS_DIR"/*/; do
  [[ -d "$subfolder" ]] && rebuild_subfolder_index "$subfolder"
done
rebuild_top_index

log "Extraction complete"

# ---------------------------------------------------------------------------
# Check if consolidation is due
# ---------------------------------------------------------------------------
if is_consolidation_due; then
  log "Consolidation is due, triggering"
  bash "$SCRIPT_DIR/consolidate.sh" &
fi
