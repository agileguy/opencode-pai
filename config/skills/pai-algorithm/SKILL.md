---
name: pai-algorithm
description: PAI's structured 7-phase methodology for accomplishing any task. USE WHEN user says "use the Algorithm", "structured approach", "comprehensive task", or when the task clearly requires multi-step planning with verifiable criteria. Do NOT use for simple, quick tasks.
---

# The PAI Algorithm

A structured 7-phase methodology that transitions from **CURRENT STATE** to **IDEAL STATE** using verifiable criteria. The goal: produce excellent work through disciplined phases, not gut-feel hacking.

Every task has a current state (where we are) and an ideal state (where we need to be). The Algorithm bridges them with ISC (Ideal State Criteria) — atomic, binary-testable checkpoints that prove we arrived.

## Effort Tiers

Select a tier based on complexity, scope, and time pressure. Default to Standard unless the task clearly demands more.

| Tier | Budget | ISC Range | When to Use |
|------|--------|-----------|-------------|
| **Standard** | <2 min | 8-16 | Normal requests, single-file changes, quick fixes |
| **Extended** | <8 min | 16-32 | Must be extraordinary quality, multi-step tasks |
| **Advanced** | <16 min | 24-48 | Multi-file work, refactoring, new features |
| **Deep** | <32 min | 40-80 | Complex design, architecture, system integration |
| **Comprehensive** | <120 min | 64-150 | No time pressure, full builds, major systems |

See [effort-tiers.md](references/effort-tiers.md) for detailed guidance.

### Model-Aware Tier Selection

The effort tier should respect the running model's output capacity:

| Model Class | Recommended Max Tier |
|-------------|---------------------|
| Small local (≤30B, 4-bit) | Standard (8-16 ISC) |
| Medium local (30-70B) | Extended (16-24 ISC) |
| API standard (Sonnet, GPT-4o) | Advanced (24-48 ISC) |
| API premium (Opus, GPT-5) | Deep or Comprehensive |

If the current model cannot sustain the selected tier's output requirements, automatically downgrade to the next lower tier. A completed Standard-tier task is worth more than a stalled Deep-tier task.

## The 7 Phases

### Phase 1: OBSERVE

```
━━━ PHASE 1: OBSERVE ━━━ 1/7
```

Reverse engineer the request before doing anything. Answer four questions:

1. **Explicitly wanted** — What did the user directly ask for?
2. **Implicitly wanted** — What do they expect but didn't say? (quality, style, conventions)
3. **Explicitly NOT wanted** — What did they say to avoid?
4. **Obviously NOT wanted** — What would be clearly wrong? (breaking changes, data loss, scope creep)

Then:
- **Select effort tier** based on complexity assessment
- **Generate ISC criteria** — one per verifiable outcome (see [isc-decomposition.md](references/isc-decomposition.md))
- **Write PRD** — the living document that tracks progress (see [prd-format.md](references/prd-format.md))

Output the full PRD with all ISC criteria before proceeding.

### Phase 2: THINK

```
━━━ PHASE 2: THINK ━━━ 2/7
```

Deep analysis before committing to an approach.

- What approaches exist for this problem?
- What are the tradeoffs of each? (complexity, performance, maintainability, risk)
- What has been tried before in this codebase?
- What constraints exist? (dependencies, compatibility, conventions)
- Are there prior art or patterns to follow?

Research if needed. Read existing code. Understand before acting.

Output: A clear analysis with the recommended approach and why alternatives were rejected.

### Phase 3: PLAN

```
━━━ PHASE 3: PLAN ━━━ 3/7
```

Concrete implementation plan. No ambiguity.

- File-by-file changes (what files to create, modify, delete)
- Dependencies to install or update
- Order of operations (what must happen first)
- Risk areas and mitigation strategies
- Which ISC criteria each step addresses

**Present the plan to the user for approval before proceeding.** Do not build until the plan is accepted. If the user modifies the plan, update the PRD accordingly.

Output: Numbered step list with file paths and ISC criterion mappings.

### Phase 4: BUILD

```
━━━ PHASE 4: BUILD ━━━ 4/7
```

Execute the plan. Write code, create files, make changes.

Rules:
- **TDD first** — Write tests before implementation when applicable
- Follow the plan from Phase 3 (deviations require justification)
- One logical change at a time
- Read existing code before modifying it
- Minimal scope — only change what the plan specifies

Update the PRD with decisions made during implementation.

### Phase 5: EXECUTE

```
━━━ PHASE 5: EXECUTE ━━━ 5/7
```

Run the implementation. Make it real.

- Install dependencies
- Run builds and compilers
- Execute scripts
- Start services
- Run database migrations

As each step succeeds, check the corresponding ISC criteria. Mark them in the PRD.

Output: Execution log with pass/fail status for each step.

### Phase 6: VERIFY

```
━━━ PHASE 6: VERIFY ━━━ 6/7
```

Validate ALL ISC criteria are met. Every single one.

- Run tests (unit, integration, e2e as appropriate)
- Check outputs match expectations
- Verify no regressions
- Evidence required for every assertion — no "I believe it works"
- Screenshots, test output, or diffs as proof

Walk through each ISC criterion and provide evidence of pass or document failure.

Update PRD: mark all passing criteria as checked, document verification evidence.

If any criteria fail, loop back to BUILD (Phase 4) to fix, then re-verify.

### Phase 7: LEARN

```
━━━ PHASE 7: LEARN ━━━ 7/7
```

Capture what happened for future work.

- What worked well?
- What was harder than expected?
- What would you do differently next time?
- Were the ISC criteria well-formed? Any that should have been split or combined?
- Any patterns discovered that apply to future tasks?

Output: Brief retrospective (5-10 bullet points).

## ISC Criteria Rules

ISC (Ideal State Criteria) are the backbone of the Algorithm. They must be:

1. **Atomic** — One verifiable thing per criterion
2. **Binary testable** — Pass or fail, no gray area, no "mostly works"
3. **8-12 words each** — Concise enough to scan, specific enough to verify
4. **Prefixed** — ISC-1, ISC-2, etc. Anti-criteria use ISC-A prefix

### The Splitting Test

Apply these four tests to every criterion. If any test triggers, split it:

1. **AND test** — Contains "and" joining two verifiable things? Split.
2. **WITH test** — Contains "with" adding a second concern? Split.
3. **Domain test** — Spans two domains (e.g., UI + data)? Split.
4. **Verification test** — Would you check two different things to verify it? Split.

### Anti-Criteria

Things that must NOT happen. Prefix with ISC-A:

- `ISC-A1: No existing tests are broken by changes`
- `ISC-A2: No hardcoded secrets in committed code`
- `ISC-A3: No files outside specified scope are modified`

See [isc-decomposition.md](references/isc-decomposition.md) for decomposition strategies.

## PRD (Product Requirements Document)

The PRD is the living document for each Algorithm execution. It tracks:

- Task context and constraints
- All ISC criteria with pass/fail status
- Decisions made and their rationale
- Verification evidence

See [prd-format.md](references/prd-format.md) for the full format specification.

## Phase Transition Rules

1. **Never skip phases** — Each phase builds on the previous one
2. **Phases can loop** — VERIFY failure loops back to BUILD
3. **User approval gates** — PLAN requires user approval before BUILD
4. **PRD is updated** — At every phase transition, update the PRD
5. **Phase headers are mandatory** — Always output the phase header when entering a phase

## Effort Scaling

The Algorithm scales down gracefully for simpler tasks:

- **Standard tier**: Phases are brief. THINK and PLAN can be 2-3 sentences each. The whole Algorithm might complete in a single response.
- **Extended/Advanced**: Each phase gets meaningful depth. PLAN should be detailed.
- **Deep/Comprehensive**: Full ceremony. THINK includes research. PLAN includes architecture diagrams or detailed pseudocode. VERIFY includes comprehensive test runs.

The structure remains the same at every tier — only the depth changes.

## When NOT to Use the Algorithm

- Simple factual questions ("what does this function do?")
- One-line fixes with obvious solutions
- File reads or searches
- Status checks or information gathering

For these, respond directly without Algorithm overhead. The Algorithm is for **building and transforming**, not for answering questions.

## Example Phase Headers

```
━━━ 🔍 OBSERVE ━━━ 1/7
━━━ 🧠 THINK ━━━ 2/7
━━━ 📋 PLAN ━━━ 3/7
━━━ 🔨 BUILD ━━━ 4/7
━━━ ⚡ EXECUTE ━━━ 5/7
━━━ ✅ VERIFY ━━━ 6/7
━━━ 📝 LEARN ━━━ 7/7
```

## Summary

The Algorithm is disciplined execution. It prevents:
- Building before understanding (OBSERVE + THINK first)
- Coding without a plan (PLAN before BUILD)
- Claiming "done" without proof (VERIFY with evidence)
- Repeating mistakes (LEARN captures patterns)

Seven phases. Verifiable criteria. Evidence-based completion. That is the Algorithm.
