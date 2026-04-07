import type { Plugin } from "@opencode-ai/plugin"
import { log } from "./pai-log"

/**
 * PAI Tier Enforcer Plugin
 *
 * Forces Standard tier Algorithm usage for local models.
 * Local models (oMLX) cannot sustain Deep/Comprehensive tier output.
 */
export const PAITierEnforcer: Plugin = async (ctx) => {
  const LOCAL_MODEL_PATTERNS = ["omlx/", "ollama/", "mlx-", "gguf", "local/"]

  function isLocalModel(model: unknown): boolean {
    if (!model) return true // default to local if unknown
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

  return {
    // Inject tier constraint into system prompt for local models
    "experimental.chat.system.transform": async (input, output) => {
      const local = isLocalModel(input.model)
      log("tier", `Model: ${String(input.model)} → ${local ? "LOCAL (Standard enforced)" : "API (full tiers)"}`)
      if (local) {
        output.push({
          type: "text",
          text: TIER_ENFORCEMENT,
        })
      }
    },
  }
}
