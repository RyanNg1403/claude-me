import {Command, Flags} from '@oclif/core'
import {createInterface} from 'node:readline'
import {runScript} from '../run-script.js'

export default class Uninstall extends Command {
  static description = 'Uninstall claude-me: remove hook, symlink, CLAUDE.md hint, and data'

  static examples = [
    '<%= config.bin %> uninstall',
    '<%= config.bin %> uninstall --yes',
  ]

  static flags = {
    yes: Flags.boolean({
      char: 'y',
      description: 'Skip confirmation prompt',
      default: false,
    }),
  }

  async run(): Promise<void> {
    const {flags} = await this.parse(Uninstall)

    if (!flags.yes) {
      this.log('This will remove:')
      this.log('  - SessionEnd hook from settings.json')
      this.log('  - Skill symlink at ~/.claude/skills/claude-me/')
      this.log('  - CLAUDE.md hint (global and project-level)')
      this.log('  - Data directory at ~/.claude/claude-me/ (corpus, logs, notes)')
      this.log('')

      const confirmed = await this.confirm('Proceed? (y/N)')
      if (!confirmed) {
        this.log('Cancelled.')
        return
      }
    }

    runScript('../uninstall.sh', ['--yes'])
  }

  private confirm(message: string): Promise<boolean> {
    const rl = createInterface({input: process.stdin, output: process.stdout})
    return new Promise(resolve => {
      rl.question(`${message} `, answer => {
        rl.close()
        resolve(answer.toLowerCase() === 'y' || answer.toLowerCase() === 'yes')
      })
    })
  }
}
