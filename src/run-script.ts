import {execSync} from 'node:child_process'
import {join} from 'node:path'
import {SCRIPTS_DIR} from './paths.js'

/**
 * Run a bash script from the scripts/ directory, streaming output to stdout/stderr.
 */
export function runScript(scriptName: string, args: string[] = []): void {
  const scriptPath = join(SCRIPTS_DIR, scriptName)
  const cmd = ['bash', scriptPath, ...args].join(' ')

  execSync(cmd, {
    stdio: 'inherit',
    cwd: SCRIPTS_DIR,
    env: {...process.env},
  })
}
