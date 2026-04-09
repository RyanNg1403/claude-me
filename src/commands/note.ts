import {Args, Command, Flags} from '@oclif/core'
import {execSync, spawn} from 'node:child_process'
import {join} from 'node:path'
import {SCRIPTS_DIR} from '../paths.js'
import {runScript} from '../run-script.js'

export default class Note extends Command {
  static args = {
    text: Args.string({
      description: 'The preference or behavior to record',
      required: true,
    }),
  }

  static description = 'Add a preference note to be processed on next sync'

  static examples = [
    '<%= config.bin %> note "always run tests before committing"',
    '<%= config.bin %> note "I prefer concise responses" --now',
    '<%= config.bin %> note "no trailing summaries" --now --detach',
  ]

  static flags = {
    detach: Flags.boolean({
      description: 'Run extraction in background (use with --now)',
      default: false,
      dependsOn: ['now'],
    }),
    now: Flags.boolean({
      description: 'Process the note immediately',
      default: false,
    }),
  }

  async run(): Promise<void> {
    const {args, flags} = await this.parse(Note)

    // Pass note text via env var to avoid shell injection
    const writeCmd = `source "${join(SCRIPTS_DIR, 'utils.sh')}" && write_note "$CLM_NOTE_TEXT"`
    const notePath = execSync(writeCmd, {
      encoding: 'utf-8',
      env: {...process.env, CLM_NOTE_TEXT: args.text},
    }).trim()

    this.log(`Note saved: ${notePath}`)

    if (flags.now && flags.detach) {
      const scriptPath = join(SCRIPTS_DIR, 'extract.sh')
      const child = spawn('bash', [scriptPath, '--notes-only'], {
        detached: true,
        stdio: 'ignore',
      })
      child.unref()
      this.log('Processing in background.')
    } else if (flags.now) {
      this.log('Processing note...')
      runScript('extract.sh', ['--notes-only'])
    } else {
      this.log('Will be processed on next sync.')
    }
  }
}
