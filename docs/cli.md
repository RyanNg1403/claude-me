# CLI Reference

## clm sync

Extract cross-project preferences from Claude Code memory folders.

```bash
clm sync                    # all active projects
clm sync -p /path/to/project  # specific project
clm sync -p .                # current directory
```

Also picks up any pending notes.

## clm note

Add a preference note to be processed during next sync.

```bash
clm note "always run tests before committing"
clm note "prefer early returns" --now              # process immediately (blocks)
clm note "no trailing summaries" --now --detach    # process in background
```

Without `--now`, the note is saved to disk instantly and processed on next sync. Notes are evaluated critically by Haiku — not blindly added. Notes can override or delete existing corpus entries on conflict.

## clm consolidate

Merge duplicates, resolve contradictions, and prune the corpus.

```bash
clm consolidate
clm consolidate "merge all PR-related entries"
clm consolidate "prune stale entries"
```

Optional focus text guides Haiku to prioritize specific criteria. Generates interview questions when conflicts can't be resolved automatically.

## clm interview

Answer pending interview questions generated during consolidation.

```bash
clm interview              # open questions in $EDITOR
clm interview --list       # list questions without editor
clm interview --clear <id> # clear a specific question
clm interview --clear-all  # clear all questions
```

Also available as `/claude-me interview` in Claude Code — presents questions conversationally.

## clm costs

Show accumulated Haiku API cost breakdown.

```bash
clm costs
clm costs --reset    # clear cost history
```

## clm status

Show corpus stats and system health.

```bash
clm status
```

Shows: entry counts per category, processed source files, last extraction/consolidation times, total API cost, and pending interview questions.

## clm install

Set up claude-me: skill symlink, SessionEnd hook, corpus directory, CLAUDE.md hint.

```bash
clm install              # CLAUDE.md hint in ~/.claude/CLAUDE.md (global)
clm install --project    # CLAUDE.md hint in ./CLAUDE.md (current project)
```

## clm uninstall

Remove everything: hook, symlink, CLAUDE.md hint, and data directory.

```bash
clm uninstall            # confirmation prompt first
clm uninstall --yes      # skip confirmation
```

## Claude Code Skill

All commands are also available as a Claude Code skill:

| Skill Command | Equivalent CLI |
|---------------|---------------|
| `/claude-me` | Load preferences into context |
| `/claude-me sync` | `clm sync` |
| `/claude-me consolidate` | `clm consolidate` |
| `/claude-me consolidate "..."` | `clm consolidate "..."` |
| `/claude-me note "..."` | `clm note "..."` |
| `/claude-me interview` | `clm interview` |
| `/claude-me costs` | `clm costs` |
| `/claude-me status` | `clm status` |
