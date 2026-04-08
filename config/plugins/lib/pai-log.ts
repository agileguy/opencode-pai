import { appendFileSync, existsSync, mkdirSync } from "fs"
import { join } from "path"

const LOG_DIR = join(process.env.HOME || "", ".config/opencode/pai/logs")
const LOG_FILE = join(LOG_DIR, "pai.log")

if (!existsSync(LOG_DIR)) mkdirSync(LOG_DIR, { recursive: true })

export function log(source: string, message: string): void {
  const ts = new Date().toISOString()
  appendFileSync(LOG_FILE, `${ts} [${source}] ${message}\n`)
}

export function logError(source: string, message: string, error?: unknown): void {
  const ts = new Date().toISOString()
  const errStr = error instanceof Error ? error.message : String(error ?? "")
  appendFileSync(LOG_FILE, `${ts} [${source}] ERROR: ${message} ${errStr}\n`)
}
