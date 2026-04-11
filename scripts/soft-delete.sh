#!/bin/bash
# claude-me soft delete wrapper — thin CLI around utils.sh soft_delete()
#
# Used by `clm delete` (and anywhere else we need a scriptable soft delete).
# Moves a corpus entry into $TRASH_DIR with a timestamped name. Recoverable
# via `mv` until cleanup_trash() prunes it (default: 7 days).

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: soft-delete.sh <absolute-path-to-corpus-entry>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "$SCRIPT_DIR/utils.sh"

soft_delete "$1"
