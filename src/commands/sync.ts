import {Command, Flags} from '@oclif/core'
import {runScript} from '../run-script.js'

export default class Sync extends Command {
  static description = 'Extract cross-project preferences from Claude Code memory folders'

  static examples = [
    '<%= config.bin %> sync',
    '<%= config.bin %> sync --project /path/to/project',
  ]

  static flags = {
    project: Flags.string({
      char: 'p',
      description: 'Extract from a specific project directory',
    }),
  }

  async run(): Promise<void> {
    const {flags} = await this.parse(Sync)

    if (flags.project) {
      this.log(`Extracting from: ${flags.project}`)
      runScript('extract.sh', ['--project', flags.project])
    } else {
      this.log('Extracting from all active projects...')
      runScript('extract.sh', ['--all-active'])
    }
  }
}
