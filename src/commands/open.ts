import {Command} from '@oclif/core'
import {execFileSync} from 'node:child_process'
import {CORPUS_DIR} from '../paths.js'

export default class Open extends Command {
  static description = 'Open the corpus directory in VS Code'

  static examples = [
    '<%= config.bin %> open',
  ]

  async run(): Promise<void> {
    // Prefer the `code` shell shim (respects the user's PATH, handles
    // existing-window reuse, works cross-platform if we ever extend).
    // Fall back to `open -a "Visual Studio Code"` which only needs the .app
    // to be installed.
    try {
      execFileSync('code', [CORPUS_DIR], {stdio: 'inherit', env: {...process.env}})
    } catch {
      try {
        execFileSync('open', ['-a', 'Visual Studio Code', CORPUS_DIR], {
          stdio: 'inherit',
          env: {...process.env},
        })
      } catch {
        this.error(
          'Could not open VS Code. Install it from https://code.visualstudio.com/ or ' +
            'add the `code` command to your PATH via Command Palette → ' +
            '"Shell Command: Install \'code\' command in PATH".',
        )
      }
    }
    this.log(`Opened ${CORPUS_DIR}`)
  }
}
