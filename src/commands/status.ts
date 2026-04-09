import {Command} from '@oclif/core'
import {readdirSync, readFileSync, statSync, existsSync} from 'node:fs'
import {join} from 'node:path'
import {CORPUS_DIR, DATA_DIR, COSTS_FILE, LOG_FILE, QUESTIONS_FILE} from '../paths.js'

export default class Status extends Command {
  static description = 'Show corpus stats and system status'

  static examples = [
    '<%= config.bin %> status',
  ]

  async run(): Promise<void> {
    this.log('=' .repeat(50))
    this.log('  claude-me Status')
    this.log('='.repeat(50))

    // Corpus stats
    const categories = ['interaction-style', 'rules', 'patterns', 'projects']
    let totalEntries = 0

    this.log('\n  Corpus:')
    for (const cat of categories) {
      const catDir = join(CORPUS_DIR, cat)
      let count = 0
      if (existsSync(catDir)) {
        const files = readdirSync(catDir).filter(f => f.endsWith('.md') && f !== 'ME.md')
        count = files.length
      }
      totalEntries += count
      this.log(`    ${cat.padEnd(22)} ${String(count).padStart(3)} entries`)
    }
    this.log(`    ${'total'.padEnd(22)} ${String(totalEntries).padStart(3)} entries`)

    // Processed sources
    const processedFile = join(DATA_DIR, '.processed')
    let processedCount = 0
    if (existsSync(processedFile)) {
      processedCount = readFileSync(processedFile, 'utf-8').trim().split('\n').filter(Boolean).length
    }
    this.log(`\n  Processed source files: ${processedCount}`)

    // Last extraction
    if (existsSync(LOG_FILE)) {
      const log = readFileSync(LOG_FILE, 'utf-8')
      const extractionLines = log.split('\n').filter(l => l.includes('Extraction complete'))
      if (extractionLines.length > 0) {
        const last = extractionLines[extractionLines.length - 1]
        const ts = last.match(/\[(.*?)\]/)?.[1] ?? 'unknown'
        this.log(`  Last extraction:       ${ts}`)
      }
    }

    // Last consolidation
    const lockFile = join(CORPUS_DIR, '.consolidate-lock')
    if (existsSync(lockFile)) {
      const mtime = statSync(lockFile).mtime
      this.log(`  Last consolidation:    ${mtime.toISOString().replace('T', ' ').slice(0, 19)}`)
    } else {
      this.log('  Last consolidation:    never')
    }

    // Costs summary
    if (existsSync(COSTS_FILE)) {
      const lines = readFileSync(COSTS_FILE, 'utf-8').trim().split('\n')
      if (lines.length > 1) {
        let totalCost = 0
        for (const line of lines.slice(1)) {
          const cost = Number.parseFloat(line.split(',').pop() ?? '0')
          totalCost += cost
        }
        this.log(`  Total API cost:        $${totalCost.toFixed(4)}`)
      }
    }

    // Pending interview questions
    if (existsSync(QUESTIONS_FILE)) {
      try {
        const questions = JSON.parse(readFileSync(QUESTIONS_FILE, 'utf-8'))
        if (Array.isArray(questions) && questions.length > 0) {
          this.log(`\n  ⚠ ${questions.length} interview question(s) pending — run 'clm interview'`)
        }
      } catch { /* ignore parse errors */ }
    }

    this.log('\n' + '='.repeat(50))
  }
}
