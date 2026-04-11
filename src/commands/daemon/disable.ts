import {Command} from '@oclif/core'
import {execFileSync} from 'node:child_process'
import {join} from 'node:path'
import {SCRIPTS_DIR} from '../../paths.js'

export default class DaemonDisable extends Command {
  static description = 'Unregister the daily notification daemon (LaunchAgent)'

  static examples = [
    '<%= config.bin %> daemon disable',
  ]

  async run(): Promise<void> {
    execFileSync('bash', [join(SCRIPTS_DIR, 'daemon-disable.sh')], {
      stdio: 'inherit',
      env: {...process.env},
    })
  }
}
