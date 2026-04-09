import {Command, Flags} from '@oclif/core'
import {execSync, spawnSync} from 'node:child_process'
import {existsSync, readFileSync, writeFileSync, unlinkSync, mkdtempSync} from 'node:fs'
import {join, basename} from 'node:path'
import {tmpdir} from 'node:os'
import {QUESTIONS_FILE, SCRIPTS_DIR} from '../paths.js'

type Question = {
  id: string
  type: 'conflict' | 'ambiguous' | 'stale'
  question: string
  context: string
  entries: string[]
}

const ANSWER_MARKER = '> YOUR ANSWER:'

export default class Interview extends Command {
  static description = 'Answer pending interview questions to resolve corpus conflicts'

  static examples = [
    '<%= config.bin %> interview',
    '<%= config.bin %> interview --list',
    '<%= config.bin %> interview --clear pr-strategy-conflict',
    '<%= config.bin %> interview --clear-all',
  ]

  static flags = {
    clear: Flags.string({
      description: 'Clear a specific question by ID',
    }),
    'clear-all': Flags.boolean({
      description: 'Clear all pending questions',
      default: false,
    }),
    list: Flags.boolean({
      char: 'l',
      description: 'List pending questions without opening editor',
      default: false,
    }),
  }

  async run(): Promise<void> {
    const {flags} = await this.parse(Interview)

    if (!existsSync(QUESTIONS_FILE)) {
      this.log('No pending interview questions.')
      return
    }

    let questions: Question[]
    try {
      questions = JSON.parse(readFileSync(QUESTIONS_FILE, 'utf-8'))
    } catch {
      this.log('No pending interview questions.')
      return
    }

    if (questions.length === 0) {
      this.log('No pending interview questions.')
      unlinkSync(QUESTIONS_FILE)
      return
    }

    if (flags['clear-all']) {
      unlinkSync(QUESTIONS_FILE)
      this.log(`Cleared all ${questions.length} pending question(s).`)
      return
    }

    if (flags.clear) {
      const remaining = questions.filter(q => q.id !== flags.clear)
      if (remaining.length === questions.length) {
        this.log(`No question found with ID: ${flags.clear}`)
        this.log('Available IDs: ' + questions.map(q => q.id).join(', '))
        return
      }

      if (remaining.length > 0) {
        writeFileSync(QUESTIONS_FILE, JSON.stringify(remaining, null, 2))
      } else {
        unlinkSync(QUESTIONS_FILE)
      }

      this.log(`Cleared question: ${flags.clear} (${remaining.length} remaining)`)
      return
    }

    if (flags.list) {
      this.log(`${questions.length} pending question(s):\n`)
      for (const [i, q] of questions.entries()) {
        this.log(`  ${i + 1}. [${q.type}] ${q.question}`)
        this.log(`     Context: ${q.context}`)
        this.log(`     Entries: ${q.entries.join(', ')}`)
        this.log('')
      }

      return
    }

    // Generate markdown file for editing
    const tmpDir = mkdtempSync(join(tmpdir(), 'clm-interview-'))
    const mdFile = join(tmpDir, 'interview.md')

    const lines: string[] = [
      '# claude-me Interview',
      '',
      'Answer each question below. Write your answer after the "> YOUR ANSWER:" marker.',
      'Leave the marker empty to skip a question. Save and close when done.',
      '',
      '---',
      '',
    ]

    for (const [i, q] of questions.entries()) {
      lines.push(`## Question ${i + 1} (${q.type})`)
      lines.push('')
      lines.push(q.question)
      lines.push('')
      lines.push(`*Context:* ${q.context}`)
      lines.push('')
      lines.push(`*Related entries:* ${q.entries.join(', ')}`)
      lines.push('')
      lines.push(`${ANSWER_MARKER} `)
      lines.push('')
      lines.push('---')
      lines.push('')
    }

    writeFileSync(mdFile, lines.join('\n'))

    // Open in editor
    const editor = process.env.EDITOR || process.env.VISUAL || 'vi'
    const result = spawnSync(editor, [mdFile], {stdio: 'inherit'})

    if (result.status !== 0) {
      this.log('Editor exited with error. No answers processed.')
      return
    }

    // Parse answers
    const edited = readFileSync(mdFile, 'utf-8')
    const answers: {question: Question; answer: string}[] = []

    for (const [i, q] of questions.entries()) {
      const regex = new RegExp(`## Question ${i + 1}[\\s\\S]*?${ANSWER_MARKER.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*(.*)`, 'm')
      const match = edited.match(regex)
      const answer = match?.[1]?.trim()
      if (answer) {
        answers.push({question: q, answer})
      }
    }

    // Clean up
    unlinkSync(mdFile)

    if (answers.length === 0) {
      this.log('No answers provided. Questions remain pending.')
      return
    }

    this.log(`Processing ${answers.length} answer(s)...`)

    // Feed each answer as a note
    for (const {question, answer} of answers) {
      const noteText = `Re: ${question.question} — ${answer}`
      const writeCmd = `source "${join(SCRIPTS_DIR, 'utils.sh')}" && write_note "${noteText.replace(/"/g, '\\"')}"`
      execSync(writeCmd, {encoding: 'utf-8', env: {...process.env}})
    }

    // Remove answered questions, keep unanswered
    const answeredIds = new Set(answers.map(a => a.question.id))
    const remaining = questions.filter(q => !answeredIds.has(q.id))

    if (remaining.length > 0) {
      writeFileSync(QUESTIONS_FILE, JSON.stringify(remaining, null, 2))
      this.log(`${remaining.length} question(s) still pending.`)
    } else {
      unlinkSync(QUESTIONS_FILE)
      this.log('All questions answered.')
    }

    // Process the notes
    this.log('Running extraction...')
    const scriptPath = join(SCRIPTS_DIR, 'extract.sh')
    execSync(`bash "${scriptPath}" --notes-only`, {
      stdio: 'inherit',
      env: {...process.env},
    })
  }
}
