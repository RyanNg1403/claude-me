#!/bin/bash
# claude-me — mark one entry as verified
#
# Bumps `last_verified` to today and increments `verify_count` on a single
# corpus entry. Called from the daemon's "Still true" action handler.
# Also used by any future interactive verify surface (e.g. `clm glance` if
# we ever build it).
#
# Usage: mark-verified.sh <path/to/entry.md>
#
# Exits 0 on success, 1 if the file doesn't exist or has no frontmatter.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: mark-verified.sh <file>" >&2
  exit 2
fi

FILE="$1"

if [[ ! -f "$FILE" ]]; then
  echo "mark-verified: file not found: $FILE" >&2
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "mark-verified: python3 required" >&2
  exit 1
fi

TODAY="$(date -u +%Y-%m-%d)"

python3 - "$FILE" "$TODAY" <<'PYEOF'
import re
import sys

path = sys.argv[1]
today = sys.argv[2]

with open(path) as fh:
    content = fh.read()

# Only touch frontmatter region (first --- ... --- block)
m = re.match(r'^---\n(.*?)\n---(\n?.*)$', content, re.DOTALL)
if not m:
    sys.stderr.write(f'mark-verified: no frontmatter in {path}\n')
    sys.exit(1)

fm = m.group(1)
body = m.group(2)

# Update last_verified: set to today (create if missing)
if re.search(r'^last_verified:', fm, re.MULTILINE):
    fm = re.sub(r'^last_verified:.*$', f'last_verified: {today}', fm, count=1, flags=re.MULTILINE)
else:
    fm = fm.rstrip() + f'\nlast_verified: {today}'

# Increment verify_count (create if missing, start at 1)
def bump(match):
    try:
        n = int(match.group(1)) + 1
    except ValueError:
        n = 1
    return f'verify_count: {n}'

if re.search(r'^verify_count:\s*(\S+)', fm, re.MULTILINE):
    fm = re.sub(r'^verify_count:\s*(\S+).*$', bump, fm, count=1, flags=re.MULTILINE)
else:
    fm = fm.rstrip() + '\nverify_count: 1'

new_content = f'---\n{fm}\n---{body}'
with open(path, 'w') as fh:
    fh.write(new_content)
PYEOF
