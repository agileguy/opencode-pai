import type { Plugin } from "@opencode-ai/plugin"
import { readFileSync, writeFileSync, appendFileSync, existsSync, mkdirSync } from "fs"
import { join, basename } from "path"

const PAI_DIR = join(process.env.HOME || "", ".config/opencode/pai")
const MEMORY_DIR = join(PAI_DIR, "memory")
const STATE_DIR = join(MEMORY_DIR, "state")
const SIGNALS_DIR = join(MEMORY_DIR, "learning/signals")

function ensureDir(dir: string) {
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true })
}

function parseYamlFrontmatter(content: string): Record<string, string> {
  const match = content.match(/^---\n([\s\S]*?)\n---/)
  if (!match) return {}
  const result: Record<string, string> = {}
  for (const line of match[1].split("\n")) {
    const [key, ...rest] = line.split(":")
    if (key && rest.length) {
      result[key.trim()] = rest.join(":").trim().replace(/^["']|["']$/g, "")
    }
  }
  return result
}

export const PAIMemory: Plugin = async ({ $ }) => {
  ensureDir(STATE_DIR)
  ensureDir(SIGNALS_DIR)

  return {
    // Track PRD writes — sync state when PRD.md is created or updated
    "tool.execute.after": async (input, output) => {
      if (input.tool !== "write" && input.tool !== "edit") return

      const args = (input as any).args || {}
      const filePath = args.file_path || args.path || ""

      if (!filePath.endsWith("PRD.md")) return

      try {
        const content = readFileSync(filePath, "utf-8")
        const frontmatter = parseYamlFrontmatter(content)

        if (frontmatter.task && frontmatter.slug) {
          const state = {
            task: frontmatter.task,
            slug: frontmatter.slug,
            phase: frontmatter.phase || "unknown",
            progress: frontmatter.progress || "0/0",
            effort: frontmatter.effort || "standard",
            updated: new Date().toISOString(),
            path: filePath,
          }

          writeFileSync(
            join(STATE_DIR, "current-work.json"),
            JSON.stringify(state, null, 2)
          )
          // Silent — synced to state file, no TUI output
        }
      } catch (e) {
        // Graceful fail — don't break the session
        // Silent fail — don't pollute TUI
      }
    },

    // Capture ratings from chat messages
    "chat.message": async (input, output) => {
      const message = (input as any).message?.content || ""
      if (typeof message !== "string") return

      // Detect rating patterns: "8/10", "rate: 9", "rating: 7"
      const ratingMatch = message.match(/(?:rate|rating)[:\s]*(\d{1,2})(?:\/10)?/i) ||
                          message.match(/(\d{1,2})\/10/)

      if (ratingMatch) {
        const rating = parseInt(ratingMatch[1], 10)
        if (rating >= 1 && rating <= 10) {
          const entry = {
            timestamp: new Date().toISOString(),
            rating,
            source: "chat",
          }
          appendFileSync(
            join(SIGNALS_DIR, "ratings.jsonl"),
            JSON.stringify(entry) + "\n"
          )
          // Silent — captured to signals file
        }
      }
    },
  }
}
