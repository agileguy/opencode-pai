# PAI Algorithm Orchestration Fixes: Software Requirements Document

**Version:** 1.0.0
**Date:** 2026-04-06
**Author:** Serena Blackwood (Architect Agent)
**Status:** DRAFT

---

## 1. Executive Summary

The PAI Algorithm and pai-boss orchestration system have been deployed to OpenCode and tested against a non-trivial task (building a CLI cribbage game). The delegation model works — the boss correctly decomposes tasks, selects agents, self-corrects when prompted, and produces well-structured delegation briefs. However, five systemic issues prevent the system from completing work end-to-end:

1. **No subagent completion feedback** — the boss cannot detect when a subagent finishes or stalls
2. **Algorithm overhead exceeds local model capacity** — Deep/Comprehensive tiers demand more structured output than small models can sustain
3. **Delegation granularity too coarse** — single delegations bundle too many concerns
4. **No progress verification mechanism** — the boss asserts "the agent is working" without evidence
5. **No circuit breakers** — stalled subagents run indefinitely with no timeout or iteration limit

These are architectural issues, not model selection issues. They exist regardless of which model runs the agents. This SRD defines the fixes.

---

## 2. Problem Analysis

### 2.1 No Subagent Completion Feedback

**Observed behavior:** pai-boss delegates to pai-architect via the Task tool. The architect's session produces partial output and stops. The boss tells the user "the subagent is working" twice, with no way to verify this claim.

**Root cause:** OpenCode's Task tool is fire-and-forget from the boss's perspective. When the subagent session completes (or stalls), no completion event propagates back to the calling session. The boss has no `check_status`, `poll_session`, or `await_result` primitive.

**Impact:** The delegation loop (delegate → receive → verify → update → next) breaks at step 2. The boss can never advance past the first delegation.

**Constraint:** We cannot modify OpenCode's core Task tool behavior. The fix must work within the existing tool and plugin surface.

### 2.2 Algorithm Overhead vs Model Capacity

**Observed behavior:** The architect subagent entered OBSERVE, generated a partial PRD with ISC criteria (including a garbled `hendis-5` instead of `ISC-5`), began THINK, and produced no further output.

**Root cause:** The Algorithm's Deep tier demands 40-80 ISC criteria, structured PRD output, and multi-phase ceremony. A model with an 8K output token limit spends most of its budget on scaffolding (phase headers, ISC format, PRD structure), leaving insufficient tokens for actual architectural content. The Algorithm doesn't scale down gracefully when output capacity is constrained.

**Impact:** Subagents produce ISC criteria and phase headers but never reach the actual deliverable. Form without substance.

**Constraint:** The Algorithm must remain the methodology. The fix is adaptive tier selection, not Algorithm removal.

### 2.3 Delegation Granularity Too Coarse

**Observed behavior:** T1 ("Phase 1: Architecture & Protocol Design") bundles four major deliverables into a single delegation: system architecture, data models, state machine, and protocol schema. This is equivalent to asking for a full technical design document in one pass.

**Root cause:** The boss decomposed by project phase (architecture → engine → server → client → testing) rather than by deliverable size. Each "phase" contains multiple independent work products that could be separate tasks.

**Impact:** The subagent receives an overwhelming brief and must sustain output across multiple complex domains in a single session. This exceeds what most models can deliver coherently.

### 2.4 No Progress Verification Mechanism

**Observed behavior:** The boss said "I will notify you as soon as the architect completes the analysis" but has no mechanism to detect completion. It violated the "never assert without verification" steering rule.

**Root cause:** The pai-boss agent prompt instructs it to "verify before moving on" but provides no concrete verification method. It says to check ISC criteria but doesn't specify *how* to check what a subagent produced.

**Impact:** The boss becomes a passive waiter instead of an active orchestrator. It cannot course-correct stalled work.

### 2.5 No Circuit Breakers

**Observed behavior:** The architect subagent stalled after 3,922 chars of output with no timeout or forced termination. In a prior OpenCode session (oh-my-opencode), a subagent ran 809 consecutive turns over 3.5 hours.

**Root cause:** Neither the boss prompt nor the OpenCode configuration enforces maximum turns, token budgets, or wall-clock timeouts for delegated sessions.

**Impact:** Stalled or looping subagents consume tokens indefinitely. No automatic recovery.

---

## 3. Architecture Decisions

### 3.1 File-Based Handoff Protocol

**Decision:** Subagents write their deliverables to workspace files. The boss checks for those files to detect completion.

**Why:** OpenCode has no session-to-session event bus accessible to agents. But all agents share the same filesystem. A file is a durable, inspectable completion signal. The boss can use `read` and `glob` tools to check if a deliverable exists.

**Pattern:**
```
1. Boss delegates: "Write your architecture spec to /workspace/crib/docs/architecture.md"
2. Boss waits, then checks: glob("/workspace/crib/docs/architecture.md")
3. If file exists → read it → verify against ISC → mark task done
4. If file missing → send follow-up or reassign
```

**Trade-off:** Adds a filesystem convention that all agents must follow. This is a feature, not a bug — it produces durable artifacts.

### 3.2 Adaptive Algorithm Tier Selection

**Decision:** The boss selects Algorithm tier based on model capability, not just task complexity. Local models (≤30B parameters) are capped at Standard tier. API-backed models use the full tier range.

**Why:** Deep/Comprehensive tiers require sustained structured output (40-80+ ISC criteria, multi-page PRDs) that exceeds small model output limits. Standard tier (8-16 ISC, <2 min) produces focused, completable work.

**Implementation:** Add tier guidance to the boss prompt and the AGENTS.md rules.

### 3.3 Task Decomposition by Deliverable, Not by Phase

**Decision:** The boss decomposes tasks into single-deliverable units. Each delegation produces exactly one artifact (one spec, one module, one test suite).

**Why:** Coarse tasks (design the full architecture) fail because they require sustained multi-domain reasoning. Fine tasks (define the Card and Deck data models) succeed because they're focused and completable in one pass.

**Sizing heuristic:** If a delegation brief has more than 3 ISC criteria, it's too big. Split it.

### 3.4 Active Progress Checking

**Decision:** The boss checks for deliverables after each delegation instead of passively waiting. If a deliverable is missing after the subagent returns, the boss diagnoses and acts (retry, split, or reassign).

**Implementation:** Add explicit checking instructions to the boss prompt with a concrete verification pattern.

### 3.5 Configurable Guardrails in Agent Definitions

**Decision:** Add `maxSteps` to each agent's configuration in `opencode.json`. Subagents get hard turn limits to prevent runaway execution.

**Why:** OpenCode supports `maxSteps` in agent configuration. This is the built-in circuit breaker that was not configured.

---

## 4. Component Changes

### 4.1 pai-boss.md — Agent Prompt Rewrite

**File:** `config/agents/pai-boss.md`

**Changes:**

#### 4.1.1 Add file-based handoff protocol

The boss must instruct every delegation to write output to a specific file path. After delegation, the boss checks for that file.

**New delegation format section:**
```markdown
### Handoff Protocol

Every delegation MUST specify an output file path. The subagent writes its deliverable there. You verify completion by reading that file.

Delegation template addition:
  ### Output
  Write your deliverable to: `/workspace/<project>/docs/<deliverable-name>.md`

After the subagent completes:
1. Check if the file exists: `glob("/workspace/<project>/docs/<deliverable-name>.md")`
2. If exists → read it → verify ISC criteria against the content
3. If missing → the task failed. Diagnose: was the brief unclear? Was the scope too large? Retry with a smaller scope or reassign.
```

#### 4.1.2 Add adaptive tier selection rule

**New section in boss prompt:**
```markdown
### Algorithm Tier Selection

Select tier based on BOTH task complexity AND the model running the subagent:

| Model Size | Max Tier | Max ISC per Task |
|------------|----------|------------------|
| Local (≤30B) | Standard | 8 |
| Local (30-70B) | Extended | 12 |
| API (Sonnet/GPT-4) | Advanced | 24 |
| API (Opus/GPT-5) | Deep+ | 40+ |

If you don't know the model size, default to Standard tier with max 8 ISC.
```

#### 4.1.3 Add decomposition sizing rule

**New section in boss prompt:**
```markdown
### Task Sizing Rule

Each delegation must produce exactly ONE deliverable. If a task has more than 3 ISC criteria, split it.

WRONG: "Design the full architecture" (4+ deliverables, 10+ ISC)
RIGHT:
  - T1a: "Define Card, Deck, Hand data models" (2-3 ISC)
  - T1b: "Design game state machine with phase transitions" (2-3 ISC)
  - T1c: "Define WebSocket message protocol schema" (2-3 ISC)
  - T1d: "Describe client/server interaction model" (2-3 ISC)

Smaller tasks complete. Larger tasks stall.
```

#### 4.1.4 Add active verification pattern

**Replace the passive "verify before moving on" with:**
```markdown
### After Every Delegation

When a subagent task completes, you MUST:

1. CHECK: Read the output file the subagent was told to produce
2. MEASURE: Count which ISC criteria the output satisfies
3. ACT:
   - All ISC met → mark task done, update tracker, delegate next task
   - Partial ISC met → send a follow-up delegation with the specific gaps
   - No output / file missing → split the task into smaller pieces and retry
   - Garbled output → the model couldn't handle the task. Simplify the brief.

Never say "the subagent is working" unless you have verified it produced output.
```

### 4.2 opencode.json — Add maxSteps Guards

**File:** `config/opencode.json`

Add `maxSteps` to each agent configuration to prevent runaway execution:

```json
{
  "agent": {
    "pai-boss": { "model": "...", "maxSteps": 50 },
    "pai-architect": { "model": "...", "maxSteps": 30 },
    "pai-engineer": { "model": "...", "maxSteps": 40 },
    "pai-designer": { "model": "...", "maxSteps": 30 },
    "pai-qa": { "model": "...", "maxSteps": 30 },
    "pai-pentester": { "model": "...", "maxSteps": 20 },
    "pai-artist": { "model": "...", "maxSteps": 20 },
    "pai-researcher": { "model": "...", "maxSteps": 25 },
    "pai-sre": { "model": "...", "maxSteps": 30 },
    "pai-pm": { "model": "...", "maxSteps": 30 }
  }
}
```

**Rationale for limits:**
- **Boss (50):** Needs room for multiple delegation cycles across a full project
- **Engineer (40):** TDD cycles (write test, implement, refactor) consume more turns
- **Architect/QA/PM/Designer/SRE (30):** Analysis and review tasks
- **Researcher (25):** Research converges or it doesn't — more turns won't help
- **Pentester/Artist (20):** Focused, bounded tasks

### 4.3 AGENTS.md — Add Orchestration Rules

**File:** `config/AGENTS.md`

Add a new section after the Agent Roster:

```markdown
## Orchestration Rules

### File-Based Handoff
All subagent deliverables must be written to files in the workspace. The calling agent verifies completion by reading the file. Verbal claims of completion ("I'm done") are not sufficient — the file must exist and contain the deliverable.

### Task Sizing
A single delegation should produce one artifact and satisfy 1-3 ISC criteria. If a brief requires more than 3 ISC, the task is too large — split it into independent sub-tasks.

### Algorithm Tier Caps
Local models (oMLX) use Standard tier only (8 ISC max). API-backed models may use higher tiers. When in doubt, default to Standard — a completed Standard task beats an incomplete Deep task.

### Circuit Breakers
All agents have maxSteps configured. If an agent hits its step limit, the work product at that point is the final output. The calling agent assesses what was produced and either accepts, retries with a smaller scope, or reassigns.
```

### 4.4 pai-algorithm Skill — Add Tier Cap Awareness

**File:** `config/skills/pai-algorithm/SKILL.md`

Add a note in the Effort Tiers section:

```markdown
### Model-Aware Tier Selection

The effort tier should respect the running model's output capacity:

| Model Class | Recommended Max Tier |
|-------------|---------------------|
| Small local (≤30B, 4-bit) | Standard (8-16 ISC) |
| Medium local (30-70B) | Extended (16-24 ISC) |
| API standard (Sonnet, GPT-4o) | Advanced (24-48 ISC) |
| API premium (Opus, GPT-5) | Deep or Comprehensive |

If the current model cannot sustain the selected tier's output requirements, automatically downgrade to the next lower tier. A completed Standard-tier task is worth more than a stalled Deep-tier task.
```

---

## 5. Phased Implementation

### Phase 1: Guardrails (Quick Win)
**Agent:** pai-engineer
**Scope:**
- Add `maxSteps` to all agents in `opencode.json`
- Add orchestration rules section to `AGENTS.md`
- Add model-aware tier note to `pai-algorithm/SKILL.md`

**ISC:**
- [ ] ISC-1: All 10 agents in opencode.json have maxSteps configured
- [ ] ISC-2: AGENTS.md contains orchestration rules section
- [ ] ISC-3: pai-algorithm SKILL.md contains tier cap guidance
- [ ] ISC-A-1: No existing agent configurations are broken by changes

**Estimated effort:** Standard tier, <15 minutes

### Phase 2: Boss Prompt Rewrite
**Agent:** pai-engineer
**Scope:**
- Rewrite pai-boss.md with file-based handoff protocol
- Add adaptive tier selection rules
- Add task sizing rules (max 3 ISC per delegation)
- Add active verification pattern
- Update delegation format template with output file requirement

**ISC:**
- [ ] ISC-4: pai-boss.md contains file-based handoff protocol section
- [ ] ISC-5: pai-boss.md contains adaptive tier selection table
- [ ] ISC-6: pai-boss.md contains task sizing rule (max 3 ISC)
- [ ] ISC-7: pai-boss.md contains active verification pattern (check/measure/act)
- [ ] ISC-8: Delegation format template includes output file path requirement
- [ ] ISC-A-2: Boss prompt does not exceed 4000 tokens (model context budget)

**Estimated effort:** Standard tier, <20 minutes

### Phase 3: Validation
**Agent:** pai-qa (validation), pai-boss (execution test)
**Scope:**
- Run pai-boss against the cribbage prompt again with the fixes applied
- Verify the boss:
  - Decomposes into single-deliverable tasks (not phase-sized chunks)
  - Specifies output file paths in every delegation
  - Checks for deliverables after subagent completion
  - Uses Standard tier for local model subagents
  - Hits maxSteps limits gracefully when applicable

**ISC:**
- [ ] ISC-9: Boss produces task list with ≤3 ISC per task
- [ ] ISC-10: Every delegation brief includes an output file path
- [ ] ISC-11: Boss reads deliverable file after subagent completes
- [ ] ISC-12: Subagent uses Standard tier (verified in session output)
- [ ] ISC-A-3: No subagent runs beyond its maxSteps limit

**Estimated effort:** Extended tier (requires running the full delegation loop)

---

## 6. Success Criteria (Full SRD)

The fix is complete when pai-boss can:

1. Delegate a task to a subagent with a specific output file path
2. Detect when the subagent has finished (by checking for the file)
3. Read the deliverable and verify it against ISC criteria
4. Advance to the next task or retry with a smaller scope
5. Complete a full delegation loop (delegate → check → verify → advance) without human intervention
6. Respect maxSteps limits on all agents
7. Use appropriate Algorithm tier for the running model

---

## 7. Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Subagent ignores file output instruction | Medium | High — breaks handoff | Reinforce in AGENTS.md rules + agent system prompts. All agents read AGENTS.md. |
| maxSteps too low for complex tasks | Medium | Medium — incomplete output | Start conservative, tune upward based on observed usage. Boss can split and retry. |
| Boss prompt exceeds context budget | Low | High — instructions truncated | Enforce 4000 token limit on boss prompt. Measure after rewrite. |
| File-based handoff creates stale artifacts | Low | Low — boss reads latest | Each task writes to a unique path. No overwrite conflicts. |
| Standard tier ISC too shallow for architecture tasks | Medium | Medium — specs lack depth | Compensate with multiple sequential Standard-tier tasks that build on each other. |

---

## 8. Out of Scope

- **Model selection** — This SRD does not address which models to use. The fixes work regardless of model.
- **OpenCode core modifications** — All changes are within the config/agents/skills layer. No forking OpenCode.
- **Agent Teams (Strategy C)** — The peer-to-peer messaging system is not required for these fixes. The file-based handoff protocol is simpler and works with existing tools.
- **Plugin development** — No custom TypeScript plugins are required. All changes are configuration and prompt engineering.
