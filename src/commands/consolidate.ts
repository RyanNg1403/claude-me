import {Args, Command} from '@oclif/core'
import {runScript} from '../run-script.js'

export default class Consolidate extends Command {
  static args = {
    focus: Args.string({
      description: 'Focus area for consolidation (e.g., "merge all PR-related entries")',
      required: false,
    }),
  }

  static description = 'Merge duplicates, resolve contradictions, and prune the corpus'

  static examples = [
    '<%= config.bin %> consolidate',
    '<%= config.bin %> consolidate "merge all PR-related entries"',
    '<%= config.bin %> consolidate "prune stale entries older than 30 days"',
  ]

  async run(): Promise<void> {
    const {args} = await this.parse(Consolidate)
    const scriptArgs = ['--force']

    if (args.focus) {
      this.log(`Consolidating with focus: ${args.focus}`)
      scriptArgs.push('--focus', args.focus)
    } else {
      this.log('Consolidating corpus...')
    }

    runScript('consolidate.sh', scriptArgs)
  }
}
