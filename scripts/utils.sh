#!/bin/bash
# claude-me shared utilities
# Sourced by extract.sh, consolidate.sh, and hook-handler.sh

set -euo pipefail

# Resolve the claude-me root directory (parent of scripts/)
ME_AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$ME_AGENT_DIR/config.json"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"

# User data lives outside the repo, in a stable location
DATA_DIR="$CLAUDE_HOME/claude-me"
CORPUS_DIR="$DATA_DIR/corpus"
LOG_DIR="$DATA_DIR/logs"
LOG_FILE="$LOG_DIR/claude-me.log"
# shellcheck disable=SC2034 # used by extract.sh which sources this file
QUEUE_FILE="$DATA_DIR/.queue"
LOCK_FILE="$CORPUS_DIR/.consolidate-lock"
PROCESSED_FILE="$DATA_DIR/.processed"
NOTES_DIR="$DATA_DIR/notes"
QUESTIONS_FILE="$DATA_DIR/pending-questions.json"
COSTS_FILE="$DATA_DIR/costs.csv"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log() {
  mkdir -p "$LOG_DIR"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
  if [[ "$(get_config_value debug)" == "true" ]]; then
    echo "[claude-me] $*" >&2
  fi
}

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
get_config_value() {
  local key="$1"
  if command -v jq &>/dev/null; then
    jq -r ".$key // empty" "$CONFIG_FILE" 2>/dev/null
  else
    # Fallback: python json parser
    python3 -c "import json,sys; d=json.load(open('$CONFIG_FILE')); print(d.get('$key',''))" 2>/dev/null
  fi
}

# ---------------------------------------------------------------------------
# Path utilities
# ---------------------------------------------------------------------------

# Replicate Claude Code's sanitizePath: replace all non-alphanumeric chars with '-'
compute_slug() {
  local path="$1"
  echo "${path//[^a-zA-Z0-9]/-}"
}

# Find the actual project directory for a given cwd.
# Computes the slug and checks if it exists. If not (e.g., slug was truncated
# by CC for long paths), falls back to scanning directory names for a prefix match.
find_project_dir() {
  local cwd="$1"
  local projects_dir
  projects_dir="$(get_projects_dir)"
  local slug
  slug="$(compute_slug "$cwd")"

  # Exact match first
  if [[ -d "$projects_dir/$slug" ]]; then
    echo "$slug"
    return
  fi

  # Prefix match fallback (handles CC's truncation + hash for long paths)
  for d in "$projects_dir"/*/; do
    [[ -d "$d" ]] || continue
    local dname
    dname="$(basename "$d")"
    if [[ "$dname" == "$slug"* ]]; then
      echo "$dname"
      return
    fi
  done
}

# Get the memory directory for a given project working directory
get_memory_dir() {
  local cwd="$1"
  local slug
  slug="$(find_project_dir "$cwd")"
  if [[ -z "$slug" ]]; then
    return
  fi
  echo "$CLAUDE_HOME/projects/$slug/memory"
}

# Get the projects base directory
get_projects_dir() {
  echo "$CLAUDE_HOME/projects"
}

# ---------------------------------------------------------------------------
# Project discovery
# ---------------------------------------------------------------------------

# List active project directories (those with recent sessions)
# Returns project slugs (directory names under ~/.claude/projects/)
get_active_projects() {
  local freshness_days
  freshness_days="$(get_config_value project_freshness_days)"
  freshness_days="${freshness_days:-14}"

  local projects_dir
  projects_dir="$(get_projects_dir)"

  if [[ ! -d "$projects_dir" ]]; then
    return
  fi

  local excluded
  excluded="$(get_config_value excluded_projects)"

  for project_dir in "$projects_dir"/*/; do
    [[ -d "$project_dir" ]] || continue
    local slug
    slug="$(basename "$project_dir")"

    # Skip excluded projects (exact match, not substring)
    if [[ -n "$excluded" ]] && echo "$excluded" | grep -qw "$slug"; then
      continue
    fi

    # Check freshness: any file modified within freshness_days
    local memory_dir="$project_dir/memory"
    if [[ ! -d "$memory_dir" ]]; then
      continue
    fi

    # Check if any session file (*.jsonl) or memory file was modified recently
    local recent_file
    recent_file="$(find "$project_dir" -maxdepth 1 -name '*.jsonl' -mtime -"$freshness_days" -print -quit 2>/dev/null)"
    if [[ -z "$recent_file" ]]; then
      recent_file="$(find "$memory_dir" -name '*.md' -mtime -"$freshness_days" -print -quit 2>/dev/null)"
    fi

    if [[ -n "$recent_file" ]]; then
      echo "$slug"
    fi
  done
}

# ---------------------------------------------------------------------------
# Lock file helpers (mtime-based timer + PID mutex, like CC's dreaming)
# ---------------------------------------------------------------------------

# Check if consolidation interval has passed
is_consolidation_due() {
  local interval_hours
  interval_hours="$(get_config_value consolidation_interval_hours)"
  interval_hours="${interval_hours:-24}"

  if [[ ! -f "$LOCK_FILE" ]]; then
    return 0  # No lock file = never consolidated = due
  fi

  local lock_mtime now interval_seconds elapsed
  lock_mtime="$(stat -f '%m' "$LOCK_FILE" 2>/dev/null || stat -c '%Y' "$LOCK_FILE" 2>/dev/null)"
  now="$(date +%s)"
  interval_seconds=$((interval_hours * 3600))
  elapsed=$((now - lock_mtime))

  if [[ $elapsed -ge $interval_seconds ]]; then
    return 0  # Due
  else
    return 1  # Not due
  fi
}

# Try to acquire the consolidation lock. Returns 0 on success, 1 if held.
acquire_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    local holder_pid
    holder_pid="$(cat "$LOCK_FILE" 2>/dev/null)"
    if [[ -n "$holder_pid" ]] && kill -0 "$holder_pid" 2>/dev/null; then
      log "Lock held by PID $holder_pid, skipping"
      return 1  # Lock held by running process
    fi
    # Stale lock (process gone), take over
    log "Removing stale lock from PID $holder_pid"
  fi

  # Write our PID
  echo $$ > "$LOCK_FILE"

  # Verify we got it (write-then-verify for race conditions)
  local written_pid
  written_pid="$(cat "$LOCK_FILE" 2>/dev/null)"
  if [[ "$written_pid" != "$$" ]]; then
    log "Lost lock race, skipping"
    return 1
  fi

  return 0
}

# Release the lock and update mtime to record consolidation time
release_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    local holder_pid
    holder_pid="$(cat "$LOCK_FILE" 2>/dev/null)"
    if [[ "$holder_pid" == "$$" ]]; then
      # Update mtime to now (records when consolidation completed)
      touch "$LOCK_FILE"
      # Clear PID but keep file (mtime is the timer)
      echo "" > "$LOCK_FILE"
    fi
  fi
}

# Rollback lock mtime on failure (so next attempt doesn't wait full interval)
rollback_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    # Set mtime back to epoch so consolidation is immediately due again
    touch -t 197001010000 "$LOCK_FILE" 2>/dev/null || true
    echo "" > "$LOCK_FILE"
  fi
}

# ---------------------------------------------------------------------------
# Memory file parsing
# ---------------------------------------------------------------------------

# Extract a frontmatter field from a memory file
# Usage: get_frontmatter_field "file.md" "type"
get_frontmatter_field() {
  local file="$1"
  local field="$2"
  sed -n '/^---$/,/^---$/p' "$file" 2>/dev/null | grep "^${field}:" | head -1 | sed "s/^${field}:[[:space:]]*//"
}

# Get content after frontmatter
get_content() {
  local file="$1"
  sed '1,/^---$/d' "$file" 2>/dev/null | sed '1,/^---$/d'
}

# ---------------------------------------------------------------------------
# ME.md index management
# ---------------------------------------------------------------------------

# Rebuild a subfolder's ME.md index from its topic files
rebuild_subfolder_index() {
  local subfolder="$1"
  local subfolder_name
  subfolder_name="$(basename "$subfolder")"
  local me_file="$subfolder/ME.md"

  local category_desc=""
  case "$subfolder_name" in
    interaction-style) category_desc="How you interact with Claude Code — verbosity, planning style, feedback patterns" ;;
    projects)          category_desc="High-level overview of your active projects and what you're building" ;;
    rules)             category_desc="Rules and corrections you consistently apply across projects" ;;
    patterns)          category_desc="Recurring decision patterns, workflow habits, and tool preferences" ;;
    *)                 category_desc="$subfolder_name entries" ;;
  esac

  {
    echo "# $subfolder_name"
    echo ""
    echo "> $category_desc"
    echo ""

    local has_entries=false
    for f in "$subfolder"/*.md; do
      [[ -f "$f" ]] || continue
      [[ "$(basename "$f")" == "ME.md" ]] && continue
      has_entries=true
      local name desc fname
      name="$(get_frontmatter_field "$f" "name")"
      desc="$(get_frontmatter_field "$f" "description")"
      fname="$(basename "$f")"
      echo "- [$name]($fname) — $desc"
    done

    if [[ "$has_entries" == "false" ]]; then
      echo "<!-- No entries yet -->"
    fi
  } > "$me_file"
}

# Rebuild the top-level corpus ME.md from all subfolders
rebuild_top_index() {
  local me_file="$CORPUS_DIR/ME.md"

  {
    echo "# Me Agent"
    echo ""
    echo "> Cross-project preferences, patterns, and behaviors accumulated from Claude Code usage."
    echo ""

    for subfolder in "$CORPUS_DIR"/*/; do
      [[ -d "$subfolder" ]] || continue
      local subfolder_name
      subfolder_name="$(basename "$subfolder")"

      # Count topic files (exclude ME.md)
      local count=0
      for f in "$subfolder"/*.md; do
        [[ -f "$f" ]] || continue
        [[ "$(basename "$f")" == "ME.md" ]] && continue
        count=$((count + 1))
      done

      echo "- [$subfolder_name/]($subfolder_name/ME.md) — $count entries"
    done
  } > "$me_file"
}

# ---------------------------------------------------------------------------
# Source tracking — track which CC memory files we've already processed
# ---------------------------------------------------------------------------

# Get the mtime of a file as epoch seconds
get_mtime() {
  local file="$1"
  stat -f '%m' "$file" 2>/dev/null || stat -c '%Y' "$file" 2>/dev/null
}

# Check if a source file has already been processed (same path + mtime)
# Returns 0 if already processed (skip), 1 if new or updated (process)
is_already_processed() {
  local source_key="$1"  # slug/filename
  local mtime="$2"

  if [[ ! -f "$PROCESSED_FILE" ]]; then
    return 1  # No manifest yet, everything is new
  fi

  grep -q "^${source_key} ${mtime}$" "$PROCESSED_FILE" 2>/dev/null
}

# Mark a source file as processed
mark_processed() {
  local source_key="$1"  # slug/filename
  local mtime="$2"

  mkdir -p "$(dirname "$PROCESSED_FILE")"

  # Remove any old entry for this source key (mtime may have changed)
  if [[ -f "$PROCESSED_FILE" ]]; then
    local tmp
    tmp="$(mktemp)"
    grep -v "^${source_key} " "$PROCESSED_FILE" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$PROCESSED_FILE"
  fi

  # Append new entry
  echo "${source_key} ${mtime}" >> "$PROCESSED_FILE"
}

# ---------------------------------------------------------------------------
# Cost tracking
# ---------------------------------------------------------------------------

# Initialize costs.csv with header if it doesn't exist
init_costs_file() {
  if [[ ! -f "$COSTS_FILE" ]]; then
    mkdir -p "$(dirname "$COSTS_FILE")"
    echo "timestamp,type,model,input_chars,output_chars,est_input_tokens,est_output_tokens,est_cost_usd" > "$COSTS_FILE"
  fi
}

# Record a haiku call's estimated cost
# Usage: record_cost "extraction|consolidation" "model" "input_chars" "output_chars"
record_cost() {
  local call_type="$1"
  local model="$2"
  local input_chars="$3"
  local output_chars="$4"

  init_costs_file

  # Estimate tokens (roughly 1 token per 4 chars)
  local input_tokens=$(( input_chars / 4 ))
  local output_tokens=$(( output_chars / 4 ))

  # Haiku pricing: $0.80/M input, $4.00/M output
  # Use integer math in cents to avoid bc dependency
  # input_cost_microcents = input_tokens * 80 / 1000000
  # output_cost_microcents = output_tokens * 400 / 1000000
  # Simplified: cost_usd = (input_tokens * 0.8 + output_tokens * 4.0) / 1000000
  local est_cost
  if command -v python3 &>/dev/null; then
    est_cost="$(python3 -c "print(f'{($input_tokens * 0.8 + $output_tokens * 4.0) / 1000000:.6f}')")"
  else
    est_cost="0.000000"
  fi

  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  echo "$ts,$call_type,$model,$input_chars,$output_chars,$input_tokens,$output_tokens,$est_cost" >> "$COSTS_FILE"
  log "Cost: ~\$$est_cost ($call_type, ~${input_tokens} in / ~${output_tokens} out)"
}

# Print cost summary
# ---------------------------------------------------------------------------
# Notes — user-injected preferences
# ---------------------------------------------------------------------------

# Write a note to the notes directory. Returns the path of the created file.
# Usage: write_note "always run tests before committing"
write_note() {
  local text="$1"
  if [[ -z "$text" ]]; then
    echo "Note text is required" >&2
    return 1
  fi

  mkdir -p "$NOTES_DIR"

  local ts
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  # Derive a slug from the first few words for readability
  local slug
  slug="$(echo "$text" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-50 | sed 's/-$//')"
  local fname="${ts}-${slug}.md"
  local fpath="$NOTES_DIR/$fname"

  cat > "$fpath" <<EOF
---
name: User note
description: $text
source: clm-note
created: $ts
---

$text
EOF

  echo "$fpath"
}

# Collect unprocessed notes and append them to a candidates file.
# Usage: collect_notes "$CANDIDATES_FILE" "$SOURCES_FILE"
# Returns the number of notes collected (via global NOTE_COUNT).
NOTE_COUNT=0
collect_notes() {
  local candidates_file="$1"
  local sources_file="$2"
  NOTE_COUNT=0

  if [[ ! -d "$NOTES_DIR" ]]; then
    return
  fi

  for note_file in "$NOTES_DIR"/*.md; do
    [[ -f "$note_file" ]] || continue

    local fname
    fname="$(basename "$note_file")"
    local source_key="notes/$fname"
    local file_mtime
    file_mtime="$(get_mtime "$note_file")"

    if is_already_processed "$source_key" "$file_mtime"; then
      continue
    fi

    local note_content
    note_content="$(cat "$note_file")"

    echo "$source_key $file_mtime" >> "$sources_file"

    {
      echo "---SOURCE: user-note / $fname---"
      echo "$note_content"
      echo ""
    } >> "$candidates_file"

    NOTE_COUNT=$((NOTE_COUNT + 1))
  done
}

# ---------------------------------------------------------------------------
# Pending interview questions
# ---------------------------------------------------------------------------

# Returns the number of pending interview questions (0 if none)
pending_question_count() {
  if [[ ! -f "$QUESTIONS_FILE" ]]; then
    echo 0
    return
  fi
  jq 'length' "$QUESTIONS_FILE" 2>/dev/null || echo 0
}

# Print a notification if there are pending questions
notify_pending_questions() {
  local count
  count="$(pending_question_count)"
  if [[ "$count" -gt 0 ]]; then
    echo ""
    echo "  $count interview question(s) pending — run 'clm interview' or '/claude-me interview'"
  fi
}

# ---------------------------------------------------------------------------
# Cost tracking
# ---------------------------------------------------------------------------

print_cost_summary() {
  if [[ ! -f "$COSTS_FILE" ]] || [[ $(wc -l < "$COSTS_FILE") -le 1 ]]; then
    echo "No cost data yet."
    return
  fi

  python3 - "$COSTS_FILE" << 'PYEOF'
import csv, sys
from datetime import datetime, timezone, timedelta
from collections import defaultdict

costs_file = sys.argv[1] if len(sys.argv) > 1 else ""
if not costs_file:
    print("No costs file specified")
    sys.exit(1)

rows = []
with open(costs_file) as f:
    reader = csv.DictReader(f)
    for row in reader:
        row["est_cost_usd"] = float(row["est_cost_usd"])
        row["est_input_tokens"] = int(row["est_input_tokens"])
        row["est_output_tokens"] = int(row["est_output_tokens"])
        row["dt"] = datetime.fromisoformat(row["timestamp"].replace("Z", "+00:00"))
        rows.append(row)

if not rows:
    print("No cost data yet.")
    sys.exit(0)

now = datetime.now(timezone.utc)
today = now.date()
month_start = today.replace(day=1)

total_cost = sum(r["est_cost_usd"] for r in rows)
total_calls = len(rows)
today_rows = [r for r in rows if r["dt"].date() == today]
today_cost = sum(r["est_cost_usd"] for r in today_rows)
month_rows = [r for r in rows if r["dt"].date() >= month_start]
month_cost = sum(r["est_cost_usd"] for r in month_rows)

# Daily breakdown (last 7 days)
daily = defaultdict(float)
for r in rows:
    daily[r["dt"].strftime("%Y-%m-%d")] += r["est_cost_usd"]

# By type
by_type = defaultdict(lambda: {"calls": 0, "cost": 0.0})
for r in rows:
    by_type[r["type"]]["calls"] += 1
    by_type[r["type"]]["cost"] += r["est_cost_usd"]

print("=" * 50)
print("  claude-me Cost Summary")
print("=" * 50)
print(f"  Total calls:     {total_calls}")
print(f"  Total cost:      ${total_cost:.4f}")
print(f"  Today's cost:    ${today_cost:.4f}  ({len(today_rows)} calls)")
print(f"  This month:      ${month_cost:.4f}  ({len(month_rows)} calls)")
if total_calls > 0:
    print(f"  Avg per call:    ${total_cost / total_calls:.4f}")
print()

print("  By type:")
for t, d in sorted(by_type.items()):
    print(f"    {t:20s}  {d['calls']:3d} calls  ${d['cost']:.4f}")
print()

print("  Daily (last 7 days):")
last_7 = sorted(daily.items())[-7:]
for day, cost in last_7:
    print(f"    {day}  ${cost:.4f}")
print("=" * 50)
PYEOF
}
