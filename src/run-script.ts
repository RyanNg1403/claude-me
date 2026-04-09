import {execFileSync} from 'node:child_process'
import {join} from 'node:path'
import {SCRIPTS_DIR} from './paths.js'

/**
 * Run a bash script from the scripts/ directory, streaming output to stdout/stderr.
 * Uses execFileSync to avoid shell interpolation of arguments.
 */
export function runScript(scriptName: string, args: string[] = []): void {
  const scriptPath = join(SCRIPTS_DIR, scriptName)

  execFileSync('bash', [scriptPath, ...args], {
    stdio: 'inherit',
    cwd: SCRIPTS_DIR,
    env: {...process.env},
  })
}
