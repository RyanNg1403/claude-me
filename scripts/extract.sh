#!/bin/bash
# me-agent extraction pipeline
# Reads Claude Code project memory files, filters for cross-project patterns,
# and uses haiku (with tool access) to classify and write to the corpus.
#
# Usage:
#   extract.sh --from-hook     Process latest queue entry (single project)
#   extract.sh --all-active    Scan all active projects
#   extract.sh --project /path Extract from a specific project directory
#   extract.sh --notes-only    Process only pending user notes (no CC memory scan)

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
    --from-hook)    MODE="hook"; shift ;;
    --all-active)   MODE="all"; shift ;;
    --project)      MODE="single"; TARGET_CWD="$2"; shift 2 ;;
    --notes-only)   MODE="notes"; shift ;;
    *)              echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "Usage: extract.sh [--from-hook|--all-active|--project /path|--notes-only]" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Collect candidates
# ---------------------------------------------------------------------------
CANDIDATES_FILE="$(mktemp)"
SOURCES_FILE="$(mktemp)"
SYSTEM_PROMPT_FILE=""
trap 'rm -f "$CANDIDATES_FILE" "$SOURCES_FILE" "$SYSTEM_PROMPT_FILE"' EXIT

candidate_count=0
note_count=0

# --- CC memory candidates (skip for notes-only mode) ---
if [[ "$MODE" != "notes" ]]; then
  declare -a PROJECT_SLUGS=()

  case "$MODE" in
    hook)
      if [[ ! -f "$QUEUE_FILE" ]]; then
        log "No queue file, nothing to process"
        # Fall through to note collection below
      else
        CLAIMED_QUEUE="$(mktemp)"
        mv "$QUEUE_FILE" "$CLAIMED_QUEUE" 2>/dev/null || true

        if [[ -f "$CLAIMED_QUEUE" ]]; then
          while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            local_cwd="$(echo "$entry" | jq -r '.cwd // empty' 2>/dev/null)"
            if [[ -n "$local_cwd" ]]; then
              resolved="$(find_project_dir "$local_cwd")"
              [[ -n "$resolved" ]] && PROJECT_SLUGS+=("$resolved")
            fi
          done < "$CLAIMED_QUEUE"
          rm -f "$CLAIMED_QUEUE"
        fi
      fi
      ;;
    all)
      while IFS= read -r slug; do
        [[ -n "$slug" ]] && PROJECT_SLUGS+=("$slug")
      done < <(get_active_projects)
      ;;
    single)
      resolved="$(find_project_dir "$TARGET_CWD")"
      if [[ -n "$resolved" ]]; then
        PROJECT_SLUGS+=("$resolved")
      else
        PROJECT_SLUGS+=("$(compute_slug "$TARGET_CWD")")
      fi
      ;;
  esac

  if [[ ${#PROJECT_SLUGS[@]} -gt 0 ]]; then
    PROJECT_SLUGS=($(printf '%s\n' "${PROJECT_SLUGS[@]}" | sort -u))
    log "Scanning ${#PROJECT_SLUGS[@]} project(s) for CC memories"

    for slug in "${PROJECT_SLUGS[@]}"; do
      memory_dir="$(get_projects_dir)/$slug/memory"

      if [[ ! -d "$memory_dir" ]]; then
        log "No memory dir for $slug, skipping"
        continue
      fi

      for mem_file in "$memory_dir"/*.md; do
        [[ -f "$mem_file" ]] || continue

        fname="$(basename "$mem_file")"
        [[ "$fname" == "MEMORY.md" ]] && continue
        [[ "$fname" == _* ]] && continue

        mem_type="$(get_frontmatter_field "$mem_file" "type")"
        case "$mem_type" in
          user|feedback|reference) ;;
          *) continue ;;
        esac

        source_key="$slug/$fname"
        file_mtime="$(get_mtime "$mem_file")"
        if is_already_processed "$source_key" "$file_mtime"; then
          continue
        fi

        mem_content="$(cat "$mem_file")"
        echo "$source_key $file_mtime" >> "$SOURCES_FILE"

        {
          echo "---SOURCE: $slug / $fname---"
          echo "$mem_content"
          echo ""
        } >> "$CANDIDATES_FILE"

        candidate_count=$((candidate_count + 1))
      done
    done
  fi
fi

# --- Pending notes (all modes) ---
collect_notes "$CANDIDATES_FILE" "$SOURCES_FILE"
note_count=$NOTE_COUNT
candidate_count=$((candidate_count + note_count))

if [[ $candidate_count -eq 0 ]]; then
  log "No new candidates or notes found"
  exit 0
fi

log "Found $candidate_count candidate(s) ($note_count note(s)), running extraction"

# ---------------------------------------------------------------------------
# Determine extraction strategy
# ---------------------------------------------------------------------------
# When notes are present, Haiku needs access to existing corpus to check for
# conflicts and override/delete existing entries. Use consolidation-style
# staging (copy corpus). Otherwise, use simple write-only staging.
HAS_NOTES=false
if [[ $note_count -gt 0 ]]; then
  HAS_NOTES=true
fi

extraction_model="$(get_config_value extraction_model)"
extraction_model="${extraction_model:-haiku}"

STAGING_DIR="$(mktemp -d)"

if [[ "$HAS_NOTES" == "true" ]]; then
  # Copy existing corpus so Haiku can read, modify, and delete entries
  for category in interaction-style rules patterns projects; do
    if [[ -d "$CORPUS_DIR/$category" ]]; then
      mkdir -p "$STAGING_DIR/$category"
      cp "$CORPUS_DIR/$category"/*.md "$STAGING_DIR/$category/" 2>/dev/null || true
    fi
  done
fi

# ---------------------------------------------------------------------------
# Build system prompt
# ---------------------------------------------------------------------------
SYSTEM_PROMPT_FILE="$(mktemp)"

if [[ "$HAS_NOTES" == "true" ]]; then
  {
    cat "$ME_AGENT_DIR/prompts/extraction.md"
    cat <<SYEOF

---

## Note Processing (additional instructions)

Some entries below are marked \`user-note\`. These are preferences the user explicitly wrote down via \`clm note\`. Treat them with the same critical eye as CC memory entries:

- **Do NOT blindly add them.** Evaluate whether each note is a genuine cross-project preference. Discard vague or meaningless notes.
- **Check for conflicts.** Read existing corpus files in the working directory. If a note contradicts an existing entry, update or delete the old entry and write the note as its replacement (or merge them if appropriate).
- **Check for duplicates.** If a note says the same thing as an existing entry, skip it.
- A note like "I don't care about X anymore" means delete the existing entry about X.
- A note like "actually, prefer Y over Z" means update the existing Z entry or replace it.

CC memory entries (marked with a project slug source) follow the standard extraction rules — classify and write only cross-project preferences.

---

Working directory: $STAGING_DIR

This directory contains the existing corpus. You may:
- **Read** existing files to check for conflicts and duplicates
- **Write** new files for qualifying entries
- **Edit** existing files to update them
- **Delete** files via Bash (rm) when a note overrides an old preference

Category subdirectories:
- $STAGING_DIR/interaction-style/  (how the user communicates with Claude Code)
- $STAGING_DIR/rules/              (explicit rules and constraints)
- $STAGING_DIR/patterns/           (workflow habits, tool preferences)
- $STAGING_DIR/projects/           (high-level project overviews)

Create subdirectories if needed (use Bash: mkdir -p).
Use kebab-case filenames (e.g., never-commit-untested.md).
Each file must have YAML frontmatter with name and description fields.

If no entries qualify and no changes are needed, just say so.
SYEOF
  } > "$SYSTEM_PROMPT_FILE"
  HAIKU_TOOLS="Read,Write,Edit,Bash,Glob"
else
  {
    cat "$ME_AGENT_DIR/prompts/extraction.md"
    cat <<SYEOF

---

Output directory: $STAGING_DIR

Write new corpus entries using the Write tool. Each file goes in a category subdirectory:
- $STAGING_DIR/interaction-style/  (how the user communicates with Claude Code)
- $STAGING_DIR/rules/              (explicit rules and constraints)
- $STAGING_DIR/patterns/           (workflow habits, tool preferences)
- $STAGING_DIR/projects/           (high-level project overviews)

Create the subdirectory if it doesn't exist (use Bash: mkdir -p).
Use kebab-case filenames (e.g., never-commit-untested.md).
Each file must have YAML frontmatter with name and description fields.

If no entries qualify as cross-project, just say so — don't create any files.
SYEOF
  } > "$SYSTEM_PROMPT_FILE"
  HAIKU_TOOLS="Read,Write,Bash"
fi

# ---------------------------------------------------------------------------
# Call haiku
# ---------------------------------------------------------------------------
USER_PROMPT="Analyze and process these entries now. Act immediately — do not ask for confirmation:

$(cat "$CANDIDATES_FILE")"

log "Calling claude -p --model $extraction_model (with tools: $HAIKU_TOOLS)"

RESPONSE_FILE="$(mktemp)"
input_chars=$(( $(wc -c < "$SYSTEM_PROMPT_FILE") + ${#USER_PROMPT} ))

if ! echo "$USER_PROMPT" | claude -p \
  --model "$extraction_model" \
  --tools "$HAIKU_TOOLS" \
  --system-prompt-file "$SYSTEM_PROMPT_FILE" \
  --dangerously-skip-permissions \
  2>&1 | tee -a "$LOG_FILE" > "$RESPONSE_FILE"; then
  log "ERROR: claude -p failed"
  exit 1
fi

output_chars=$(wc -c < "$RESPONSE_FILE")
record_cost "extraction" "$extraction_model" "$input_chars" "$output_chars"
rm -f "$RESPONSE_FILE"

# ---------------------------------------------------------------------------
# Apply staged changes to corpus
# ---------------------------------------------------------------------------
if [[ "$HAS_NOTES" == "true" ]]; then
  # Diff-and-apply (like consolidation): Haiku may have modified or deleted files
  for category in interaction-style rules patterns projects; do
    corpus_cat="$CORPUS_DIR/$category"
    staging_cat="$STAGING_DIR/$category"

    # Delete files that Haiku removed
    if [[ -d "$corpus_cat" ]]; then
      for f in "$corpus_cat"/*.md; do
        [[ -f "$f" ]] || continue
        fname="$(basename "$f")"
        [[ "$fname" == "ME.md" ]] && continue
        if [[ ! -f "$staging_cat/$fname" ]]; then
          rm "$f"
          log "Deleted $category/$fname (note override)"
        fi
      done
    fi

    # Copy new or updated files from staging
    if [[ -d "$staging_cat" ]]; then
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
    fi
  done
else
  # Simple move: Haiku only wrote new files to empty staging dir
  for category_dir in "$STAGING_DIR"/*/; do
    [[ -d "$category_dir" ]] || continue
    category="$(basename "$category_dir")"
    case "$category" in
      interaction-style|rules|patterns|projects) ;;
      *) log "Unknown category '$category' in staging, skipping"; continue ;;
    esac
    mkdir -p "$CORPUS_DIR/$category"
    for staged_file in "$category_dir"/*.md; do
      [[ -f "$staged_file" ]] || continue
      fname="$(basename "$staged_file")"
      if [[ -f "$CORPUS_DIR/$category/$fname" ]]; then
        log "File $category/$fname already exists, skipping"
      else
        mv "$staged_file" "$CORPUS_DIR/$category/$fname"
        log "Created $category/$fname"
      fi
    done
  done
fi
rm -rf "$STAGING_DIR"

# ---------------------------------------------------------------------------
# Mark processed sources (regardless of whether haiku created files)
# ---------------------------------------------------------------------------
if [[ -f "$SOURCES_FILE" ]]; then
  while IFS=' ' read -r src_key src_mtime; do
    mark_processed "$src_key" "$src_mtime"
    # Delete processed note files (corpus is the durable output)
    if [[ "$src_key" == notes/* ]]; then
      rm -f "$NOTES_DIR/${src_key#notes/}"
    fi
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
notify_pending_questions

# ---------------------------------------------------------------------------
# Check if consolidation is due
# ---------------------------------------------------------------------------
if is_consolidation_due; then
  log "Consolidation is due, triggering"
  bash "$SCRIPT_DIR/consolidate.sh" &
fi
