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

## clm verify

Mark a corpus entry as verified — bumps `last_verified` to today and increments `verify_count`.

```bash
clm verify rules/never-commit-untested.md
clm verify /Users/you/.claude/claude-me/corpus/rules/never-commit-untested.md
```

Use after reading an entry and confirming it still applies. Refuses to operate on files outside the corpus directory.

## clm delete

Soft-delete a corpus entry. Recoverable from `~/.claude/claude-me/trash/` for 7 days (configurable via `trash_retention_days`).

```bash
clm delete rules/old-rule.md
clm delete rules/old-rule.md --yes    # skip confirmation
```

Refuses to operate on files outside the corpus directory. Recovery: `mv ~/.claude/claude-me/trash/<trashed-name> ~/.claude/claude-me/corpus/<original-path>`.

## clm open

Open the corpus directory in VS Code.

```bash
clm open
```

Tries the `code` shell command first; falls back to `open -a "Visual Studio Code"`. Useful for browsing or editing entries directly.

## clm daemon

Manage the optional daily notification daemon. Disabled by default — opt in with `clm daemon enable`. Surfaces one weighted-random corpus entry per day at 9am via macOS notification (passive: click opens the file in VS Code).

```bash
clm daemon enable    # register LaunchAgent, fire one test notification
clm daemon disable   # unregister
clm daemon test      # fire one notification right now
clm daemon status    # show registration state and schedule
```

Requires `terminal-notifier` (`brew install terminal-notifier`). Schedule, weights, and threshold are configurable in `config.json` via `daemon_hour`, `daemon_minute`, `daemon_stale_weight`, `daemon_unverified_weight`, `daemon_fresh_weight`, and `daemon_stale_threshold_days`.

The daemon is currently passive: notifications have a single click action that opens the file in VS Code. Verifying or deleting an entry happens via `clm verify` and `clm delete` separately.

## clm install

Set up claude-me: skill symlink, SessionEnd hook, status line, corpus directory, CLAUDE.md hint, freshness migration. Detects `terminal-notifier` and warns if missing (only relevant if you plan to enable the daemon).

```bash
clm install              # CLAUDE.md hint in ~/.claude/CLAUDE.md (global)
clm install --local      # CLAUDE.md hint in ./CLAUDE.md (current project)
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
| `/claude-me verify <entry>` | `clm verify <entry>` |
| `/claude-me delete <entry>` | `clm delete <entry>` |
| `/claude-me open` | `clm open` |
| `/claude-me daemon enable` | `clm daemon enable` |
| `/claude-me costs` | `clm costs` |
| `/claude-me status` | `clm status` |
