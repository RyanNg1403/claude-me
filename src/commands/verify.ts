import {Args, Command} from '@oclif/core'
import {execFileSync} from 'node:child_process'
import {existsSync, realpathSync} from 'node:fs'
import {isAbsolute, join} from 'node:path'
import {CORPUS_DIR, SCRIPTS_DIR} from '../paths.js'

export default class Verify extends Command {
  static description = "Mark a corpus entry as verified — bumps last_verified to today and increments verify_count"

  static examples = [
    '<%= config.bin %> verify rules/never-commit-untested.md',
    '<%= config.bin %> verify /Users/you/.claude/claude-me/corpus/rules/never-commit-untested.md',
  ]

  static args = {
    entry: Args.string({
      description: 'Entry path — relative to corpus dir (e.g. rules/foo.md) or absolute',
      required: true,
    }),
  }

  async run(): Promise<void> {
    const {args} = await this.parse(Verify)

    const filePath = isAbsolute(args.entry) ? args.entry : join(CORPUS_DIR, args.entry)

    if (!existsSync(filePath)) {
      this.error(`Entry not found: ${filePath}`)
    }

    // Refuse to operate on files outside the corpus dir, even if they exist.
    // Resolves symlinks and ../ tricks before the prefix check.
    const resolved = realpathSync(filePath)
    const corpusReal = realpathSync(CORPUS_DIR)
    if (!resolved.startsWith(corpusReal + '/')) {
      this.error(`Not a corpus entry (must be under ${CORPUS_DIR}): ${filePath}`)
    }

    try {
      execFileSync('bash', [join(SCRIPTS_DIR, 'mark-verified.sh'), filePath], {
        stdio: 'inherit',
        env: {...process.env},
      })
    } catch {
      this.error('Failed to mark entry as verified')
    }

    // Refresh stats cache so the status line picks up any freshness change
    try {
      execFileSync('bash', [join(SCRIPTS_DIR, 'refresh-stats.sh')], {
        stdio: 'ignore',
        env: {...process.env},
      })
    } catch {
      // Best-effort
    }

    this.log(`Verified: ${filePath}`)
  }
}
