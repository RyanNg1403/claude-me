import {Command} from '@oclif/core'
import {execFileSync} from 'node:child_process'
import {join} from 'node:path'
import {SCRIPTS_DIR} from '../../paths.js'

export default class DaemonStatus extends Command {
  static description = 'Show current daemon registration state and schedule'

  static examples = [
    '<%= config.bin %> daemon status',
  ]

  async run(): Promise<void> {
    execFileSync('bash', [join(SCRIPTS_DIR, 'daemon-status.sh')], {
      stdio: 'inherit',
      env: {...process.env},
    })
  }
}
