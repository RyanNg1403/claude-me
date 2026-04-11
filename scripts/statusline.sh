#!/bin/bash
# claude-me status line — renders corpus pulse for Claude Code's statusLine.
#
# Output format:
#   "clm 47"               (green)            — always shown
#   "clm 47 · 1 pending"   (green + orange)   — pending interview questions
#
# Staleness is intentionally invisible from the status line. A growing stale
# counter creates debt anxiety and turns the corpus into homework. Stale
# entries surface only via `clm glance`, which is the action surface.
#
# Reads from $DATA_DIR/.stats.json (refreshed by extract / consolidate /
# interview pipelines). Falls back to inline computation if cache is missing
# or older than $CACHE_TTL seconds. This keeps per-turn renders fast while
# still picking up changes between sessions.
#
# Wired up by clm install via ~/.claude/settings.json statusLine field.
# Receives JSON context on stdin from Claude Code (currently unused).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "$SCRIPT_DIR/utils.sh"

# Drain stdin so CC doesn't see EPIPE on the JSON context it sends.
cat > /dev/null

CACHE_TTL=300  # 5 minutes

needs_refresh=true
if [[ -f "$STATS_FILE" ]]; then
  cache_mtime="$(stat -f '%m' "$STATS_FILE" 2>/dev/null || stat -c '%Y' "$STATS_FILE" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  age=$((now - cache_mtime))
  if [[ $age -lt $CACHE_TTL ]]; then
    needs_refresh=false
  fi
fi

if [[ "$needs_refresh" == "true" ]]; then
  write_stats_cache 2>/dev/null || true
fi

if [[ ! -f "$STATS_FILE" ]]; then
  # No cache and no corpus to compute from — print nothing
  exit 0
fi

if command -v jq &>/dev/null; then
  total="$(jq -r '.total // 0' "$STATS_FILE" 2>/dev/null || echo 0)"
  stale="$(jq -r '.stale // 0' "$STATS_FILE" 2>/dev/null || echo 0)"
  pending="$(jq -r '.pending // 0' "$STATS_FILE" 2>/dev/null || echo 0)"
else
  total=0; stale=0; pending=0
fi

# Don't render anything for an empty corpus — silence is better than "clm 0"
if [[ "$total" -eq 0 ]]; then
  exit 0
fi

# ANSI colors. Honors the standard NO_COLOR env var (https://no-color.org).
# Green via basic 16-color (universally supported); orange via 256-color
# (foreground 208 is a true orange, distinct from yellow/red).
if [[ -n "${NO_COLOR:-}" ]]; then
  C_GREEN=""; C_ORANGE=""; C_DIM=""; C_RESET=""
else
  C_GREEN=$'\033[32m'
  C_ORANGE=$'\033[38;5;208m'
  C_DIM=$'\033[2m'
  C_RESET=$'\033[0m'
fi

out="${C_GREEN}clm${C_RESET} $total"
[[ "$pending" -gt 0 ]] && out="$out${C_DIM} · ${C_RESET}${C_ORANGE}$pending pending${C_RESET}"

echo "$out"
