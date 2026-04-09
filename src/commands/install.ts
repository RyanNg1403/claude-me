import {Command, Flags} from '@oclif/core'
import {runScript} from '../run-script.js'
import {PROJECT_ROOT} from '../paths.js'

export default class Install extends Command {
  static description = 'Install claude-me: symlink skill, create data directory, register SessionEnd hook'

  static examples = [
    '<%= config.bin %> install',
    '<%= config.bin %> install --local',
  ]

  static flags = {
    local: Flags.boolean({
      char: 'l',
      description: 'Add CLAUDE.md hint to ./CLAUDE.md (current project) instead of ~/.claude/CLAUDE.md',
      default: false,
    }),
  }

  async run(): Promise<void> {
    const {flags} = await this.parse(Install)
    this.log(`Installing from: ${PROJECT_ROOT}`)
    const args = ['--cwd', process.cwd()]
    if (flags.local) args.push('--project')
    runScript('../install.sh', args)
  }
}
