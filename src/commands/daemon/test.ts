import {Command} from '@oclif/core'
import {execFileSync} from 'node:child_process'
import {join} from 'node:path'
import {SCRIPTS_DIR} from '../../paths.js'

export default class DaemonTest extends Command {
  static description = 'Fire one daily notification right now (skips the scheduler)'

  static examples = [
    '<%= config.bin %> daemon test',
  ]

  async run(): Promise<void> {
    execFileSync('bash', [join(SCRIPTS_DIR, 'notify-daily.sh')], {
      stdio: 'inherit',
      env: {...process.env},
    })
    this.log('Test notification dispatched.')
  }
}
