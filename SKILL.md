---
name: me-agent
description: Personal interaction wiki — cross-project preferences and behaviors from Claude Code usage. Use when adapting to user preferences, checking interaction style, or when user asks to sync/update their profile.
argument-hint: "[sync|consolidate|costs]"
user-invocable: true
---

# Me Agent

A cross-project persona wiki that accumulates your preferences, patterns, and behaviors from Claude Code usage.

## How to Use

### Read Mode (no arguments)

Load the user's preference corpus to adapt your responses.

1. Read `~/.claude/me-agent/corpus/ME.md` to get the top-level index
2. Based on the current conversation context, read relevant subfolder ME.md files:
   - `~/.claude/me-agent/corpus/interaction-style/ME.md` — how the user communicates
   - `~/.claude/me-agent/corpus/rules/ME.md` — rules the user enforces
   - `~/.claude/me-agent/corpus/patterns/ME.md` — workflow habits and preferences
   - `~/.claude/me-agent/corpus/projects/ME.md` — what the user is building
3. Read specific topic files listed in the subfolder indexes if they're relevant
4. Apply this knowledge naturally — don't announce it, just adapt

### Sync Mode (`/me-agent sync`)

Trigger extraction from all active project memory folders:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/extract.sh --all-active
```

Report what was extracted: how many projects scanned, how many new entries added, and which categories they landed in.

### Consolidate Mode (`/me-agent consolidate`)

Trigger corpus consolidation — the equivalent of Claude Code's `/dream`. Merges duplicates, resolves contradictions, prunes project-specific leaks:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/consolidate.sh --force
```

Report what changed: entries merged, deleted, moved, or updated.

### Costs Mode (`/me-agent costs`)

Show accumulated cost summary:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/costs.sh
```

Shows total cost, today's cost, this month's cost, average per call, and daily breakdown.

## Corpus Structure

The corpus lives at `~/.claude/me-agent/corpus/` (outside the skill repo — your personal data stays private):

```
~/.claude/me-agent/corpus/
  ME.md                     Top-level index
  interaction-style/        How you talk to Claude Code
    ME.md + topic files
  projects/                 What you're building
    ME.md + topic files
  rules/                    Rules you enforce
    ME.md + topic files
  patterns/                 Workflow habits
    ME.md + topic files
```

Each topic file uses markdown with YAML frontmatter (name, description) — same format as Claude Code memory files.

## Notes

- The corpus is project-agnostic — it captures patterns that span across projects
- Entries are extracted from Claude Code's own project memory folders (piggybacking on CC's extraction/consolidation)
- Extraction runs automatically via SessionEnd hook, or manually via `/me-agent sync`
- Consolidation runs every 24 hours (configurable) or manually via `/me-agent consolidate`
- Corpus and logs live at `~/.claude/me-agent/`, separate from the skill repo
