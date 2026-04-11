#!/usr/bin/env python3
# claude-me weighted-random entry picker
#
# Walks $CORPUS_DIR/*/<*.md>, parses frontmatter, computes a weight per entry,
# and prints the absolute path of one weighted-randomly selected entry to
# stdout. Used by the daemon (notify-daily.sh) to decide which entry to
# surface in the daily notification.
#
# Weights (configurable via config.json):
#   stale        = entries with last_verified older than N days (default 3x)
#   unverified   = entries with verify_count == 0 (default 2x)
#   fresh        = everything else (default 1x)
# A single entry takes the MAX weight it qualifies for, not the sum.
#
# Usage: pick-entry.py <corpus_dir> [stale_weight] [unverified_weight]
#                      [fresh_weight] [stale_threshold_days]
#
# Exits 0 and prints path on success. Exits 0 and prints nothing if the
# corpus is empty — callers should treat empty stdout as "skip notification".

import random
import re
import sys
from datetime import date, datetime, timedelta
from pathlib import Path


def parse_args():
    if len(sys.argv) < 2:
        print("usage: pick-entry.py <corpus_dir> [stale_w] [unv_w] [fresh_w] [stale_days]", file=sys.stderr)
        sys.exit(2)
    corpus = Path(sys.argv[1])
    stale_w = float(sys.argv[2]) if len(sys.argv) > 2 else 3.0
    unv_w = float(sys.argv[3]) if len(sys.argv) > 3 else 2.0
    fresh_w = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
    stale_days = int(sys.argv[5]) if len(sys.argv) > 5 else 30
    return corpus, stale_w, unv_w, fresh_w, stale_days


LAST_VERIFIED_RE = re.compile(r'^last_verified:\s*(.+)$', re.MULTILINE)
VERIFY_COUNT_RE = re.compile(r'^verify_count:\s*(\d+)$', re.MULTILINE)


def entry_weight(path, today, stale_cutoff, stale_w, unv_w, fresh_w):
    """Return the weight for a single entry, based on its freshness fields."""
    try:
        content = path.read_text()
    except OSError:
        return fresh_w

    is_stale = False
    lv_match = LAST_VERIFIED_RE.search(content)
    if lv_match:
        value = lv_match.group(1).strip().strip('"').strip("'")
        try:
            lv = datetime.strptime(value, '%Y-%m-%d').date()
            if lv < stale_cutoff:
                is_stale = True
        except ValueError:
            # Malformed — repair-freshness will normalize on next sync, but
            # for weighting purposes we treat it as stale (something's off).
            is_stale = True
    else:
        # Missing field — treat as stale
        is_stale = True

    is_unverified = False
    vc_match = VERIFY_COUNT_RE.search(content)
    if vc_match:
        try:
            if int(vc_match.group(1)) == 0:
                is_unverified = True
        except ValueError:
            is_unverified = True
    else:
        is_unverified = True

    # Take the MAX weight this entry qualifies for. We don't sum because
    # "stale AND unverified" shouldn't be 5x — stale already captures
    # "needs attention".
    if is_stale:
        return stale_w
    if is_unverified:
        return unv_w
    return fresh_w


def main():
    corpus, stale_w, unv_w, fresh_w, stale_days = parse_args()

    if not corpus.exists():
        sys.exit(0)

    today = date.today()
    stale_cutoff = today - timedelta(days=stale_days)

    entries = []
    weights = []
    for category_dir in corpus.iterdir():
        if not category_dir.is_dir():
            continue
        # Defensive: skip anything prefixed with _ (e.g. _trash, _archive)
        if category_dir.name.startswith('_'):
            continue
        for f in category_dir.glob('*.md'):
            if f.name == 'ME.md':
                continue
            w = entry_weight(f, today, stale_cutoff, stale_w, unv_w, fresh_w)
            entries.append(f)
            weights.append(w)

    if not entries:
        sys.exit(0)  # Empty corpus, caller skips

    picked = random.choices(entries, weights=weights, k=1)[0]
    print(picked)


if __name__ == '__main__':
    main()
