#!/bin/bash
# claude-me cost tracker
# Shows accumulated costs from haiku calls.
#
# Usage:
#   costs.sh          Print cost summary
#   costs.sh --reset  Clear cost history

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

if [[ "${1:-}" == "--reset" ]]; then
  rm -f "$COSTS_FILE"
  echo "Cost history cleared."
  exit 0
fi

print_cost_summary
