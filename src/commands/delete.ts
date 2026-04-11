import {Args, Command, Flags} from '@oclif/core'
import {execFileSync} from 'node:child_process'
import {existsSync, realpathSync} from 'node:fs'
import {createInterface} from 'node:readline/promises'
import {isAbsolute, join, relative} from 'node:path'
import {stdin as input, stdout as output} from 'node:process'
import {CORPUS_DIR, SCRIPTS_DIR} from '../paths.js'

export default class Delete extends Command {
  static description = 'Soft-delete a corpus entry (moves to trash, recoverable for 7 days)'

  static examples = [
    '<%= config.bin %> delete rules/never-commit-untested.md',
    '<%= config.bin %> delete rules/never-commit-untested.md --yes',
  ]

  static args = {
    entry: Args.string({
      description: 'Entry path — relative to corpus dir (e.g. rules/foo.md) or absolute',
      required: true,
    }),
  }

  static flags = {
    yes: Flags.boolean({
      char: 'y',
      description: 'Skip confirmation prompt',
      default: false,
    }),
  }

  async run(): Promise<void> {
    const {args, flags} = await this.parse(Delete)

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

    const relPath = relative(CORPUS_DIR, filePath)

    if (!flags.yes) {
      const rl = createInterface({input, output})
      const answer = await rl.question(
        `Soft-delete ${relPath}? It will be recoverable from trash for 7 days. [y/N] `,
      )
      rl.close()
      if (answer.trim().toLowerCase() !== 'y') {
        this.log('Cancelled.')
        return
      }
    }

    try {
      execFileSync('bash', [join(SCRIPTS_DIR, 'soft-delete.sh'), filePath], {
        stdio: 'inherit',
        env: {...process.env},
      })
    } catch {
      this.error('Failed to soft-delete entry')
    }

    // Refresh stats cache so the status line reflects the lower total
    try {
      execFileSync('bash', [join(SCRIPTS_DIR, 'refresh-stats.sh')], {
        stdio: 'ignore',
        env: {...process.env},
      })
    } catch {
      // Best-effort
    }

    this.log(`Soft-deleted: ${relPath}`)
    this.log('Recover via: mv ~/.claude/claude-me/trash/<trash-name> ~/.claude/claude-me/corpus/' + relPath)
  }
}
