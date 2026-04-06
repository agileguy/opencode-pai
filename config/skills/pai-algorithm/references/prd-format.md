# PRD Format Specification

The PRD (Product Requirements Document) is the living document for every Algorithm execution. Create it during OBSERVE, update it at every phase transition.

## Template

```yaml
---
task: "8 word task description"
slug: YYYYMMDD-HHMMSS_kebab-task-name
effort: standard|extended|advanced|deep|comprehensive
phase: observe|think|plan|build|execute|verify|learn|complete
progress: 0/N
mode: interactive
started: ISO-8601
updated: ISO-8601
---
```

## Sections

### Context

What was requested, why it matters, constraints, and risks.

```markdown
## Context

**Request:** [What the user asked for]
**Why:** [Why this matters / what problem it solves]
**Constraints:** [Time, compatibility, scope limits]
**Risks:** [What could go wrong]
```

### Criteria

All ISC criteria, checked off as they pass verification.

```markdown
## Criteria

- [ ] ISC-1: Config file loads without parse errors
- [ ] ISC-2: All existing tests continue to pass
- [ ] ISC-A1: No files outside /config are modified
- [x] ISC-3: New skill directory structure exists (verified)
```

Rules:
- Unchecked `[ ]` until evidence confirms pass
- Checked `[x]` only during or after VERIFY phase
- Anti-criteria (ISC-A prefix) are verified the same way
- Never check a box without evidence

### Decisions

Key decisions made during execution, with rationale.

```markdown
## Decisions

- **Chose X over Y** — Y required additional dependency, X uses stdlib
- **Split into two files** — Single file exceeded 200 lines, readability concern
```

### Verification

Evidence that criteria were met. Added during VERIFY phase.

```markdown
## Verification

**ISC-1:** Config loads — `bun run validate` exits 0 (output attached)
**ISC-2:** Tests pass — `bun test` shows 14/14 passing
**ISC-A1:** Scope check — `git diff --name-only` shows only /config files
```

## PRD Lifecycle

1. **OBSERVE** — Create PRD with context and all ISC criteria
2. **THINK** — No PRD changes (analysis phase)
3. **PLAN** — Update if criteria need adjustment based on plan
4. **BUILD** — Add decisions as they're made
5. **EXECUTE** — Update phase and progress as steps complete
6. **VERIFY** — Check criteria, add verification evidence
7. **LEARN** — Mark phase as `complete`, add retrospective notes

## Progress Tracking

The `progress` field tracks ISC criteria completion: `verified/total`.

- `progress: 0/12` — Starting, nothing verified
- `progress: 7/12` — 7 of 12 criteria verified
- `progress: 12/12` — All criteria met, task complete
