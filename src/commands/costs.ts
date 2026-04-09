import {Command, Flags} from '@oclif/core'
import {runScript} from '../run-script.js'

export default class Costs extends Command {
  static description = 'Show accumulated Haiku API costs (total, daily, monthly)'

  static examples = [
    '<%= config.bin %> costs',
    '<%= config.bin %> costs --reset',
  ]

  static flags = {
    reset: Flags.boolean({
      description: 'Clear cost history',
      default: false,
    }),
  }

  async run(): Promise<void> {
    const {flags} = await this.parse(Costs)

    if (flags.reset) {
      runScript('costs.sh', ['--reset'])
    } else {
      runScript('costs.sh')
    }
  }
}
