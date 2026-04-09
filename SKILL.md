---
name: me-agent
description: Personal interaction wiki — cross-project preferences and behaviors from Claude Code usage. Use when adapting to user preferences, checking interaction style, or when user asks to sync/update their profile.
argument-hint: "[sync|consolidate|costs|status|note \"...\"|interview]"
user-invocable: true
---

# Me Agent

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

Extract cross-project preferences from all active Claude Code memory folders:

```bash
clm sync
```

Report what was extracted: how many projects scanned, how many new entries added, and which categories they landed in.

### Consolidate Mode (`/me-agent consolidate`)

Merge duplicates, resolve contradictions, prune project-specific leaks (like Claude Code's `/dream`):

```bash
clm consolidate
```

Report what changed: entries merged, deleted, moved, or updated.

### Costs Mode (`/me-agent costs`)

Show accumulated Haiku API cost summary:

```bash
clm costs
```

### Note Mode (`/me-agent note "..."`)

Add a preference note to be processed on next sync:

```bash
clm note "always run tests before committing"
clm note "always run tests before committing" --now            # blocks until processed
clm note "always run tests before committing" --now --detach   # processes in background
```

Without `--now`, the note is just saved to disk (instant). With `--now`, add `--detach` to avoid blocking the session.

### Interview Mode (`/me-agent interview`)

Present pending interview questions to the user and process their answers. Questions are generated during consolidation when Haiku encounters conflicts or ambiguities it cannot resolve alone.

1. Read `~/.claude/me-agent/pending-questions.json`
2. If no questions, tell the user there are no pending questions
3. Present each question conversationally — show the question, context, and related entries
4. For each answer the user gives, run: `clm note "Re: <question> — <answer>" --now --detach`
5. After each answer, clear it: `clm interview --clear <question-id>`
6. After all questions are answered, or to clear all at once: `clm interview --clear-all`

### Status Mode (`/me-agent status`)

Show corpus stats and system status:

```bash
clm status
```

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

Each topic file has YAML frontmatter (`name`, `description`) and markdown content with optional `**Why:**` and `**How to apply:**` sections.
