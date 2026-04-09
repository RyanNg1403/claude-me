import {Command, Flags} from '@oclif/core'
import {runScript} from '../run-script.js'

export default class Uninstall extends Command {
  static description = 'Uninstall claude-me: remove hook, symlink, and optionally purge data'

  static examples = [
    '<%= config.bin %> uninstall',
    '<%= config.bin %> uninstall --purge',
  ]

  static flags = {
    purge: Flags.boolean({
      description: 'Also delete corpus and logs at ~/.claude/claude-me/',
      default: false,
    }),
  }

  async run(): Promise<void> {
    const {flags} = await this.parse(Uninstall)
    const args = flags.purge ? ['--purge'] : []
    runScript('../uninstall.sh', args)
  }
}
