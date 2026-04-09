# SRD: Autoresearch Loop v2 — Comprehensive Improvement Plan

## Executive Summary

The current autoresearch system (Karpathy-pattern prompt optimization) has proven the concept: automated mutation → eval → keep/revert loops can improve agent prompts. However, after running multiple campaigns across three agents (engineer, architect, boss) with multiple models (Gemma 31B, Qwen 3.5 35B, GPT-OSS 120B), clear structural limitations have emerged. This SRD proposes a comprehensive redesign of the mutator, evaluator, and loop orchestration to break through the current plateaus.

---

## Problem Statement

### Current Results

| Agent | Model | Baseline | Best | Improvement | Plateau After |
|-------|-------|----------|------|-------------|---------------|
| pai-engineer | gemma-4-31b-it-4bit | 0.8500 | 0.8667 | +2.0% | Exp 11/50 |
| pai-engineer | Qwen3.5-35B-A3B-8bit | 0.8167 | 0.8500 | +4.1% | Exp 1/25 |
| pai-architect | gemma-4-31b-it-4bit | 0.7381 | 0.8095 | +9.7% | Exp 11/50 |
| pai-architect | Qwen3.5-35B-A3B-8bit | 0.8333 | 0.8333 | 0% | Exp 0 (no improvement) |

### Diagnosed Root Causes

**1. Mutator trapped in local optimum.** The mutator keeps trying the same strategy (add task-specific rules) even after repeated failures. It doesn't learn from the tried-mutations log effectively.

**2. Equal-weight binary metrics mask what matters.** E1 (file exists) and E3 (tests pass) both count as 1 point. An agent that creates files but produces broken tests scores 14/20 while one that produces perfect code but forgets an export scores 19/20. The scoring doesn't reflect actual quality.

**3. Only 3 tasks sampled per eval.** `MAX_TASKS=3` means each eval run only tests 3 of 10 engineer tasks (or 3 of 4 architect tasks). Mutations that help one task but hurt two others look like improvements due to sampling variance.

**4. Mutator can only add/modify rules.** The mutation space is "change the prompt body text." It cannot change temperature, max_steps, tool permissions, or the task itself. These are often more impactful than prompt wording.

**5. No per-task score tracking.** The aggregate score hides which tasks improved and which regressed. The mutator targets tasks blindly.

**6. Non-deterministic eval.** Same prompt + same task can score differently across runs due to model randomness. A mutation might be reverted not because it's worse, but because of noise.

**7. No mutation type diversity.** The program.md lists many mutation strategies (reorder, remove, add example, shrink) but the mutator defaults to "add a rule" almost every time.

---

## Architecture: Autoresearch v2

### Phase 1: Evaluator Overhaul

#### 1.1 Weighted Scoring

Replace equal-weight binary metrics with tiered weights reflecting actual importance.

**Engineer weights:**

| Tier | Metrics | Weight | Rationale |
|------|---------|--------|-----------|
| Critical | E3 (tests pass) | 3x | If tests don't pass, nothing else matters |
| High | E1, E2, E6, Q7, S5 | 2x | Core deliverables: files exist, exports, imports, TDD order |
| Standard | Q1-Q6, Q8, Q9, E4, E5 | 1x | Quality signals |
| Low | S1, S2, S3, S4 | 0.5x | Speed/efficiency — nice but secondary |

Score formula: `sum(metric * weight) / sum(weights)` instead of `passed / total`.

**Architect weights:**

| Tier | Metrics | Weight | Rationale |
|------|---------|--------|-----------|
| Critical | A1 (doc exists), A3 (trade-offs), A5 (recommendation) | 3x | Core deliverables |
| High | A2 (structured), A4 (constraints), A8 (failure modes) | 2x | Quality signals |
| Standard | A6 (length), A7 (no code), A9, A10 | 1x | Polish |

#### 1.2 All Tasks Per Eval

Change `MAX_TASKS` from 3 to ALL tasks for the agent under test. This eliminates sampling variance.

- Engineer: 10 tasks × ~3 min = ~30 min per eval (acceptable)
- Architect: 4 tasks × ~5 min = ~20 min per eval
- Boss: 4 tasks × ~5 min = ~20 min per eval

Trade-off: Slower experiments but dramatically more reliable scores. Consider caching: if a task's prompt+model haven't changed, reuse the previous output.

#### 1.3 Per-Task Score Tracking

Log individual task scores in the JSONL:

```json
{
  "exp": 5,
  "type": "eval",
  "aggregate": 0.8500,
  "tasks": {
    "01-palindrome": 0.95,
    "02-debounce": 0.70,
    "03-csv2json": 0.85,
    "04-fix-sort": 0.90,
    "05-stack": 0.85
  },
  "weakest": "02-debounce",
  "strongest": "01-palindrome"
}
```

The mutator can then focus on the weakest task rather than guessing.

#### 1.4 Noise Reduction: Multi-Run Averaging

Run each eval task 2x and average the scores. This costs 2x time but eliminates "got lucky/unlucky" reverts. Only enable for close decisions (score within ±0.03 of baseline).

#### 1.5 New Metrics

**Engineer:**
- `E7: bun test runs without error` — distinct from E3 (tests pass). Catches syntax errors, missing dependencies.
- `Q10: no duplicate code` — detect copy-paste patterns (>3 identical lines) between test and impl.
- `Q11: function signature matches task` — parse task description for function name, check impl exports it.

**Architect:**
- `A11: quantitative estimates` — contains numbers (latency, throughput, capacity, percentages). Design docs without numbers are hand-waving.
- `A12: diagram or table present` — contains markdown table or ASCII diagram. Forces structured thinking.

**Boss:**
- `D7: verification step` — boss read the output file after delegation (not just delegated and assumed success).
- `D8: error recovery` — if first delegation failed, boss retried or adjusted scope.

---

### Phase 2: Mutator Overhaul

#### 2.1 Strategy Selector

Instead of the mutator choosing its own strategy each time (which converges on "add a rule"), force-rotate through mutation strategies:

```
STRATEGIES = [
  "remove_verbose",     # Delete the longest section or rule
  "reorder_top3",       # Move the 3 most important instructions to the top
  "add_example",        # Add a concrete input→output example for the weakest task
  "shrink_prompt",      # Reduce total lines by 10%
  "change_sequencing",  # Add "Do X BEFORE Y" constraints based on failure patterns
  "explicit_tool_call", # Add explicit "Use the write tool to create {file}" instructions
  "remove_last_added",  # Undo the most recent mutation that wasn't reverted
]
```

Round-robin through strategies. The mutator prompt includes: "Your strategy this round is: {strategy}. You MUST use this strategy."

#### 2.2 Failure Analysis

Before mutating, the mutator receives the per-task score breakdown and the actual failing metrics:

```
TASK SCORES:
  01-palindrome: 0.95 (strong)
  02-debounce: 0.70 (WEAK — failing: E3 tests pass, Q4 edge cases)
  07-retry: 0.75 (WEAK — failing: Q8 test quality, S5 TDD order)

FAILING METRICS on weakest task (02-debounce):
  ✗ E3: tests pass — bun test exited with error
  ✗ Q4: edge cases — only 1 edge case found, need 3
  
Your mutation should target: 02-debounce, specifically E3 and Q4.
```

This replaces the current approach of randomly picking a focus task.

#### 2.3 Anti-Repeat Enforcement

The current `tried-mutations.log` is provided as context but the mutator ignores it. Strengthen:

1. Hash each mutation diff (first 200 chars of the actual diff)
2. Before committing the mutation, check if a similar diff hash exists in the tried log
3. If duplicate detected, reject and force a different strategy
4. After 3 consecutive no-mutation results, force the "shrink_prompt" strategy

#### 2.4 Crossover Mutations

When multiple agents have been optimized, allow cross-pollination:

- If pai-architect's prompt has a section that improved its score, try adding a similar pattern to pai-engineer
- Example: architect's "Document Structure" section → engineer's "Output Structure" section

#### 2.5 Temperature Mutations

Allow the mutator to propose temperature changes (0.0 to 0.5 range). Temperature significantly affects code generation quality and is currently fixed at 0.1 (engineer) / 0.2 (architect/boss). This is a high-leverage knob that prompt text mutations can't reach.

---

### Phase 3: Loop Orchestration

#### 3.1 Adaptive Experiment Budget

Instead of fixed 25 or 50 experiments:

```
- If last 5 experiments all reverted → increase diversity (force strategy rotation)
- If last 10 experiments all reverted → stop early (plateau detected)
- If an improvement found → reset the plateau counter
- Max experiments: 50 (hard cap)
- Min experiments: 10 (always try at least 10)
```

#### 3.2 Parallel Agent Loops

Run engineer and architect loops simultaneously since they use different prompt files and eval tasks. The model handles concurrent requests via oMLX's batched engine.

```bash
# Launch both in parallel
EVAL_AGENT=pai-engineer MAX_EXPERIMENTS=25 nohup bash .autoresearch/loop.sh &
EVAL_AGENT=pai-architect MAX_EXPERIMENTS=25 nohup bash .autoresearch/loop.sh &
```

This halves wall-clock time for a full campaign.

#### 3.3 Model Comparison Mode

New command: `bash .autoresearch/compare-models.sh pai-engineer model1 model2`

Runs the same eval suite on both models with the current prompt, outputs a side-by-side comparison. This replaces the current manual process of switching models and re-running.

#### 3.4 Checkpoint & Resume

Save loop state to a JSON file so runs can be interrupted and resumed:

```json
{
  "agent": "pai-engineer",
  "experiment": 12,
  "baseline": 0.8667,
  "improvements": 3,
  "strategy_index": 4,
  "started": "2026-04-09T01:00:00Z"
}
```

On restart, resume from the saved state instead of re-establishing baseline.

---

### Phase 4: Eval Task Improvements

#### 4.1 Task Difficulty Tiers

Label tasks by difficulty so the mutator knows what to prioritize:

| Tier | Engineer Tasks | Architect Tasks |
|------|---------------|-----------------|
| Easy | palindrome, stack | cache-strategy |
| Medium | csv2json, debounce, linked-list | auth-spec, queue-vs-sync |
| Hard | retry, event-emitter, lru-cache, validator | multi-tenant |

Easy tasks should score >0.9 consistently. Focus mutations on medium/hard tasks.

#### 4.2 Golden Test Outputs

Create reference outputs for each task that score 1.0 on all metrics. Store in `eval/golden/`. The mutator can read these to understand what "perfect" looks like and guide its mutations toward producing agents that generate similar output.

#### 4.3 Eval Determinism

Set model temperature to 0.0 during eval (override agent config). This eliminates randomness and makes scores perfectly reproducible. Only the mutator run uses the agent's configured temperature.

---

## Implementation Phases

### Phase 1: Evaluator (Priority: CRITICAL, Effort: 2 days)
1. Implement weighted scoring in `check-metrics.sh`
2. Change `MAX_TASKS` to run all tasks
3. Add per-task score logging to JSONL
4. Add new metrics (E7, Q10, Q11, A11, A12, D7, D8)

### Phase 2: Mutator (Priority: HIGH, Effort: 2 days)
1. Implement strategy rotation in `loop.sh`
2. Add failure analysis to mutator prompt
3. Add diff-hash anti-repeat
4. Enable temperature mutations

### Phase 3: Loop (Priority: MEDIUM, Effort: 1 day)
1. Adaptive early stopping
2. Parallel agent loops
3. Checkpoint & resume
4. Model comparison command

### Phase 4: Eval Tasks (Priority: LOW, Effort: 1 day)
1. Task difficulty labels
2. Golden test outputs
3. Eval determinism (temp=0)

---

## Success Criteria

| Metric | Current | Target |
|--------|---------|--------|
| Engineer best score | 0.8667 | >0.92 |
| Architect best score | 0.8333 | >0.90 |
| Boss best score | unknown | >0.85 |
| Experiments to plateau | 11 | >20 (more productive exploration) |
| Eval noise (same prompt, different runs) | ~±0.05 | <±0.01 |
| Time per experiment (engineer) | 7-9 min | 5-7 min (all tasks but cached) |
| Mutations that are duplicates | ~30% | <5% |

---

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Weighted scoring changes baseline — can't compare to old runs | Medium | Keep old scoring as `check-metrics-v1.sh`, run both during transition |
| All-tasks eval is too slow for 120B models | High | Use MoE models (Qwen3.5) for autoresearch, reserve dense models for manual eval |
| Strategy rotation forces bad strategies | Low | Each strategy gets 2 attempts before rotation, not just 1 |
| Parallel loops contend for GPU memory | Medium | oMLX batched engine handles this; monitor with process_memory_enforcer |
| Golden outputs overfit the eval to one "correct" style | Medium | Use goldens as reference only in mutator prompt, not as scoring criteria |

---

## Non-Goals

- Changing the eval task set (that's a separate effort)
- Optimizing for cloud models (this system is for local 26-35B models)
- Multi-agent coordination optimization (boss→engineer pipeline — separate SRD)
- Automated model selection (manual for now)
