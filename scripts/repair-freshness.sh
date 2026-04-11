#!/bin/bash
# claude-me freshness metadata repair sweep
#
# Walks $CORPUS_DIR/*/<*.md> (excluding ME.md) and ensures every entry has
# valid created_at, last_verified, and verify_count frontmatter fields.
# Idempotent and self-healing — safe to run any time.
#
# Used as:
#   1. One-shot migration during `clm install` for pre-existing corpus
#   2. Post-process at the end of extract.sh and consolidate.sh to catch
#      any drift in fields Haiku writes
#
# Defaults when fields are missing:
#   created_at    = file mtime (date portion)
#   last_verified = file mtime (date portion)
#   verify_count  = 0
#
# Date format: YYYY-MM-DD. Anything else gets normalized or replaced with
# the file mtime.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "$SCRIPT_DIR/utils.sh"

if [[ ! -d "$CORPUS_DIR" ]]; then
  exit 0
fi

if ! command -v python3 &>/dev/null; then
  log "WARNING: python3 not found, skipping freshness repair"
  exit 0
fi

python3 - "$CORPUS_DIR" <<'PYEOF'
import sys, os, re
from datetime import datetime, date
from pathlib import Path

corpus_dir = Path(sys.argv[1])

DATE_RE = re.compile(r'^\d{4}-\d{2}-\d{2}$')
FRONTMATTER_RE = re.compile(r'^---\n(.*?)\n---(\n?.*)$', re.DOTALL)


def normalize_date(value):
    if value is None:
        return None
    s = value.strip().strip('"').strip("'")
    if not DATE_RE.match(s):
        return None
    try:
        datetime.strptime(s, '%Y-%m-%d')
        return s
    except ValueError:
        return None


def normalize_int(value):
    if value is None:
        return None
    try:
        n = int(value.strip())
        return max(0, n)
    except ValueError:
        return None


def parse_frontmatter(text):
    """Return (ordered_keys, dict). First-occurrence wins on duplicates."""
    fields = {}
    order = []
    for line in text.split('\n'):
        if ':' not in line:
            continue
        key, _, value = line.partition(':')
        key = key.strip()
        value = value.strip()
        if not key or key in fields:
            continue
        fields[key] = value
        order.append(key)
    return order, fields


def serialize_frontmatter(order, fields):
    return '\n'.join(f'{k}: {fields[k]}' for k in order)


checked = 0
repaired = 0

for category_dir in sorted(corpus_dir.iterdir()):
    if not category_dir.is_dir():
        continue
    for f in sorted(category_dir.glob('*.md')):
        if f.name == 'ME.md':
            continue
        checked += 1

        try:
            content = f.read_text()
        except OSError:
            continue

        m = FRONTMATTER_RE.match(content)
        if not m:
            # No frontmatter at all — skip silently. We don't fabricate one.
            continue

        fm_text = m.group(1)
        body = m.group(2)
        order, fields = parse_frontmatter(fm_text)

        mtime_date = datetime.fromtimestamp(f.stat().st_mtime).date().isoformat()
        changed = False

        # created_at
        norm = normalize_date(fields.get('created_at'))
        if norm is None:
            fields['created_at'] = mtime_date
            if 'created_at' not in order:
                order.append('created_at')
            changed = True
        elif norm != fields['created_at']:
            fields['created_at'] = norm
            changed = True

        # last_verified
        norm = normalize_date(fields.get('last_verified'))
        if norm is None:
            fields['last_verified'] = mtime_date
            if 'last_verified' not in order:
                order.append('last_verified')
            changed = True
        elif norm != fields['last_verified']:
            fields['last_verified'] = norm
            changed = True

        # verify_count
        norm = normalize_int(fields.get('verify_count'))
        if norm is None:
            fields['verify_count'] = '0'
            if 'verify_count' not in order:
                order.append('verify_count')
            changed = True
        elif str(norm) != fields['verify_count']:
            fields['verify_count'] = str(norm)
            changed = True

        if not changed:
            continue

        new_fm = serialize_frontmatter(order, fields)
        new_content = f'---\n{new_fm}\n---{body}'
        try:
            f.write_text(new_content)
        except OSError:
            continue
        repaired += 1
        print(f'  repaired: {category_dir.name}/{f.name}', file=sys.stderr)

print(f'  freshness sweep: checked={checked} repaired={repaired}', file=sys.stderr)
PYEOF
