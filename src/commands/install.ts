import {Command, Flags} from '@oclif/core'
import {runScript} from '../run-script.js'
import {PROJECT_ROOT} from '../paths.js'

export default class Install extends Command {
  static description = 'Install claude-me: symlink skill, create data directory, register SessionEnd hook'

  static examples = [
    '<%= config.bin %> install',
    '<%= config.bin %> install --global',
  ]

  static flags = {
    global: Flags.boolean({
      char: 'g',
      description: 'Add CLAUDE.md hint to ~/.claude/CLAUDE.md (all projects) instead of ./CLAUDE.md',
      default: false,
    }),
  }

  async run(): Promise<void> {
    const {flags} = await this.parse(Install)
    this.log(`Installing from: ${PROJECT_ROOT}`)
    const args = flags.global ? ['--global'] : []
    runScript('../install.sh', args)
  }
}
