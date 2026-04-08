import type { Plugin, PluginModule } from "@opencode-ai/plugin"
import { readFileSync, existsSync } from "fs"
import { join } from "path"
import { log } from "./lib/pai-log"

const server: Plugin = async ({ directory }) => {
  const contextDir = join(process.env.HOME || "", ".config/opencode/pai/context")

  return {
    event: async ({ event }) => {
      if (event.type === "session.created") {
        const contexts: string[] = []

        const userProfile = join(contextDir, "user/profile.md")
        if (existsSync(userProfile)) {
          contexts.push(`[User Profile loaded: ${userProfile}]`)
        }

        const daIdentity = join(contextDir, "da/identity.md")
        if (existsSync(daIdentity)) {
          contexts.push(`[DA Identity loaded: ${daIdentity}]`)
        }

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

export default { server } satisfies PluginModule
