# claude-me

> A cross-project persona wiki for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Learns how you work — not what you build.

Claude Code's memory is project-scoped. You correct it in one project ("don't commit without asking"), but the next project doesn't know. **claude-me** fixes this by extracting cross-project preferences from your existing Claude Code memories into a single, portable corpus.

## How It Works

```mermaid
graph TD
    A["You use Claude Code across projects"] --> B["CC's own agents extract + consolidate memories
    into ~/.claude/projects/.../memory/*.md"]
    B --> C{Session ends}
    C --> D["hook-handler.sh
    Queues session info, spawns background job
    (exits in < 3s)"]

    D --> E["extract.sh (background, async)"]

    E --> E1["1. Read project memory files"]
    E1 --> E2["2. Filter by type + source tracking (free)"]
    E2 --> E3{"New candidates?"}
    E3 -- No --> E3N["Exit — zero cost"]
    E3 -- Yes --> E4["3. Haiku with tool access classifies + writes corpus files directly"]

    E4 --> F{24h since last consolidation?}
    F -- Yes --> G["consolidate.sh
    Haiku reads, merges, prunes corpus via tools"]
    F -- No --> H["Done"]
    G --> H

    style A fill:#1a1a2e,stroke:#6366f1,color:#e2e8f0
    style B fill:#1a1a2e,stroke:#6366f1,color:#e2e8f0
    style C fill:#312e81,stroke:#818cf8,color:#e2e8f0
    style D fill:#1e3a5f,stroke:#38bdf8,color:#e2e8f0
    style E fill:#1e3a5f,stroke:#38bdf8,color:#e2e8f0
    style E1 fill:#1a2e1a,stroke:#4ade80,color:#e2e8f0
    style E2 fill:#1a2e1a,stroke:#4ade80,color:#e2e8f0
    style E3 fill:#312e81,stroke:#818cf8,color:#e2e8f0
    style E3N fill:#5a5a5a,stroke:#888,color:#fff
    style E4 fill:#3b1a1a,stroke:#f97316,color:#e2e8f0
    style F fill:#312e81,stroke:#818cf8,color:#e2e8f0
    style G fill:#3b1a1a,stroke:#f97316,color:#e2e8f0
    style H fill:#1a1a2e,stroke:#6366f1,color:#e2e8f0
```

> **Key insight:** We never mine raw transcripts. Claude Code already spent the tokens to extract and consolidate project memories. We read those pre-refined `.md` files, filter with source tracking (zero tokens), and only give Haiku the new candidates with direct tool access to write corpus files.

## Cost

| Scenario | Cost |
|----------|------|
| **Per session** (steady state, ~3 candidates) | **~$0.002** |
| **Consolidation** (daily) | **~$0.003** |
| **Monthly** (10 sessions/day) | **~$0.69** |
| **No new memories** (most sessions) | **$0.00** |

All calls use Haiku ($0.80/M input, $4.00/M output). Most work is bash scripts at zero token cost. If no new memories are found, haiku is never called.

## Install

```bash
git clone https://github.com/user/me-agent.git
cd me-agent
bash install.sh
```

This will:
1. Symlink the skill to `~/.claude/skills/me-agent/`
2. Create `~/.claude/me-agent/` for your personal data (corpus, logs)
3. Register a `SessionEnd` hook in `~/.claude/settings.json`
4. Set SessionEnd hook timeout to 3s

Your preferences are stored at `~/.claude/me-agent/corpus/`, separate from the repo — never committed to git.

**Requires:** `jq`, `claude` CLI

## Usage

| Command | What it does |
|---------|--------------|
| `/me-agent` | Load your preference corpus into context |
| `/me-agent sync` | Extract from all active projects now |
| `/me-agent consolidate` | Merge, deduplicate, prune the corpus (like CC's `/dream`) |

After installation, extraction runs **automatically** when each Claude Code session ends. The corpus grows over time with no manual effort.

## How Extraction Decides What's New

Instead of grepping for content similarity (which misses paraphrases), claude-me tracks **which source files it has already processed** via a `.processed` manifest:

| Scenario | Action |
|----------|--------|
| Same file, same mtime | Skip — already processed |
| Same file, new mtime | Re-process — CC updated it |
| New file | Process |
| Haiku discards entry | Still marked processed — won't re-scan |

This means most sessions cost zero tokens — haiku is only called when CC has genuinely new material.

## Corpus

Stored at `~/.claude/me-agent/corpus/` (private, outside the repo):

```
~/.claude/me-agent/corpus/
  ME.md                      ← top-level index (always loaded first)
  interaction-style/          ← how you talk to Claude Code
  rules/                     ← corrections you enforce everywhere
  patterns/                  ← workflow habits, tool preferences
  projects/                  ← high-level view of what you're building
```

Each subfolder has its own `ME.md` index + topic files. Topic files use the same format as Claude Code memories:

```yaml
---
name: Never commit without verification
description: Always ask user to verify changes work before committing
---

Never commit code without first asking the user to verify the change works.

**Why:** Committing untested changes wastes time if they need to be reverted.

**How to apply:** After making a change, ask to verify before committing.
```

## Configuration

Edit `config.json`:

| Setting | Default | Description |
|---------|---------|-------------|
| `consolidation_interval_hours` | `24` | Hours between consolidation runs |
| `extraction_model` | `haiku` | Model for extraction calls |
| `consolidation_model` | `haiku` | Model for consolidation calls |
| `project_freshness_days` | `14` | Skip projects with no activity in N days |
| `excluded_projects` | `[]` | Project slugs to ignore |
| `debug` | `false` | Verbose logging to stderr |

## Uninstall

```bash
bash uninstall.sh          # remove hook + symlink, keep data at ~/.claude/me-agent/
bash uninstall.sh --purge  # also delete ~/.claude/me-agent/ (corpus + logs)
```

## Design Principles

- **Claude Code native** — same markdown + frontmatter format, same progressive disclosure, haiku uses tools directly (like CC's dreaming agent)
- **Project-agnostic** — only patterns that generalize across projects
- **Token efficient** — piggyback on CC's extraction, source tracking before LLM, haiku only when new material exists
- **Transparent** — plain markdown files you can read, edit, and version control
- **Safe** — corpus at `~/.claude/me-agent/`, separate from skills and repo. Deleting skills or the repo doesn't touch your data.

## License

MIT
