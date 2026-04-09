import {Command} from '@oclif/core'
import {runScript} from '../run-script.js'

export default class Consolidate extends Command {
  static description = 'Merge duplicates, resolve contradictions, and prune the corpus (like Claude Code /dream)'

  static examples = [
    '<%= config.bin %> consolidate',
  ]

  async run(): Promise<void> {
    this.log('Consolidating corpus...')
    runScript('consolidate.sh', ['--force'])
  }
}
