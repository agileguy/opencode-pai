import type { Plugin, PluginModule } from "@opencode-ai/plugin"
import { log } from "./lib/pai-log"

const LOCAL_MODEL_PATTERNS = ["omlx/", "ollama/", "mlx-", "gguf", "local/"]

function isLocalModel(model: unknown): boolean {
  if (!model) return true
  const m = String(typeof model === "object" && model !== null && "id" in model ? (model as any).id : model).toLowerCase()
  return LOCAL_MODEL_PATTERNS.some(p => m.includes(p))
}

const TIER_ENFORCEMENT = `
## MANDATORY: Algorithm Tier Constraint

You are running on a LOCAL model with limited output capacity.

**You MUST use Standard tier ONLY.**
- Maximum 8 ISC criteria total
- OBSERVE phase: 5 sentences max, then immediately delegate
- No PRD tables in OBSERVE — just list tasks and delegate T1
- Skip THINK and PLAN phases — go straight from OBSERVE to delegation
- Each delegation: 1 deliverable, max 3 ISC

**If you selected Comprehensive, Deep, or Advanced tier: STOP. Switch to Standard NOW.**

This is not optional. Exceeding Standard tier will cause your output to truncate and the task to stall.
`

const server: Plugin = async (ctx) => {
  return {
    "experimental.chat.system.transform": async (input, output) => {
      const local = isLocalModel(input.model)
      log("tier", `Model: ${String(input.model)} → ${local ? "LOCAL (Standard enforced)" : "API (full tiers)"}`)
      if (local) {
        output.system.push(TIER_ENFORCEMENT)
      }
    },
  }
}

export default { server } satisfies PluginModule
