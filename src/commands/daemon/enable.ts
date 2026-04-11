import {Command} from '@oclif/core'
import {execFileSync} from 'node:child_process'
import {join} from 'node:path'
import {SCRIPTS_DIR} from '../../paths.js'

export default class DaemonEnable extends Command {
  static description = 'Register the daily notification daemon (LaunchAgent) and fire a test notification'

  static examples = [
    '<%= config.bin %> daemon enable',
  ]

  async run(): Promise<void> {
    execFileSync('bash', [join(SCRIPTS_DIR, 'daemon-enable.sh')], {
      stdio: 'inherit',
      env: {...process.env},
    })
  }
}
