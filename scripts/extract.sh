#!/bin/bash
# me-agent extraction pipeline
# Reads Claude Code project memory files, filters for cross-project patterns,
# and uses haiku (with tool access) to classify and write to the corpus.
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

    # Atomic claim: move queue to a temp file, process from there
    CLAIMED_QUEUE="$(mktemp)"
    mv "$QUEUE_FILE" "$CLAIMED_QUEUE" 2>/dev/null || { log "No queue to claim"; exit 0; }

    # Read all entries from claimed queue
    while IFS= read -r entry; do
      [[ -z "$entry" ]] && continue
      local_cwd="$(echo "$entry" | jq -r '.cwd // empty' 2>/dev/null)"
      if [[ -n "$local_cwd" ]]; then
        local resolved
        resolved="$(find_project_dir "$local_cwd")"
        [[ -n "$resolved" ]] && PROJECT_SLUGS+=("$resolved")
      fi
    done < "$CLAIMED_QUEUE"
    rm -f "$CLAIMED_QUEUE"
    ;;
  all)
    while IFS= read -r slug; do
      [[ -n "$slug" ]] && PROJECT_SLUGS+=("$slug")
    done < <(get_active_projects)
    ;;
  single)
    local resolved
    resolved="$(find_project_dir "$TARGET_CWD")"
    if [[ -n "$resolved" ]]; then
      PROJECT_SLUGS+=("$resolved")
    else
      PROJECT_SLUGS+=("$(compute_slug "$TARGET_CWD")")
    fi
    ;;
esac

if [[ ${#PROJECT_SLUGS[@]} -eq 0 ]]; then
  log "No active projects to process"
  exit 0
fi

# Deduplicate slugs (multiple sessions in same project)
PROJECT_SLUGS=($(printf '%s\n' "${PROJECT_SLUGS[@]}" | sort -u))

log "Extracting from ${#PROJECT_SLUGS[@]} project(s)"

# ---------------------------------------------------------------------------
# Collect candidate memory entries
# ---------------------------------------------------------------------------
CANDIDATES_FILE="$(mktemp)"
SOURCES_FILE="$(mktemp)"
trap 'rm -f "$CANDIDATES_FILE" "$SOURCES_FILE"' EXIT

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

    # Track this source for marking after processing
    echo "$source_key $file_mtime" >> "$SOURCES_FILE"

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
# Build prompt and call haiku with tool access
# ---------------------------------------------------------------------------
extraction_model="$(get_config_value extraction_model)"
extraction_model="${extraction_model:-haiku}"

PROMPT="$(cat "$ME_AGENT_DIR/prompts/extraction.md")

---

Corpus directory: $CORPUS_DIR

Write new corpus entries directly using the Write tool. Each file goes in the appropriate category subdirectory:
- $CORPUS_DIR/interaction-style/  (how the user communicates with Claude Code)
- $CORPUS_DIR/rules/              (explicit rules and constraints)
- $CORPUS_DIR/patterns/           (workflow habits, tool preferences)
- $CORPUS_DIR/projects/           (high-level project overviews)

Use kebab-case filenames (e.g., never-commit-untested.md).
Each file must have YAML frontmatter with name and description fields.
Only write files inside $CORPUS_DIR. Do not modify any other files.

If no entries qualify as cross-project, just say so — don't create any files.

---

## Memory Entries to Analyze

$(cat "$CANDIDATES_FILE")"

log "Calling claude -p --model $extraction_model (with tools)"

if ! echo "$PROMPT" | claude -p \
  --model "$extraction_model" \
  --tools "Read,Write,Bash" \
  --dangerously-skip-permissions \
  >> "$LOG_FILE" 2>&1; then
  log "ERROR: claude -p failed"
  exit 1
fi

# ---------------------------------------------------------------------------
# Mark processed sources (regardless of whether haiku created files)
# ---------------------------------------------------------------------------
if [[ -f "$SOURCES_FILE" ]]; then
  while IFS=' ' read -r src_key src_mtime; do
    mark_processed "$src_key" "$src_mtime"
  done < "$SOURCES_FILE"
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
