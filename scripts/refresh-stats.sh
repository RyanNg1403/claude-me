#!/bin/bash
# claude-me stats cache refresher
# Standalone wrapper around write_stats_cache for callers that aren't
# extract.sh or consolidate.sh (e.g. clm interview --clear*).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "$SCRIPT_DIR/utils.sh"

write_stats_cache
