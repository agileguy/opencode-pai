# PAI → OpenCode: Software Requirements Document

**Version:** 1.1.0
**Date:** 2026-04-05
**Author:** Serena Blackwood (Architect Agent)
**Status:** DRAFT — Architecture Reviewed, Dockerized

---

## 1. Executive Summary

This SRD defines the architecture for porting PAI (Personal AI Infrastructure) from Claude Code to OpenCode. PAI is a 16-principle personal AI system with 7 major subsystems: Algorithm, Skills, Hooks, Agents, Memory, Notifications, and Delegation. OpenCode is an open-source, model-agnostic terminal AI coding agent with analogous but differently-shaped systems.

**The strategic case for porting:**
- **Model freedom** — PAI on Claude Code is locked to Anthropic models. OpenCode supports 75+ providers including local models via oMLX, enabling fully offline operation.
- **Cost control** — Multi-model routing lets PAI assign cheap models (Gemini Flash, Haiku) to simple tasks and expensive models (Opus, Sonnet) to complex work.
- **Persistence** — OpenCode's daemon architecture provides persistent sessions that survive terminal disconnects.
- **Open source** — No vendor lock-in. MIT-licensed. Fork-ready.

**The honest constraints:**
- OpenCode's plugin API is maturing but has edge cases (session resume, idle hooks).
- No guaranteed 1M context window — model-dependent, varies from 4K to 128K+ for local models.
- OpenCode's agent system is less sophisticated than Claude Code's (no native multi-agent collaboration yet).

---

## 2. Component Mapping: PAI → OpenCode

### 2.1 High-Level Mapping

| PAI Component | Claude Code Mechanism | OpenCode Equivalent | Mapping Confidence |
|---|---|---|---|
| **CLAUDE.md** (project rules) | Native system prompt injection | **AGENTS.md** | Direct — identical purpose |
| **settings.json** (hooks, config) | Native hooks config | **opencode.json** (plugins) | High — different API, same concept |
| **Skills (SKILL.md)** | Skill tool + progressive loading | **Skills (SKILL.md)** | **Exact** — same open standard |
| **Hooks (*.hook.ts)** | Claude Code hook events | **Plugins (*.ts)** | High — different event names |
| **Agents (*.md)** | Task tool subagent_types | **Agents (.opencode/agents/*.md)** | High — similar frontmatter |
| **Memory system** | Custom directory + hooks | **Custom plugin + data dir** | Medium — needs design |
| **Algorithm v3.7.0** | CLAUDE.md + skill loading | **AGENTS.md rules + skill** | Medium — creative adaptation |
| **Delegation (TaskTool)** | Task() with subagent_type | **TaskTool** | Direct — same concept |
| **Context routing** | File reads triggered by prompts | **instructions[] in config** | Medium — less dynamic |
| **ComposeAgent** | CLI tool + trait system | **No direct equivalent** | Low — needs plugin |
| **PRD system** | Algorithm writes files | **Plugin + agent rules** | Medium — needs design |

### 2.2 Skills: Direct Port (Same Standard)

PAI's skill system and OpenCode's skill system use the **same open standard** (agentskills.io). This is the highest-confidence mapping.

**PAI skill structure:**
```
~/.claude/skills/SkillName/
├── SKILL.md
├── Tools/
│   └── ToolName.ts
└── Workflows/
    └── WorkflowName.md
```

**OpenCode skill structure:**
```
.opencode/skills/skill-name/
├── SKILL.md
├── scripts/
│   └── tool-name.ts
└── references/
    └── workflow-name.md
```

**Migration steps:**
1. Copy skill directories
2. Rename to kebab-case (PAI uses TitleCase, OpenCode uses kebab-case)
3. Update frontmatter `name` field to kebab-case
4. Move `Tools/` → `scripts/`, `Workflows/` → `references/`
5. Update internal file references
6. Replace Claude-specific API calls (Skill tool → skill tool)

**Skills that port directly (no logic changes):**
- Research, Blogging, Media, Security, Investigation, ContentAnalysis, Thinking
- All skills that are pure markdown workflows with no Claude-specific tool calls

**Skills requiring adaptation:**
- Skills that invoke `Skill("OtherSkill")` — OpenCode's skill tool uses the same pattern
- Skills that use Claude Code's `Task()` with `subagent_type` — map to OpenCode's TaskTool
- Skills that reference `~/.claude/` paths — update to `~/.config/opencode/` or `.opencode/`

### 2.3 Hooks → Plugins

PAI's hook system maps to OpenCode's plugin system with event name translation.

| PAI Hook Event | OpenCode Plugin Event | Notes |
|---|---|---|
| `SessionStart` | `session.created` | Plugin context issues on resume (known bug) |
| `SessionEnd` (Stop) | `session.deleted` | |
| `PreToolUse` | `tool.execute.before` | Input/output mutation pattern |
| `PostToolUse` | `tool.execute.after` | Read-only access to results |
| `UserPromptSubmit` | `chat.message` | Different API surface |
| N/A | `permission.ask` | New capability — permission interception |
| N/A | `chat.params` | New capability — model param modification |

**PAI hooks to port (priority order):**

| Hook | Purpose | OpenCode Plugin Design |
|---|---|---|
| `LoadContext.hook.ts` | Inject dynamic context at session start | `session.created` event handler |
| `PRDSync.hook.ts` | Sync PRD frontmatter to work.json | `tool.execute.after` on write/edit of PRD.md |
| `RatingCapture.hook.ts` | Capture user satisfaction ratings | `chat.message` handler detecting rating patterns |
| `SessionAutoName.hook.ts` | Auto-generate session names | `session.created` + `message.updated` |
| `TabTitle.hook.ts` | Dynamic terminal tab titles | `event` handler for status changes |

**Plugin template (TypeScript):**

```typescript
import type { Plugin } from "@opencode-ai/plugin"

export const PAIContextLoader: Plugin = async ({ project, $, directory }) => {
  return {
    event: async ({ event }) => {
      if (event.type === "session.created") {
        // Load PAI context equivalent to LoadContext.hook.ts
        // Read dynamic context files, inject as system message
      }
    },
    "tool.execute.before": async (input, output) => {
    },
    "tool.execute.after": async (input, output) => {
      // PRD sync: when PRD.md is written/edited, sync state
      if (input.tool === "write" || input.tool === "edit") {
        // Check if file is a PRD, extract frontmatter, sync to state
      }
    },
  }
}
```

### 2.4 Agents: Nearly Direct Port

PAI's agent definitions (`.claude/agents/*.md`) map closely to OpenCode's (`.opencode/agents/*.md`).

**PAI frontmatter:**
```yaml
---
name: Architect
description: System design specialist
model: opus
color: purple
persona:
  name: "Serena Blackwood"
  title: "The Academic Visionary"
permissions:
  allow: ["Bash", "Read(*)", "Write(*)", "Edit(*)"]
---
```

**OpenCode frontmatter:**
```yaml
---
description: System design, architecture decisions, and implementation planning
mode: primary
model: anthropic/claude-opus-4-5-20251101
temperature: 0.2
tools:
  write: true
  edit: true
  bash: true
permission:
  bash:
    "*": ask
    "git *": allow
---
```

**Key differences:**
- OpenCode uses `mode: primary | subagent | all` instead of implicit role
- OpenCode uses `tools: { name: bool }` instead of `permissions.allow[]`
- OpenCode uses `model: provider/model-id` (full qualified) vs PAI's shorthand
- OpenCode has no native persona fields — these go in the markdown body
- OpenCode has `temperature`, `maxSteps`, `isolation` fields PAI lacks

**Agent roster for OpenCode port:**

| Agent | Mode | Model | Key Capability |
|---|---|---|---|
| `pai-architect` | primary | configurable (Opus-tier) | System design, specs, no code |
| `pai-engineer` | primary | configurable (Opus-tier) | TDD, implementation, surgical fixes |
| `pai-designer` | subagent | configurable (Sonnet-tier) | UX/UI, accessibility, shadcn |
| `pai-qa` | subagent | configurable (Sonnet-tier) | Edge case testing, evidence-based |
| `pai-pentester` | subagent | configurable (Sonnet-tier) | Security assessment, OWASP |
| `pai-artist` | subagent | configurable (Sonnet-tier) | Image gen via OpenAI API |
| `pai-researcher` | subagent | configurable (Flash-tier) | Web search, synthesis |
| `pai-sre` | primary | configurable (Sonnet-tier) | Infra ops, destructive action gates |
| `pai-pm` | primary | configurable (Sonnet-tier) | Orchestration, phased implementation |

### 2.5 Memory System

PAI's memory system (`~/.claude/MEMORY/`) has no direct OpenCode equivalent. Design a custom solution:

**Proposed structure:**
```
~/.config/opencode/pai/
├── memory/
│   ├── work/                    # PRDs and work tracking
│   │   └── {timestamp}_{slug}/
│   │       └── PRD.md
│   ├── learning/                # Learnings and signals
│   │   ├── system/
│   │   ├── algorithm/
│   │   └── signals/
│   │       └── ratings.jsonl
│   ├── research/                # Research captures
│   │   └── YYYY-MM/
│   ├── state/                   # Runtime state
│   │   ├── current-work.json
│   │   └── events.jsonl
│   └── security/                # Security events
├── context/                     # Context routing files
│   ├── user/                    # User identity, goals, preferences
│   ├── da/                      # DA identity
│   └── projects/                # Project-specific context
└── history/                     # Session history and research
```

**Implementation:** A `pai-memory` plugin handles:
- Writing to `memory/work/` when PRDs are created/updated
- Appending to `memory/learning/signals/ratings.jsonl` on rating capture
- Updating `memory/state/current-work.json` on work transitions
- Rotating/archiving old entries

### 2.6 The Algorithm

PAI's Algorithm v3.7.0 is the most complex component to port. It's a 7-phase structured methodology (Observe → Think → Plan → Build → Execute → Verify → Learn) with ISC criteria, effort tiers, and PRD management.

**Porting strategy: Hybrid approach**

1. **AGENTS.md rules** — Encode the Algorithm's behavioral rules (surgical fixes, verify before assert, first principles, etc.) into AGENTS.md as always-loaded project context.

2. **Algorithm skill** — Create `.opencode/skills/pai-algorithm/SKILL.md` containing the full Algorithm methodology. When activated, it guides the agent through the 7-phase process.

3. **Algorithm agent** — Create `pai-algorithm.md` agent definition that enforces Algorithm mode when invoked:
   ```yaml
   ---
   description: PAI Algorithm executor — structured 7-phase methodology
   mode: primary
   temperature: 0.1
   ---
   ```

4. **PRD plugin** — A plugin that watches for PRD.md writes and syncs frontmatter state.

**What's lost:** The Algorithm's phase transition announcements don't have a direct equivalent in OpenCode. The PRD sync is achievable but requires custom plugin code.

### 2.7 Configuration (opencode.json)

**Global config (`~/.config/opencode/opencode.json`):**

```jsonc
{
  "$schema": "https://opencode.ai/config.json",

  // Default model (local via oMLX)
  "model": "omlx/gemma-4-26b-a4b-it-4bit",
  "small_model": "omlx/gemma-4-26b-a4b-it-4bit",

  // Providers
  "provider": {
    "omlx": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "oMLX (local MLX)",
      "options": {
        "baseURL": "http://host.docker.internal:8000/v1",
        "apiKey": "{env:OMLX_API_KEY}"
      },
      "models": {
        "gemma-4-26b-a4b-it-4bit": {
          "name": "Gemma 4 26B A4B (MLX)",
          "limit": { "context": 131072, "output": 8192 }
        },
        "gemma-4-31b-it-4bit": {
          "name": "Gemma 4 31B (MLX)",
          "limit": { "context": 131072, "output": 8192 }
        }
      }
    },
    "anthropic": {
      "api_key": "{env:ANTHROPIC_API_KEY}"
    },
    "google": {
      "api_key": "{env:GEMINI_API_KEY}"
    }
  },

  // Agent model routing
  "agent": {
    "build": { "model": "omlx/gemma-4-26b-a4b-it-4bit" },
    "plan": { "model": "omlx/gemma-4-26b-a4b-it-4bit" },
    "pai-architect": { "model": "anthropic/claude-opus-4-5", "mode": "primary" },
    "pai-engineer": { "model": "omlx/gemma-4-31b-it-4bit", "mode": "primary" },
    "pai-researcher": { "model": "google/gemini-2.5-flash", "mode": "subagent" },
    "pai-qa": { "model": "omlx/gemma-4-26b-a4b-it-4bit", "mode": "subagent" }
  },

  // Permissions
  "permission": {
    "read": "allow",
    "glob": "allow",
    "grep": "allow",
    "list": "allow",
    "bash": {
      "*": "ask",
      "git status*": "allow",
      "git diff*": "allow",
      "git log*": "allow",
      "git branch*": "allow",
      "rm -rf*": "deny"
    },
    "edit": {
      "*.env": "deny",
      "*.env.*": "deny",
      "*": "ask"
    }
  },

  // Context loading
  "instructions": [
    "AGENTS.md",
    ".opencode/context/steering-rules.md"
  ],

  // MCP servers
  "mcp": {},

  // Session management
  "compaction": { "auto": true, "prune": true },
  "watcher": {
    "ignore": ["**/node_modules/**", "**/dist/**", "**/.git/**"]
  }
}
```

---

## 3. Gap Analysis

### 3.1 Features With No OpenCode Equivalent

| PAI Feature | Impact | Mitigation |
|---|---|---|
| **ComposeAgent (trait composition)** | Medium | Build as custom plugin with trait YAML + template system |
| **Sentiment analysis hooks** | Low | Plugin with regex/keyword detection on messages |
| **Session harvesting** | Medium | Plugin that processes session transcripts on `session.deleted` |
| **Dynamic context injection (<system-reminder>)** | High | No equivalent — use instructions[] for static, skill for dynamic |
| **1M context window guarantee** | High | Model-dependent — design for 128K max, degrade gracefully |

### 3.2 Features That Work Better in OpenCode

| Feature | Why Better |
|---|---|
| **Multi-model routing** | Assign different providers per agent — impossible in Claude Code |
| **Persistent sessions** | Survive terminal disconnect, SSH drops, machine sleep |
| **Air-gapped operation** | Full local execution via oMLX — no network required |
| **Version-controlled agents** | `.opencode/agents/` travels with repo — every contributor gets same team |
| **Plugin tool override** | Plugin tools supersede built-ins — enables security layers |
| **Skill cross-compatibility** | Same SKILL.md standard works in Claude Code, Cursor, Codex |
| **Cost optimization** | Route cheap tasks to free local models, expensive to cloud |

### 3.3 Model-Agnostic Adaptation

PAI was designed for Claude's capabilities. Key adaptations:

| Claude Assumption | OpenCode Reality | Adaptation |
|---|---|---|
| 1M context window | 4K-128K depending on model | Design for 64K baseline, graceful degradation |
| Claude tool use format | Varies by provider | Use OpenAI-compatible format (universal) |
| Claude-specific prompting | Model-specific needs | Test prompts against target models |
| Anthropic billing | BYO API keys | Track token usage in plugin |

---

## 4. Architecture Decision Records

### ADR-1: Skills Use Same Open Standard (agentskills.io)
**Decision:** Port PAI skills with minimal modification, leveraging the shared SKILL.md standard.
**Rationale:** Both PAI and OpenCode implement the same agentskills.io spec. Renaming conventions (TitleCase → kebab-case) and directory restructuring (Tools/ → scripts/) is the only required work.
**Consequence:** Skills are cross-compatible — can run in both Claude Code and OpenCode simultaneously during migration.

### ADR-2: Algorithm Lives as Skill + AGENTS.md Rules
**Decision:** Split the Algorithm into behavioral rules (AGENTS.md) and procedural methodology (skill).
**Rationale:** AGENTS.md is always-loaded context (behavioral guardrails). The Algorithm's 7-phase procedure is activated on-demand via skill. This matches OpenCode's progressive disclosure model.
**Consequence:** The Algorithm's behavioral rules apply to ALL agents. The full procedural Algorithm only loads when explicitly needed.

### ADR-3: Memory System as Custom Plugin
**Decision:** Implement PAI's memory system as an OpenCode plugin writing to `~/.config/opencode/pai/memory/`.
**Rationale:** No built-in equivalent exists. A plugin can intercept session events, tool executions, and message patterns to capture learnings, ratings, and work state.
**Consequence:** Additional maintenance burden. The plugin must handle its own file I/O, rotation, and integrity.

### ADR-4: Multi-Model Default Configuration
**Decision:** Default to local oMLX models for cost optimization, with cloud providers as configured overrides.
**Rationale:** PAI's founding principle is "scaffolding > model." Running locally by default aligns with model independence. Cloud models available when quality demands it.
**Consequence:** Some PAI features (complex Architecture decisions, deep research) may need cloud model routing for quality.

### ADR-5: Agent Definitions Use OpenCode Native Format
**Decision:** Rewrite agent definitions in OpenCode's frontmatter format rather than maintaining Claude Code format.
**Rationale:** OpenCode's format adds `mode`, `temperature`, `maxSteps`, `isolation`, and `tools` fields that provide finer control.
**Consequence:** Agent files are not directly portable back to Claude Code.

---

## 5. Migration Strategy — Engineer-Executable Phases

Each phase is a sequence of concrete tasks an engineer can execute. Every task specifies the exact files to create/modify, the commands to run, and the test gate that must pass before proceeding.

---

### Phase 1: Docker + Infrastructure + Test Harness

**Goal:** Containerized OpenCode that connects to host oMLX with a passing test suite.
**Effort:** 2-3 days
**Branch:** `phase-1-foundation`

#### Task 1.1: Repository Scaffolding
```
Create these files:
  Dockerfile                          # From SRD Section 9.3
  docker-compose.yml                  # From SRD Section 9.4
  entrypoint.sh                       # Startup banner + env validation
  .env.example                        # Template: OMLX_API_KEY, GEMINI_API_KEY, OPENAI_API_KEY
  Makefile                            # build, up, down, shell, test, test-quick, test-e2e
  .gitignore                          # .env, node_modules, *.db
  README.md                           # Setup instructions
```

**Engineer instructions:**
1. Write `Dockerfile` — Ubuntu 24.04, install Node 22, Bun, uv, gh, delta, glow, ripgrep, fd, OpenCode
2. Write `docker-compose.yml` — bind mounts for config + repos + ssh + git, named volumes for opencode_data + bash_history, extra_hosts for host.docker.internal
3. Write `entrypoint.sh` — print tool versions, validate OMLX_API_KEY is set, exec "$@"
4. Write `Makefile` with targets: `build`, `up`, `down`, `shell`, `rebuild`, `test`, `test-quick`, `test-e2e`
5. `make build && make up` — verify container starts

#### Task 1.2: OpenCode Configuration
```
Create these files:
  config/opencode.json                # Global config (oMLX provider, permissions, model routing)
  config/AGENTS.md                    # PAI behavioral rules
```

**Engineer instructions:**
1. Write `config/opencode.json` with:
   - oMLX provider: `baseURL: http://host.docker.internal:8000/v1`, `apiKey: {env:OMLX_API_KEY}`
   - All 3 oMLX models: gemma-4-26b-a4b-it-4bit, gemma-4-31b-it-4bit, gpt-oss-20b-MXFP4-Q8
   - Default model: `omlx/gemma-4-26b-a4b-it-4bit`
   - Permissions: read=allow, glob=allow, grep=allow, bash=ask (git*=allow, rm*=deny), edit=ask (.env=deny)
   - Compaction: auto=true, prune=true
   - Watcher ignore: node_modules, dist, .git, vendor, coverage
   - Instructions: `["AGENTS.md"]`
2. Write `config/AGENTS.md` with PAI steering rules (surgical fixes, verify before assert, first principles, no attribution, TDD, identity)
3. `make down && make up` — verify opencode sees config: `docker exec ... opencode models omlx`

#### Task 1.3: Core Agent Definitions (3 agents)
```
Create these files:
  config/agents/pai-architect.md      # mode: primary, read-only, system design
  config/agents/pai-engineer.md       # mode: primary, full tools, TDD
  config/agents/pai-researcher.md     # mode: subagent, read + webfetch only
```

**Engineer instructions:**
1. Write each agent with OpenCode frontmatter: `description`, `mode`, `tools`, `permission`
2. Include persona and expertise in markdown body
3. Verify: `docker exec ... ls ~/.config/opencode/agents/` shows all 3

#### Task 1.4: Test Harness
```
Create these files:
  tests/connectivity.sh               # oMLX reachable, models listed, DNS
  tests/model-routing.sh              # Each model responds to completions
  tests/agent-defs.sh                 # Agent files present + frontmatter valid
  tests/tool-access.sh                # opencode, rg, git, bun, gh, workspace writable
  tests/e2e-smoke.sh                  # Real prompt round-trip via opencode run
  tests/README.md                     # Test documentation
```

**Engineer instructions:**
1. Write all test scripts from SRD Section 10.3
2. Add tmux and jq to Dockerfile (required by test harness)
3. Add Makefile targets: `test` (tmux), `test-quick` (sequential), `test-e2e` (with LLM)
4. Run `make test-quick` — all structural tests must pass
5. Run `make test-e2e` — model routing and e2e smoke must pass

#### Phase 1 Gate
```
make test-quick   → ALL PASS (connectivity, agent-defs, tool-access)
make test-e2e     → ALL PASS (model-routing, e2e-smoke)
opencode models omlx → lists 3 models
docker exec ... opencode run "Say PONG" → responds
```

**Rollback:** `make down && rm -rf config/ tests/ Dockerfile docker-compose.yml`

---

### Phase 2: Full Agent Roster + Skills

**Goal:** All 9 PAI agents, 10 priority skills, skill activation working.
**Effort:** 1 week
**Branch:** `phase-2-agents-skills`
**Depends on:** Phase 1 gate passed

#### Task 2.1: Remaining Agent Definitions (6 agents)
```
Create these files:
  config/agents/pai-designer.md       # mode: subagent, UI/UX focus
  config/agents/pai-qa.md             # mode: subagent, read-only + bash for tests
  config/agents/pai-pentester.md      # mode: subagent, security boundaries
  config/agents/pai-artist.md         # mode: subagent, bash for OpenAI image API
  config/agents/pai-sre.md            # mode: primary, confirm-required for destructive
  config/agents/pai-pm.md             # mode: primary, task delegation
```

**Engineer instructions:**
1. Write each agent fresh in OpenCode frontmatter format using the agent specifications from SRD Section 2.4 (mode, tools, permission fields)
2. Update `tests/agent-defs.sh` REQUIRED_AGENTS array to include all 9
3. Run `make test-quick` — agent-defs must pass for all 9

#### Task 2.2: Agent Team Configuration
```
Modify:
  config/opencode.json                # Add agent blocks with model routing
```

**Engineer instructions:**
1. Add `agent` section to opencode.json mapping each agent to model tier:
   - pai-architect → anthropic/claude-opus (or omlx/gemma-4-31b for local)
   - pai-engineer → omlx/gemma-4-31b-it-4bit
   - pai-researcher → google/gemini-2.5-flash (or omlx for offline)
   - pai-designer, pai-qa, pai-pentester, pai-sre, pai-pm → omlx/gemma-4-26b-a4b-it-4bit
   - pai-artist → omlx/gemma-4-26b-a4b-it-4bit (image gen via bash/OpenAI API)
2. Verify: `docker exec ... opencode run --agent pai-qa "What tools do you have?"` responds correctly

#### Task 2.3: Priority Skills (10 skills)
```
Create these directories + SKILL.md files:
  config/skills/research/SKILL.md
  config/skills/blogging/SKILL.md
  config/skills/media/SKILL.md
  config/skills/security/SKILL.md
  config/skills/thinking/SKILL.md
  config/skills/content-analysis/SKILL.md
  config/skills/investigation/SKILL.md
  config/skills/scraping/SKILL.md
  config/skills/rag/SKILL.md
  config/skills/utilities/SKILL.md
```

**Engineer instructions:**
1. For each skill: copy SKILL.md from `~/.claude/skills/SkillName/SKILL.md`
2. Rename to kebab-case, update frontmatter `name` field
3. Strip PAI-specific references (voice notifications, Claude-specific tool calls)
4. Replace `Skill("OtherSkill")` → `skill({ name: "other-skill" })`
5. Replace `~/.claude/` paths → `~/.config/opencode/pai/`
6. Add `tests/skill-loading.sh` and run — all 10 skills must have valid frontmatter
7. Run `make test-quick` — skill-loading must pass

#### Task 2.4: Skill Loading Test
```
Create:
  tests/skill-loading.sh              # From SRD Section 10.3 Category 5
```

**Engineer instructions:**
1. Write test script that validates each skill directory has SKILL.md with name + description
2. Run `make test-quick` — must pass

#### Phase 2 Gate
```
make test-quick   → ALL PASS (all 9 agents, 10 skills, tools, connectivity)
docker exec ... opencode run --agent pai-engineer "List your capabilities" → responds with TDD
docker exec ... opencode run --agent pai-artist "Describe an image" → responds with artistic context
```

**Rollback:** `git checkout phase-1-foundation -- config/agents/ config/opencode.json`

---

### Phase 3: Plugins + Memory + PRD System

**Goal:** Event-driven plugins for context loading, memory, ratings, PRD sync.
**Effort:** 1-2 weeks
**Branch:** `phase-3-plugins-memory`
**Depends on:** Phase 2 gate passed

#### Task 3.1: Plugin Infrastructure
```
Create these files:
  config/plugins/package.json         # Dependencies: @opencode-ai/plugin, zod
  config/plugins/tsconfig.json        # TypeScript config
```

**Engineer instructions:**
1. Write `package.json` with `@opencode-ai/plugin` as dependency
2. Add to Dockerfile: `RUN cd /home/developer/.config/opencode/plugins && bun install` (or handle in entrypoint.sh)
3. Rebuild: `make rebuild`
4. Verify node_modules exist: `docker exec ... ls ~/.config/opencode/plugins/node_modules/@opencode-ai`

#### Task 3.2: Context Loader Plugin
```
Create:
  config/plugins/pai-context-loader.ts
```

**Engineer instructions:**
1. Implement plugin that fires on `session.created` event
2. Read context files from `~/.config/opencode/pai/context/` and log their availability
3. Test: start opencode session, verify plugin loaded (check logs)

#### Task 3.3: Memory Plugin
```
Create:
  config/plugins/pai-memory.ts
  config/pai/memory/state/current-work.json     # Initial empty state
  config/pai/memory/learning/signals/ratings.jsonl  # Empty file
```

**Engineer instructions:**
1. Implement plugin with:
   - `tool.execute.after` handler: when write/edit targets a PRD.md, parse frontmatter, update `current-work.json`
   - `chat.message` handler: detect rating patterns (e.g., "8/10", "rate: 9"), append to `ratings.jsonl`
2. Test: create a test PRD.md via opencode, verify current-work.json updated

#### Task 3.4: Plugin Compilation Tests
```
Create:
  tests/plugin-hooks.sh               # From SRD Section 10.3 Category 6
```

**Engineer instructions:**
1. Write test that validates package.json, node_modules, and each .ts plugin compiles
2. Run `make test-quick` — plugin-hooks must pass

#### Phase 3 Gate
```
make test-quick   → ALL PASS (including plugin-hooks)
make test-e2e     → ALL PASS
Plugin loads without errors on session start (check opencode logs)
PRD write triggers state update in current-work.json
```

**Rollback:** Delete `config/plugins/*.ts`. Rebuild.

---

### Phase 4: Algorithm Skill + Remaining Skills

**Goal:** Full Algorithm methodology as a skill, remaining PAI skills ported.
**Effort:** 2-3 weeks
**Branch:** `phase-4-algorithm-parity`
**Depends on:** Phase 3 gate passed

#### Task 4.1: Algorithm Skill
```
Create:
  config/skills/pai-algorithm/SKILL.md          # 7-phase methodology
  config/skills/pai-algorithm/references/
    prd-format.md                               # PRD specification
    isc-decomposition.md                        # Criteria writing guide
    effort-tiers.md                             # Standard through Comprehensive
```

**Engineer instructions:**
1. Write SKILL.md with frontmatter: `name: pai-algorithm`, description including "USE WHEN complex task, multi-step, Algorithm, structured methodology"
2. Body contains the 7-phase procedure (Observe → Think → Plan → Build → Execute → Verify → Learn)
3. Reference files contain supporting detail (split for progressive disclosure)
4. Test: invoke skill from opencode session, verify it guides through phases

#### Task 4.2: Remaining Skills Port
```
Create skill directories for all remaining PAI skills:
  config/skills/{skill-name}/SKILL.md
```

**Engineer instructions:**
1. Inventory all skills in `~/.claude/skills/` (excluding personal `_ALLCAPS` skills)
2. Port each: copy SKILL.md, rename, update frontmatter, strip PAI-specific references
3. Update `tests/skill-loading.sh` to validate all ported skills
4. Run `make test-quick`

#### Task 4.3: Context Routing
```
Create:
  config/pai/context/user/profile.md            # User identity + preferences
  config/pai/context/da/identity.md             # DA personality
  config/pai/context/steering-rules.md          # Full behavioral rules
Modify:
  config/opencode.json                          # Add instructions[] paths
```

**Engineer instructions:**
1. Write context files with relevant PAI user/DA context (sanitized — no secrets)
2. Add to `instructions[]` in opencode.json
3. Verify: start session, confirm context loads in system prompt

#### Phase 4 Gate
```
make test-quick   → ALL PASS
make test-e2e     → ALL PASS
opencode run "Use the Algorithm to plan a simple CLI tool" → produces PRD with ISC criteria
All ported skills discoverable via opencode's skill catalog
```

**Rollback:** Revert to Phase 3 branch. Algorithm and extra skills are additive.

---

### Phase 5: OpenCode-Native Features

**Goal:** Capabilities that are impossible in Claude Code.
**Effort:** 2-4 weeks
**Branch:** `phase-5-native`
**Depends on:** Phase 4 gate passed

#### Task 5.1: ACP Integration
**Engineer instructions:**
1. Test `opencode acp` from inside container
2. Configure Zed/JetBrains on host to connect to container's ACP endpoint
3. Verify PAI agents accessible from IDE

#### Task 5.2: Multi-Model Cost Routing
**Engineer instructions:**
1. Add Google/Anthropic providers to opencode.json (if not already)
2. Configure agent model overrides for quality-sensitive vs routine work
3. Test: verify different agents hit different providers

#### Task 5.3: Persistent Session Workflows
**Engineer instructions:**
1. Test `opencode serve` in headless mode inside container
2. Submit prompts via REST API from host
3. Verify sessions survive container restart (named volume)

#### Task 5.4: PAI MCP Server
**Engineer instructions:**
1. Build MCP server plugin exposing PAI tools (memory query, skill catalog, context lookup)
2. Configure as MCP server in opencode.json
3. Test: external agent connects and uses PAI tools

#### Task 5.5: ComposeAgent Plugin
**Engineer instructions:**
1. Build plugin implementing trait-based agent composition
2. Accept trait list → generate agent prompt → spawn via TaskTool
3. Test: compose a custom agent with specific traits, verify behavior matches

#### Phase 5 Gate
```
ACP: PAI agent responds from Zed editor
Headless: opencode serve accepts REST prompt, returns response
MCP: External agent queries PAI memory
ComposeAgent: Custom trait-composed agent executes correctly
```

**Rollback:** Each feature is independent. Disable individually in config.

---

## 6. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| OpenCode plugin API changes break PAI plugins | High | Medium | Pin OpenCode version, test before upgrade |
| Local model quality insufficient for Algorithm | Medium | High | Configurable model routing — fall back to cloud |
| Context window too small for complex tasks | Medium | High | Aggressive compaction, skill-based context loading |
| Session resume bug loses PAI context | High | Medium | Persist critical state to filesystem, reload on resume |
| Skills load order causes wrong activation | Low | Medium | Explicit skill descriptions with USE WHEN triggers |
| Agent permission drift across models | Medium | Low | Centralized permission config in opencode.json |
| Community OpenCode breaking changes | High | Medium | Fork if necessary — MIT licensed |

---

## 7. Dependency Matrix

| Component | Depends On | Blocks |
|---|---|---|
| AGENTS.md | Nothing | Everything (load first) |
| opencode.json | oMLX running on port 8000 | All agents and plugins |
| Agent definitions | AGENTS.md, opencode.json | Agent-specific skills |
| PAI context plugin | opencode.json | Session context loading |
| Memory plugin | Agent definitions | PRD sync, ratings, learning |
| Algorithm skill | Agents, memory plugin, PRD sync | Full Algorithm execution |
| Skills (ported) | Agent definitions | Workflow automation |
| ACP integration | All above stable | IDE access |

---

## 8. Directory Structure (Complete)

```
Project Root/
├── .opencode/
│   ├── agents/                      # Agent definitions
│   │   ├── pai-architect.md
│   │   ├── pai-engineer.md
│   │   ├── pai-designer.md
│   │   ├── pai-qa.md
│   │   ├── pai-pentester.md
│   │   ├── pai-artist.md
│   │   ├── pai-researcher.md
│   │   ├── pai-sre.md
│   │   └── pai-pm.md
│   ├── plugins/                     # OpenCode plugins (PAI hooks)
│   │   ├── pai-context-loader.ts    # Session start context injection
│   │   ├── pai-memory.ts            # Memory system (ratings, PRD, learning)
│   │   ├── pai-tab-title.ts         # Terminal tab title updates
│   │   └── package.json             # Plugin dependencies
│   ├── skills/                      # Ported PAI skills
│   │   ├── pai-algorithm/
│   │   │   └── SKILL.md
│   │   ├── research/
│   │   │   ├── SKILL.md
│   │   │   └── references/
│   │   ├── blogging/
│   │   │   └── SKILL.md
│   │   └── ... (remaining skills)
│   └── context/                     # Static context files
│       ├── steering-rules.md        # AI behavioral rules
│       ├── user-profile.md          # User identity + preferences
│       └── da-identity.md           # DA personality
├── AGENTS.md                        # Project rules (PAI behavioral rules)
└── opencode.json                    # Project config overrides

Global (~/.config/opencode/):
├── opencode.json                    # Global config (providers, permissions)
├── AGENTS.md                        # Global rules
├── agents/                          # Global agents (available everywhere)
│   └── (same agents as above)
├── plugins/                         # Global plugins
│   └── (same plugins as above)
├── skills/                          # Global skills
│   └── (ported PAI skills)
└── pai/                             # PAI-specific data
    ├── memory/                      # Memory system
    │   ├── work/
    │   ├── learning/
    │   ├── research/
    │   ├── state/
    │   └── security/
    ├── context/                     # Full context routing
    │   ├── user/
    │   ├── da/
    │   └── projects/
    └── history/                     # Session captures
```

---

## 10. Automated Validation Suite

### 10.1 Design Philosophy

Every phase of the migration produces assertions that must be validated **before** declaring that phase complete. Manual "it looks like it works" is insufficient — PAI's founding principle is "never assert without verification."

The validation suite runs inside the Docker container using **tmux** to orchestrate parallel test sessions. Each test is a self-contained script that exercises one capability and exits with a pass/fail code.

### 10.2 Test Infrastructure

**tmux-based test harness:** A single `make test` command launches a tmux session inside the container, runs all validation scripts in parallel panes, collects results, and outputs a structured report.

```
┌─────────────────────────────────────────────────────────────┐
│  tmux session: pai-validation                                │
│                                                              │
│  ┌─────────────────┐ ┌─────────────────┐ ┌───────────────┐  │
│  │ Pane 0:         │ │ Pane 1:         │ │ Pane 2:       │  │
│  │ connectivity    │ │ model-routing   │ │ agent-defs    │  │
│  │ tests           │ │ tests           │ │ tests         │  │
│  └─────────────────┘ └─────────────────┘ └───────────────┘  │
│  ┌─────────────────┐ ┌─────────────────┐ ┌───────────────┐  │
│  │ Pane 3:         │ │ Pane 4:         │ │ Pane 5:       │  │
│  │ tool-access     │ │ skill-loading   │ │ plugin-hooks  │  │
│  │ tests           │ │ tests           │ │ tests         │  │
│  └─────────────────┘ └─────────────────┘ └───────────────┘  │
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ Pane 6: Test Aggregator — collects results, reports     │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 10.3 Test Categories

#### Category 1: Connectivity Tests
Validate the container can reach all host services.

```bash
#!/usr/bin/env bash
# tests/connectivity.sh — Run inside container
set -euo pipefail

PASS=0; FAIL=0; RESULTS=""

# Test 1: oMLX reachable
if curl -sf -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${OMLX_API_KEY}" \
    "http://host.docker.internal:8000/v1/models"; then
  PASS=$((PASS+1)); RESULTS+="PASS: oMLX API reachable\n"
else
  FAIL=$((FAIL+1)); RESULTS+="FAIL: oMLX API unreachable at host.docker.internal:8000\n"
fi

# Test 2: oMLX returns models
MODEL_COUNT=$(curl -sf \
    -H "Authorization: Bearer ${OMLX_API_KEY}" \
    "http://host.docker.internal:8000/v1/models" | jq '.data | length')
if [ "$MODEL_COUNT" -gt 0 ]; then
  PASS=$((PASS+1)); RESULTS+="PASS: oMLX serving ${MODEL_COUNT} models\n"
else
  FAIL=$((FAIL+1)); RESULTS+="FAIL: oMLX returned 0 models\n"
fi

# Test 3: LightRAG reachable (optional)
if curl -sf -o /dev/null "http://host.docker.internal:9621/health" 2>/dev/null; then
  PASS=$((PASS+1)); RESULTS+="PASS: LightRAG reachable\n"
else
  RESULTS+="SKIP: LightRAG not running (optional)\n"
fi

# Test 4: DNS resolution
if getent hosts host.docker.internal >/dev/null 2>&1; then
  PASS=$((PASS+1)); RESULTS+="PASS: host.docker.internal resolves\n"
else
  FAIL=$((FAIL+1)); RESULTS+="FAIL: host.docker.internal DNS resolution failed\n"
fi

printf "$RESULTS"
echo "---"
echo "CONNECTIVITY: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
```

#### Category 2: Model Routing Tests
Validate that configured models are accessible and respond to completions.

```bash
#!/usr/bin/env bash
# tests/model-routing.sh
set -euo pipefail

PASS=0; FAIL=0; RESULTS=""

MODELS=("gemma-4-26b-a4b-it-4bit" "gemma-4-31b-it-4bit" "gpt-oss-20b-MXFP4-Q8")

for MODEL in "${MODELS[@]}"; do
  # Test: model listed in /v1/models
  if curl -sf -H "Authorization: Bearer ${OMLX_API_KEY}" \
      "http://host.docker.internal:8000/v1/models" | jq -e ".data[] | select(.id == \"${MODEL}\")" > /dev/null 2>&1; then
    PASS=$((PASS+1)); RESULTS+="PASS: Model ${MODEL} listed\n"
  else
    FAIL=$((FAIL+1)); RESULTS+="FAIL: Model ${MODEL} not found in /v1/models\n"
    continue
  fi

  # Test: model responds to a completion request
  RESPONSE=$(curl -sf -X POST \
      -H "Authorization: Bearer ${OMLX_API_KEY}" \
      -H "Content-Type: application/json" \
      "http://host.docker.internal:8000/v1/chat/completions" \
      -d "{\"model\": \"${MODEL}\", \"messages\": [{\"role\": \"user\", \"content\": \"Reply with exactly: PING\"}], \"max_tokens\": 10}" 2>/dev/null || echo "ERROR")

  if echo "$RESPONSE" | jq -e '.choices[0].message.content' > /dev/null 2>&1; then
    PASS=$((PASS+1)); RESULTS+="PASS: Model ${MODEL} responds to completions\n"
  else
    FAIL=$((FAIL+1)); RESULTS+="FAIL: Model ${MODEL} completion failed\n"
  fi
done

printf "$RESULTS"
echo "---"
echo "MODEL-ROUTING: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
```

#### Category 3: Agent Definition Tests
Validate all PAI agent files are present and well-formed.

```bash
#!/usr/bin/env bash
# tests/agent-defs.sh
set -euo pipefail

PASS=0; FAIL=0; RESULTS=""
AGENT_DIR="${HOME}/.config/opencode/agents"

REQUIRED_AGENTS=(
  "pai-architect" "pai-engineer" "pai-designer"
  "pai-qa" "pai-pentester" "pai-artist"
  "pai-researcher" "pai-sre" "pai-pm"
)

for AGENT in "${REQUIRED_AGENTS[@]}"; do
  FILE="${AGENT_DIR}/${AGENT}.md"

  # Test: file exists
  if [ -f "$FILE" ]; then
    PASS=$((PASS+1)); RESULTS+="PASS: ${AGENT}.md exists\n"
  else
    FAIL=$((FAIL+1)); RESULTS+="FAIL: ${AGENT}.md missing\n"
    continue
  fi

  # Test: has YAML frontmatter with description
  if head -20 "$FILE" | grep -q "^description:"; then
    PASS=$((PASS+1)); RESULTS+="PASS: ${AGENT} has description field\n"
  else
    FAIL=$((FAIL+1)); RESULTS+="FAIL: ${AGENT} missing description in frontmatter\n"
  fi

  # Test: has mode field
  if head -20 "$FILE" | grep -q "^mode:"; then
    PASS=$((PASS+1)); RESULTS+="PASS: ${AGENT} has mode field\n"
  else
    FAIL=$((FAIL+1)); RESULTS+="FAIL: ${AGENT} missing mode in frontmatter\n"
  fi
done

printf "$RESULTS"
echo "---"
echo "AGENT-DEFS: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
```

#### Category 4: Tool Access Tests
Validate OpenCode's built-in tools are functional inside the container.

```bash
#!/usr/bin/env bash
# tests/tool-access.sh
set -euo pipefail

PASS=0; FAIL=0; RESULTS=""

# Test: opencode binary exists and runs
if opencode --version > /dev/null 2>&1; then
  VERSION=$(opencode --version 2>&1 | head -1)
  PASS=$((PASS+1)); RESULTS+="PASS: opencode installed (${VERSION})\n"
else
  FAIL=$((FAIL+1)); RESULTS+="FAIL: opencode binary not found or not executable\n"
fi

# Test: opencode sees configured providers
if opencode models omlx 2>&1 | grep -q "gemma"; then
  PASS=$((PASS+1)); RESULTS+="PASS: opencode sees omlx provider models\n"
else
  FAIL=$((FAIL+1)); RESULTS+="FAIL: opencode cannot list omlx models\n"
fi

# Test: ripgrep available (used by grep tool)
if rg --version > /dev/null 2>&1; then
  PASS=$((PASS+1)); RESULTS+="PASS: ripgrep available\n"
else
  FAIL=$((FAIL+1)); RESULTS+="FAIL: ripgrep not installed\n"
fi

# Test: git available and configured
if git --version > /dev/null 2>&1; then
  PASS=$((PASS+1)); RESULTS+="PASS: git available\n"
else
  FAIL=$((FAIL+1)); RESULTS+="FAIL: git not installed\n"
fi

# Test: bun available
if bun --version > /dev/null 2>&1; then
  PASS=$((PASS+1)); RESULTS+="PASS: bun available\n"
else
  FAIL=$((FAIL+1)); RESULTS+="FAIL: bun not installed\n"
fi

# Test: gh CLI available and authenticated
if gh auth status > /dev/null 2>&1; then
  PASS=$((PASS+1)); RESULTS+="PASS: gh CLI authenticated\n"
else
  FAIL=$((FAIL+1)); RESULTS+="FAIL: gh CLI not authenticated\n"
fi

# Test: workspace directory exists and is writable
if [ -d /workspace ] && touch /workspace/.write-test && rm /workspace/.write-test; then
  PASS=$((PASS+1)); RESULTS+="PASS: /workspace writable\n"
else
  FAIL=$((FAIL+1)); RESULTS+="FAIL: /workspace not writable\n"
fi

printf "$RESULTS"
echo "---"
echo "TOOL-ACCESS: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
```

#### Category 5: Skill Loading Tests
Validate PAI skills are discoverable by OpenCode.

```bash
#!/usr/bin/env bash
# tests/skill-loading.sh
set -euo pipefail

PASS=0; FAIL=0; RESULTS=""
SKILL_DIR="${HOME}/.config/opencode/skills"

# Test: skills directory exists
if [ -d "$SKILL_DIR" ]; then
  PASS=$((PASS+1)); RESULTS+="PASS: Skills directory exists\n"
else
  FAIL=$((FAIL+1)); RESULTS+="FAIL: Skills directory missing at ${SKILL_DIR}\n"
  printf "$RESULTS"; echo "SKILL-LOADING: ${PASS} passed, ${FAIL} failed"; exit 1
fi

# Test: each skill has a valid SKILL.md with frontmatter
for SKILL_PATH in "$SKILL_DIR"/*/SKILL.md; do
  [ -f "$SKILL_PATH" ] || continue
  SKILL_NAME=$(basename "$(dirname "$SKILL_PATH")")

  # Has name field
  if head -10 "$SKILL_PATH" | grep -q "^name:"; then
    PASS=$((PASS+1)); RESULTS+="PASS: ${SKILL_NAME} has name field\n"
  else
    FAIL=$((FAIL+1)); RESULTS+="FAIL: ${SKILL_NAME} missing name in frontmatter\n"
  fi

  # Has description field
  if head -10 "$SKILL_PATH" | grep -q "^description:"; then
    PASS=$((PASS+1)); RESULTS+="PASS: ${SKILL_NAME} has description field\n"
  else
    FAIL=$((FAIL+1)); RESULTS+="FAIL: ${SKILL_NAME} missing description in frontmatter\n"
  fi
done

SKILL_COUNT=$(find "$SKILL_DIR" -name "SKILL.md" | wc -l)
RESULTS+="INFO: ${SKILL_COUNT} skills discovered\n"

printf "$RESULTS"
echo "---"
echo "SKILL-LOADING: ${PASS} passed, ${FAIL} failed (${SKILL_COUNT} skills)"
[ "$FAIL" -eq 0 ]
```

#### Category 6: Plugin Hook Tests
Validate plugins load without errors.

```bash
#!/usr/bin/env bash
# tests/plugin-hooks.sh
set -euo pipefail

PASS=0; FAIL=0; RESULTS=""
PLUGIN_DIR="${HOME}/.config/opencode/plugins"

# Test: plugin directory exists
if [ -d "$PLUGIN_DIR" ]; then
  PASS=$((PASS+1)); RESULTS+="PASS: Plugin directory exists\n"
else
  FAIL=$((FAIL+1)); RESULTS+="FAIL: Plugin directory missing\n"
  printf "$RESULTS"; echo "PLUGIN-HOOKS: ${PASS} passed, ${FAIL} failed"; exit 1
fi

# Test: package.json exists
if [ -f "${PLUGIN_DIR}/package.json" ]; then
  PASS=$((PASS+1)); RESULTS+="PASS: package.json present\n"
else
  FAIL=$((FAIL+1)); RESULTS+="FAIL: package.json missing in plugins/\n"
fi

# Test: dependencies installed (node_modules exists)
if [ -d "${PLUGIN_DIR}/node_modules" ] || [ -d "${HOME}/.config/opencode/node_modules" ]; then
  PASS=$((PASS+1)); RESULTS+="PASS: Plugin dependencies installed\n"
else
  FAIL=$((FAIL+1)); RESULTS+="FAIL: Plugin dependencies not installed (run bun install)\n"
fi

# Test: each .ts plugin file is valid TypeScript (syntax check)
for PLUGIN in "$PLUGIN_DIR"/*.ts; do
  [ -f "$PLUGIN" ] || continue
  NAME=$(basename "$PLUGIN")
  if bun build --no-bundle "$PLUGIN" --outdir /tmp/pai-plugin-check > /dev/null 2>&1; then
    PASS=$((PASS+1)); RESULTS+="PASS: ${NAME} compiles\n"
  else
    FAIL=$((FAIL+1)); RESULTS+="FAIL: ${NAME} has TypeScript errors\n"
  fi
done

printf "$RESULTS"
echo "---"
echo "PLUGIN-HOOKS: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
```

#### Category 7: End-to-End Smoke Test
Send a real prompt through OpenCode and validate the response.

```bash
#!/usr/bin/env bash
# tests/e2e-smoke.sh
set -euo pipefail

PASS=0; FAIL=0; RESULTS=""

# Test: opencode run with a simple prompt returns output
E2E_OUTPUT=$(timeout 120 opencode run "Reply with exactly the word PONG and nothing else" 2>&1 || echo "TIMEOUT")

if echo "$E2E_OUTPUT" | grep -qi "PONG"; then
  PASS=$((PASS+1)); RESULTS+="PASS: e2e smoke test — model responded via opencode run\n"
elif echo "$E2E_OUTPUT" | grep -q "TIMEOUT"; then
  FAIL=$((FAIL+1)); RESULTS+="FAIL: e2e smoke test — timed out after 120s\n"
else
  FAIL=$((FAIL+1)); RESULTS+="FAIL: e2e smoke test — unexpected output: $(echo "$E2E_OUTPUT" | head -3)\n"
fi

# Test: opencode run with agent selection
AGENT_OUTPUT=$(timeout 120 opencode run --agent pai-researcher "What is 2+2? Reply with just the number." 2>&1 || echo "TIMEOUT")

if echo "$AGENT_OUTPUT" | grep -q "4"; then
  PASS=$((PASS+1)); RESULTS+="PASS: Agent routing — pai-researcher responded\n"
elif echo "$AGENT_OUTPUT" | grep -q "TIMEOUT"; then
  FAIL=$((FAIL+1)); RESULTS+="FAIL: Agent routing — timed out\n"
else
  FAIL=$((FAIL+1)); RESULTS+="FAIL: Agent routing — unexpected output\n"
fi

printf "$RESULTS"
echo "---"
echo "E2E-SMOKE: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
```

### 10.4 Test Runner (Makefile)

```makefile
# Makefile — test targets

.PHONY: test test-quick test-e2e test-inside

# Run all tests inside the container via tmux
test:
	docker exec -it opencode-pai-opencode-pai-1 bash -c '\
		tmux new-session -d -s pai-validation \; \
		split-window -h \; \
		split-window -v \; \
		select-pane -t 0 \; \
		split-window -v \; \
		select-pane -t 0 \; \
		send-keys "bash /workspace/tests/connectivity.sh 2>&1 | tee /tmp/test-connectivity.log" Enter \; \
		select-pane -t 1 \; \
		send-keys "bash /workspace/tests/model-routing.sh 2>&1 | tee /tmp/test-model-routing.log" Enter \; \
		select-pane -t 2 \; \
		send-keys "bash /workspace/tests/agent-defs.sh 2>&1 | tee /tmp/test-agent-defs.log" Enter \; \
		select-pane -t 3 \; \
		send-keys "bash /workspace/tests/tool-access.sh 2>&1 | tee /tmp/test-tool-access.log" Enter \; \
		attach'

# Quick validation (no e2e, no tmux — sequential in single shell)
test-quick:
	docker exec opencode-pai-opencode-pai-1 bash -c '\
		echo "=== Connectivity ===" && bash /workspace/tests/connectivity.sh && \
		echo "=== Agent Defs ===" && bash /workspace/tests/agent-defs.sh && \
		echo "=== Tool Access ===" && bash /workspace/tests/tool-access.sh && \
		echo "=== Skill Loading ===" && bash /workspace/tests/skill-loading.sh && \
		echo "=== Plugin Hooks ===" && bash /workspace/tests/plugin-hooks.sh && \
		echo "" && echo "ALL QUICK TESTS PASSED"'

# Full e2e (slow — sends real prompts through LLM)
test-e2e:
	docker exec opencode-pai-opencode-pai-1 bash -c '\
		echo "=== Model Routing ===" && bash /workspace/tests/model-routing.sh && \
		echo "=== E2E Smoke ===" && bash /workspace/tests/e2e-smoke.sh && \
		echo "" && echo "ALL E2E TESTS PASSED"'

# Run tests from inside the container (if already attached)
test-inside:
	@echo "Run: make test-quick   (fast, no LLM calls)"
	@echo "Run: make test-e2e     (slow, sends prompts to models)"
	@echo "Run: make test         (tmux parallel view)"
```

### 10.5 Validation Per Migration Phase

Each phase has a **gate** — a subset of tests that must pass before proceeding.

| Phase | Gate Tests | Pass Criteria |
|---|---|---|
| **Phase 1: Foundation** | connectivity, tool-access, agent-defs (3 agents only) | All pass, oMLX responds, opencode runs |
| **Phase 2: Core** | All Phase 1 + agent-defs (all 9), skill-loading, plugin-hooks | All agents present, skills discoverable, plugins compile |
| **Phase 3: Parity** | All Phase 2 + e2e-smoke, model-routing | End-to-end prompt succeeds, all models respond |
| **Phase 4: Native** | All Phase 3 + ACP connectivity, MCP tool exposure | IDE connection works, external agents access PAI tools |

### 10.6 CI Integration

The test suite is designed for both local and CI execution:

```yaml
# .github/workflows/validate.yml
name: PAI-OpenCode Validation
on: [push, pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build container
        run: docker compose build
      - name: Start container
        run: docker compose up -d
      - name: Run quick tests (no LLM — CI has no oMLX)
        run: |
          docker exec opencode-pai-opencode-pai-1 bash -c '
            bash /workspace/tests/agent-defs.sh &&
            bash /workspace/tests/tool-access.sh &&
            bash /workspace/tests/skill-loading.sh &&
            bash /workspace/tests/plugin-hooks.sh'
      - name: Teardown
        if: always()
        run: docker compose down
```

Note: CI runs only structural tests (agent defs, tool access, skill loading, plugin compilation). Model routing and e2e tests require a live oMLX server and run locally only.

### 10.7 Test Directory Structure

```
tests/
├── connectivity.sh        # Host service reachability
├── model-routing.sh       # oMLX model listing + completion
├── agent-defs.sh          # Agent file presence + frontmatter
├── tool-access.sh         # OpenCode + system tools availability
├── skill-loading.sh       # Skill discovery + frontmatter validation
├── plugin-hooks.sh        # Plugin compilation + dependency check
├── e2e-smoke.sh           # Real LLM prompt round-trip
└── README.md              # Test documentation
```

---

## Appendix A: AGENTS.md Template

```markdown
# PAI on OpenCode

## Core Principles
- Surgical fixes only — never add or remove components as a fix
- Never assert without verification — evidence required
- First principles over bolt-ons — understand → simplify → reduce → add
- Ask before destructive actions — deletes, force pushes, production deploys
- Read before modifying — understand existing code first
- One change when debugging — isolate, verify, proceed
- Minimal scope — only change what was asked

## Identity
- First person ("I"), user by name ("Dan")
- No Claude/AI attribution in commits or PRs — constitutional requirement

## Development Stack
- TypeScript > Python, bun > npm, uv > pip
- CLI interfaces for all tools
- TDD: write tests first

## Agent Team
This project uses PAI agents. Invoke by name:
- @pai-architect — system design and planning
- @pai-engineer — implementation and TDD
- @pai-researcher — deep research and analysis
- @pai-qa — testing and validation
- @pai-artist — image generation (OpenAI API)
- @pai-sre — infrastructure operations
```

---

## 9. Dockerization Architecture

### 9.1 Design Principles

PAI-OpenCode runs as a Docker container that reaches the **host's oMLX server** for local model inference. The container communicates with host services via `host.docker.internal`.

**Key architectural decisions:**
- OpenCode (Go binary) runs inside the container
- oMLX runs on the **host** (macOS, Metal GPU access) — the container cannot access Apple Silicon GPU
- The container reaches oMLX via `host.docker.internal:8000`
- Sessions persist via a named Docker volume
- PAI config (agents, skills, plugins) is bind-mounted from the repo
- Git identity and SSH keys are bind-mounted read-only from the host

### 9.2 Container Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Docker Container (Linux/arm64)                              │
│                                                              │
│  OpenCode (Go binary)                                        │
│    ├── Agents (.opencode/agents/pai-*.md)   ← bind mount     │
│    ├── Plugins (.opencode/plugins/*.ts)     ← bind mount     │
│    ├── Skills (.opencode/skills/*)          ← bind mount     │
│    ├── AGENTS.md                            ← bind mount     │
│    └── opencode.json                        ← bind mount     │
│                                                              │
│  Sessions: ~/.local/share/opencode/         ← named volume   │
│  Tools: Node.js, Bun, uv, gh, git, ripgrep                  │
│                                                              │
│  ┌──── host.docker.internal ────┐                            │
│  │  :8000 → oMLX (LLM + embed) │                            │
│  │  :9621 → LightRAG            │                            │
│  └──────────────────────────────┘                            │
└─────────────────────────────────────────────────────────────┘
```

### 9.3 Dockerfile Specification

```dockerfile
FROM ubuntu:24.04
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# OS packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl wget jq ripgrep fd-find fzf tree htop tmux \
    openssh-client ca-certificates build-essential zip unzip sudo bat \
  && rm -rf /var/lib/apt/lists/* \
  && ln -sf "$(which fdfind)" /usr/local/bin/fd \
  && ln -sf "$(which batcat)" /usr/local/bin/bat

# git-delta, glow, GitHub CLI
RUN ARCH=$(dpkg --print-architecture) \
  && DELTA_VERSION=0.18.2 \
  && if [ "$ARCH" = "arm64" ]; then DA=aarch64; GA=arm64; else DA=x86_64; GA=x86_64; fi \
  && curl -fsSL "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-${DA}-unknown-linux-gnu.tar.gz" \
    | tar xz --strip-components=1 -C /usr/local/bin \
  && curl -fsSL "https://github.com/charmbracelet/glow/releases/download/v2.0.0/glow_2.0.0_Linux_${GA}.tar.gz" \
    | tar xz --strip-components=1 -C /usr/local/bin \
  && GH_VERSION=2.74.0 \
  && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${GA}.tar.gz" \
    | tar xz --strip-components=1 -C /usr/local

# Node.js 22.x + Bun + uv
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

ARG BUN_VERSION=1.2.5
ENV BUN_INSTALL=/usr/local/bun
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}" \
  && ln -sf /usr/local/bun/bin/bun /usr/local/bin/bun \
  && ln -sf /usr/local/bun/bin/bunx /usr/local/bin/bunx

ENV UV_INSTALL_DIR=/usr/local/bin
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# OpenCode (Go binary)
RUN curl -fsSL https://opencode.ai/install | bash

# User setup
RUN usermod -l developer -d /home/developer -m ubuntu \
  && groupmod -n developer ubuntu \
  && echo "developer ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/developer \
  && chmod 0440 /etc/sudoers.d/developer

USER developer
RUN uv python install 3.12
ENV PATH="/home/developer/.local/bin:/home/developer/.opencode/bin:/usr/local/bun/bin:${PATH}"

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
WORKDIR /workspace
ENTRYPOINT ["entrypoint.sh"]
CMD ["bash"]
```

### 9.4 docker-compose.yml Specification

```yaml
services:
  opencode-pai:
    build: .
    env_file: .env
    volumes:
      # Source code
      - ./workspace:/workspace
      - ~/repos:/workspace/repos
      # PAI config (agents, skills, plugins, AGENTS.md)
      - ./config:/home/developer/.config/opencode
      # OpenCode session persistence
      - opencode_data:/home/developer/.local/share/opencode
      # Git identity (read-only)
      - ~/.ssh:/home/developer/.ssh:ro
      - ~/.gitconfig:/home/developer/.gitconfig:ro
      - ~/.config/gh:/home/developer/.config/gh:ro
      # Shell history
      - bash_history:/home/developer/.bash_history
    working_dir: /workspace
    stdin_open: true
    tty: true
    environment:
      - OMLX_API_KEY=qwerty12345!
      - OMLX_BASE_URL=http://host.docker.internal:8000/v1
    extra_hosts:
      - "host.docker.internal:host-gateway"

volumes:
  opencode_data:
  bash_history:
```

### 9.5 Config Directory Layout (bind-mounted)

```
config/                              # → ~/.config/opencode/ inside container
├── opencode.json                    # Global config (oMLX via host.docker.internal)
├── AGENTS.md                        # Global PAI rules
├── agents/                          # PAI agent definitions
│   ├── pai-architect.md
│   ├── pai-engineer.md
│   ├── pai-designer.md
│   ├── pai-qa.md
│   ├── pai-pentester.md
│   ├── pai-artist.md
│   ├── pai-researcher.md
│   ├── pai-sre.md
│   └── pai-pm.md
├── plugins/                         # PAI plugins
│   ├── pai-context-loader.ts
│   ├── pai-memory.ts
│   ├── │   └── package.json
├── skills/                          # Ported PAI skills
│   ├── pai-algorithm/
│   │   └── SKILL.md
│   └── research/
│       └── SKILL.md
└── pai/                             # PAI data (memory, state)
    ├── memory/
    ├── context/
    └── history/
```

### 9.6 Critical: oMLX Connection from Container

The opencode.json inside the container MUST use `host.docker.internal` instead of `127.0.0.1`:

```jsonc
{
  "provider": {
    "omlx": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://host.docker.internal:8000/v1",
        "apiKey": "{env:OMLX_API_KEY}"
      }
    }
  }
}
```

### 9.7 Host Services Dependency

The container assumes these services run on the host:

| Service | Host Port | Purpose | Required? |
|---------|-----------|---------|-----------|
| oMLX | 8000 | LLM inference + embeddings | Yes |
| LightRAG | 9621 | Knowledge base queries | No (optional) |

---

## Appendix B: Glossary

| Term | Definition |
|---|---|
| **PAI** | Personal AI Infrastructure — the system being ported |
| **OpenCode** | Open-source AI coding agent (sst/opencode, opencode.ai) |
| **ISC** | Ideal State Criteria — verifiable success criteria in the Algorithm |
| **PRD** | Product Requirements Document — single source of truth per task |
| **AGENTS.md** | Project rules file injected into agent system prompts |
| **SKILL.md** | On-demand procedural expertise loaded by agent decision |
| **MCP** | Model Context Protocol — connects agents to tools/data |
| **ACP** | Agent Client Protocol — connects agents to editors |
| **oMLX** | Local MLX inference server for Apple Silicon |
| **TaskTool** | Agent delegation mechanism (spawns subagent sessions) |
