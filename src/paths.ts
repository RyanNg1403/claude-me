import {homedir} from 'node:os'
import {join, dirname} from 'node:path'
import {fileURLToPath} from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))

/** Root of the claude-me repo (parent of src/) */
export const PROJECT_ROOT = join(__dirname, '..')

/** Scripts directory */
export const SCRIPTS_DIR = join(PROJECT_ROOT, 'scripts')

/** Claude home directory */
export const CLAUDE_HOME = process.env.CLAUDE_HOME ?? join(homedir(), '.claude')

/** Data directory for user-specific data */
export const DATA_DIR = join(CLAUDE_HOME, 'claude-me')

/** Corpus directory */
export const CORPUS_DIR = join(DATA_DIR, 'corpus')

/** Notes directory */
export const NOTES_DIR = join(DATA_DIR, 'notes')

/** Pending interview questions */
export const QUESTIONS_FILE = join(DATA_DIR, 'pending-questions.json')

/** Costs CSV file */
export const COSTS_FILE = join(DATA_DIR, 'costs.csv')

/** Log file */
export const LOG_FILE = join(DATA_DIR, 'logs', 'claude-me.log')
