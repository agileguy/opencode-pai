import type { Plugin } from "@opencode-ai/plugin"
import { readFileSync, existsSync } from "fs"
import { join } from "path"
import { log } from "./pai-log"

export const PAIContextLoader: Plugin = async ({ directory }) => {
  const contextDir = join(process.env.HOME || "", ".config/opencode/pai/context")

  return {
    event: async ({ event }) => {
      if (event.type === "session.created") {
        const contexts: string[] = []

        // Load user profile if exists
        const userProfile = join(contextDir, "user/profile.md")
        if (existsSync(userProfile)) {
          contexts.push(`[User Profile loaded: ${userProfile}]`)
        }

        // Load DA identity if exists
        const daIdentity = join(contextDir, "da/identity.md")
        if (existsSync(daIdentity)) {
          contexts.push(`[DA Identity loaded: ${daIdentity}]`)
        }

        // Load steering rules if exists
        const steeringRules = join(contextDir, "steering-rules.md")
        if (existsSync(steeringRules)) {
          contexts.push(`[Steering Rules loaded: ${steeringRules}]`)
        }

        if (contexts.length > 0) {
          log("context", `Loaded: ${contexts.join(", ")}`)
        } else {
          log("context", "No context files found — running with defaults")
        }
      }
    },
  }
}
