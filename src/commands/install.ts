import {Command} from '@oclif/core'
import {runScript} from '../run-script.js'
import {PROJECT_ROOT} from '../paths.js'

export default class Install extends Command {
  static description = 'Install claude-me: symlink skill, create data directory, register SessionEnd hook'

  static examples = [
    '<%= config.bin %> install',
  ]

  async run(): Promise<void> {
    this.log(`Installing from: ${PROJECT_ROOT}`)
    runScript('../install.sh')
  }
}
