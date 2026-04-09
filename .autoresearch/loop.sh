#!/bin/bash
# PAI Autoresearch Loop
# Applies Karpathy's autoresearch pattern to PAI agent prompt optimization.
# Runs overnight — mutates agent prompts, evaluates, keeps improvements.
#
# Usage: nohup bash .autoresearch/loop.sh > .autoresearch/output.log 2>&1 &
# Monitor: tail -f .autoresearch/output.log
# Stop: touch .autoresearch/STOP-pai-engineer (or STOP-pai-boss, etc.)

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

AR_DIR="$REPO_DIR/.autoresearch"
EVAL_DIR="$REPO_DIR/eval"
# Agent names use pai- prefix (pai-engineer, pai-boss, pai-architect)
EVAL_AGENT="${EVAL_AGENT:-pai-engineer}"
# Per-agent state files — allows parallel loops without collision
LOG_FILE="$AR_DIR/log-${EVAL_AGENT}.jsonl"
BASELINE_FILE="$AR_DIR/baseline-${EVAL_AGENT}.txt"
STOP_FILE="$AR_DIR/STOP-${EVAL_AGENT}"
TRIED_FILE="$AR_DIR/tried-${EVAL_AGENT}.log"
STDOUT_LOG="$AR_DIR/mutator-${EVAL_AGENT}-stdout.log"
STDERR_LOG="$AR_DIR/mutator-${EVAL_AGENT}-stderr.log"
HYPOTHESIS_FILE="$AR_DIR/hypothesis-${EVAL_AGENT}.txt"
MAX_EXPERIMENTS="${MAX_EXPERIMENTS:-50}"
NO_MUTATION_STREAK=0
MAX_NO_MUTATION_STREAK=3  # After this many no-mutations, force diversity

# Adaptive early stopping — replace fixed limit with plateau detection
PLATEAU_COUNTER=0
PLATEAU_THRESHOLD=10   # Stop after 10 consecutive non-improvements
MIN_EXPERIMENTS=10     # Always run at least 10

# Checkpoint file for resume support
CHECKPOINT_FILE="$AR_DIR/checkpoint-${EVAL_AGENT}.json"

# Mutation strategies — round-robin rotation
STRATEGIES=(
  "remove_verbose"
  "reorder_top3"
  "add_example"
  "shrink_prompt"
  "change_sequencing"
  "explicit_tool_call"
  "remove_last_added"
)
STRATEGY_INDEX=0

# Save loop state to checkpoint file for resume support
save_checkpoint() {
  cat > "$CHECKPOINT_FILE" << CKPT
{"agent":"$EVAL_AGENT","experiment":$EXPERIMENT,"baseline":"$BASELINE_SCORE","improvements":$IMPROVEMENTS,"strategy_index":$STRATEGY_INDEX,"plateau_counter":$PLATEAU_COUNTER,"ts":"$(date -Iseconds)"}
CKPT
}

# Get latest per-task results for failure analysis
get_failure_analysis() {
  local results_dir
  results_dir=$(ls -td "$EVAL_DIR/results/"* 2>/dev/null | head -1)
  if [ -n "$results_dir" ] && [ -f "$results_dir/results.jsonl" ]; then
    # Extract task scores and find weakest
    python3 -c "
import json, sys
tasks = []
with open('$results_dir/results.jsonl') as f:
    for line in f:
        d = json.loads(line)
        if d.get('agent') == '$EVAL_AGENT':
            tasks.append(d)
if tasks:
    tasks.sort(key=lambda x: x['score'])
    print('TASK SCORES:')
    for t in tasks:
        status = 'WEAK' if t['score'] < 0.85 else 'strong'
        metrics = t.get('metrics', 'no metrics')
        print(f\"  {t['task']}: {t['score']:.3f} ({status}) — {metrics}\")
    weakest = tasks[0]
    failing = [m.split(':')[0]+':'+m.split(':')[1] for m in weakest.get('metrics','').split() if 'fail' in m]
    print(f\"\\nWEAKEST: {weakest['task']} ({weakest['score']:.3f})\")
    if failing:
        print(f\"FAILING METRICS: {', '.join(failing)}\")
    print(f\"Target your mutation at: {weakest['task']}\")
" 2>/dev/null || echo "No task analysis available"
  else
    echo "No results available yet"
  fi
}

# Always establish baseline on first run (score <= 0)
CURRENT_BASELINE=$(cat "$BASELINE_FILE" 2>/dev/null || echo "0.0")
if [ "$CURRENT_BASELINE" = "0.0" ] || [ "$CURRENT_BASELINE" = "0" ]; then
  echo "=== Establishing baseline ==="
  # Map agent name to task dir (pai-engineer -> engineer)
  TASK_DIR_NAME="${EVAL_AGENT#pai-}"
  BASELINE=$(bash "$EVAL_DIR/run-eval.sh" "$EVAL_AGENT" 2>&1 | tail -1)
  if ! echo "$BASELINE" | grep -qE '^[0-9]'; then BASELINE="0.0"; fi
  echo "$BASELINE" > "$BASELINE_FILE"
  echo "{\"type\":\"baseline\",\"score\":$BASELINE,\"ts\":\"$(date -Iseconds)\"}" >> "$LOG_FILE"
  echo "Baseline score: $BASELINE"
fi

BASELINE_SCORE=$(cat "$BASELINE_FILE")
EXPERIMENT=0
IMPROVEMENTS=0
START_TIME=$(date +%s)

# Resume from checkpoint if available
if [ -f "$CHECKPOINT_FILE" ] && [ "$CURRENT_BASELINE" != "0.0" ]; then
  CKPT_EXP=$(python3 -c "import json; print(json.load(open('$CHECKPOINT_FILE'))['experiment'])" 2>/dev/null || echo 0)
  CKPT_BASELINE=$(python3 -c "import json; print(json.load(open('$CHECKPOINT_FILE'))['baseline'])" 2>/dev/null || echo "0.0")
  CKPT_IMPROVEMENTS=$(python3 -c "import json; print(json.load(open('$CHECKPOINT_FILE'))['improvements'])" 2>/dev/null || echo 0)
  CKPT_STRATEGY=$(python3 -c "import json; print(json.load(open('$CHECKPOINT_FILE'))['strategy_index'])" 2>/dev/null || echo 0)
  CKPT_PLATEAU=$(python3 -c "import json; print(json.load(open('$CHECKPOINT_FILE'))['plateau_counter'])" 2>/dev/null || echo 0)
  if [ "$CKPT_EXP" -gt 0 ]; then
    echo "Resuming from checkpoint: experiment $CKPT_EXP, baseline $CKPT_BASELINE, $CKPT_IMPROVEMENTS improvements"
    EXPERIMENT=$CKPT_EXP
    BASELINE_SCORE="$CKPT_BASELINE"
    IMPROVEMENTS=$CKPT_IMPROVEMENTS
    STRATEGY_INDEX=$CKPT_STRATEGY
    PLATEAU_COUNTER=$CKPT_PLATEAU
  fi
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  PAI Autoresearch Loop                   ║"
echo "║  Baseline: $BASELINE_SCORE                         ║"
echo "║  Max experiments: $MAX_EXPERIMENTS                    ║"
echo "║  Evaluating: $EVAL_AGENT                       ║"
echo "║  Stop: touch .autoresearch/STOP-$EVAL_AGENT ║"
echo "╚══════════════════════════════════════════╝"
echo ""

while [ "$EXPERIMENT" -lt "$MAX_EXPERIMENTS" ]; do
  # Check stop signal
  if [ -f "$STOP_FILE" ]; then
    echo "STOP signal received. Halting."
    rm -f "$STOP_FILE"
    break
  fi

  EXPERIMENT=$((EXPERIMENT + 1))
  ELAPSED=$(( ($(date +%s) - START_TIME) / 60 ))
  echo ""
  echo "━━━ Experiment $EXPERIMENT / $MAX_EXPERIMENTS (${ELAPSED}m elapsed, $IMPROVEMENTS improvements) ━━━"

  # 1. MUTATE — Use opencode to modify agent prompt
  echo "  [1/3] Mutating prompt..."

  # Compute current strategy via round-robin
  CURRENT_STRATEGY="${STRATEGIES[$((STRATEGY_INDEX % ${#STRATEGIES[@]}))]}"
  STRATEGY_INDEX=$((STRATEGY_INDEX + 1))
  echo "  Strategy: $CURRENT_STRATEGY"

  # Get failure analysis from last eval run
  FAILURE_ANALYSIS=$(get_failure_analysis)

  # Pick a random task to focus the mutation on
  TASK_DIR_NAME="${EVAL_AGENT#pai-}"
  FOCUS_TASK=$(ls "$EVAL_DIR/tasks/$TASK_DIR_NAME/"*.txt 2>/dev/null | sort -R | head -1)
  FOCUS_NAME=$(basename "$FOCUS_TASK" .txt 2>/dev/null || echo "general")

  # Get last 5 results for context
  RECENT=$(tail -5 "$LOG_FILE" 2>/dev/null || echo "no previous experiments")

  # Get tried mutations history (last 10 for context, avoid repeats)
  TRIED=$(tail -10 "$TRIED_FILE" 2>/dev/null || echo "none yet")

  # Agent prompt file path
  AGENT_PROMPT_FILE="config/agents/${EVAL_AGENT}.md"

  # Build diversity nudge if we're in a no-mutation streak
  DIVERSITY_HINT=""
  if [ "$NO_MUTATION_STREAK" -ge "$MAX_NO_MUTATION_STREAK" ]; then
    DIVERSITY_HINT="
IMPORTANT: The last $NO_MUTATION_STREAK attempts produced NO mutation. You MUST make a change this time.
Try a completely DIFFERENT strategy — reorder sections, remove verbose instructions, add a concrete example,
change the TDD workflow description, or simplify the prompt. Do NOT repeat anything from the tried list below."
  fi

  MUTATE_PROMPT="You are the PAI Autoresearch mutator. Read .autoresearch/program.md for full instructions.

Current baseline score: $BASELINE_SCORE
Experiment: $EXPERIMENT / $MAX_EXPERIMENTS
Recent experiment log:
$RECENT

ALREADY TRIED (do NOT repeat these — try something DIFFERENT):
$TRIED
$DIVERSITY_HINT
Your MANDATORY strategy for this round is: $CURRENT_STRATEGY
- remove_verbose: Delete the longest or most wordy section/rule
- reorder_top3: Move the 3 most important instructions to the very top of the prompt
- add_example: Add a concrete input→output example relevant to the focus task
- shrink_prompt: Remove at least 2 lines to make the prompt shorter
- change_sequencing: Add a "Do X BEFORE Y" constraint based on failure patterns
- explicit_tool_call: Add explicit "Use the write tool to create {filename}" instruction
- remove_last_added: Undo/revert the most recent addition that wasn't reverted by the loop

You MUST follow the assigned strategy. Do not default to "add a rule."

Task-level failure analysis from last eval:
$FAILURE_ANALYSIS

Focus: the '$FOCUS_NAME' task is currently underperforming. Read the task at eval/tasks/$TASK_DIR_NAME/$FOCUS_NAME.txt, then read the current agent prompt at $AGENT_PROMPT_FILE.

Make exactly ONE targeted mutation to $AGENT_PROMPT_FILE that you hypothesize will improve the agent's score on this task. Your mutation MUST be different from everything in the ALREADY TRIED list above.

After editing the agent file, READ .autoresearch/hypothesis-${EVAL_AGENT}.txt first, THEN write your hypothesis to it.

Remember: ONLY edit the markdown body of the agent file, not the YAML frontmatter. Keep the prompt SHORT (under 80 lines). You MUST make a file change — do not just read and exit. IMPORTANT: You must READ any file before you can WRITE to it."

  timeout 180 opencode run \
    --dangerously-skip-permissions \
    --pure \
    "$MUTATE_PROMPT" \
    >"$STDOUT_LOG" 2>"$STDERR_LOG" || true

  # Check if anything actually changed
  if git diff --quiet config/agents/; then
    echo "  No mutation made — skipping eval"
    NO_MUTATION_STREAK=$((NO_MUTATION_STREAK + 1))
    echo "{\"exp\":$EXPERIMENT,\"type\":\"no_mutation\",\"streak\":$NO_MUTATION_STREAK,\"ts\":\"$(date -Iseconds)\"}" >> "$LOG_FILE"
    continue
  fi

  # Compute diff hash and check for repeats
  DIFF_HASH=$(git diff config/agents/ | md5sum | cut -c1-16)
  if grep -q "$DIFF_HASH" "$TRIED_FILE" 2>/dev/null; then
    echo "  Duplicate mutation detected (hash: $DIFF_HASH) — skipping eval"
    git checkout -- config/agents/
    NO_MUTATION_STREAK=$((NO_MUTATION_STREAK + 1))
    echo "{\"exp\":$EXPERIMENT,\"type\":\"duplicate\",\"hash\":\"$DIFF_HASH\",\"ts\":\"$(date -Iseconds)\"}" >> "$LOG_FILE"
    continue
  fi
  NO_MUTATION_STREAK=0  # Reset streak on successful mutation

  HYPOTHESIS=$(cat "$HYPOTHESIS_FILE" 2>/dev/null || echo "unknown")
  DIFF_SUMMARY=$(git diff --stat config/agents/ | tail -1)
  DIFF_PATCH=$(git diff config/agents/ | head -40)
  echo "  Mutation: $DIFF_SUMMARY"
  echo "  Hypothesis: $HYPOTHESIS"

  # Log this mutation attempt to tried-mutations (so future experiments avoid repeats)
  echo "--- Exp $EXPERIMENT [hash:$DIFF_HASH]: $HYPOTHESIS | Diff: $DIFF_SUMMARY" >> "$TRIED_FILE"

  # 2. EVALUATE — Run eval suite
  echo "  [2/3] Running eval suite..."
  SCORE=$(bash "$EVAL_DIR/run-eval.sh" "$EVAL_AGENT" 2>&1 | tail -1)

  # Handle non-numeric
  if ! echo "$SCORE" | grep -qE '^[0-9]'; then
    SCORE="0.0000"
  fi

  echo "  Score: $SCORE (baseline: $BASELINE_SCORE)"

  # 3. DECIDE — Keep or revert
  # Use >= so lateral moves (same score) are kept — they change strategy without regressing
  DOMINATED=$(awk "BEGIN {print ($SCORE < $BASELINE_SCORE) ? 1 : 0}")

  if [ "$DOMINATED" = "0" ]; then
    if [ "$(awk "BEGIN {print ($SCORE > $BASELINE_SCORE) ? 1 : 0}")" = "1" ]; then
      echo "  [3/3] ✓ IMPROVED — committing"
      COMMIT_TYPE="improvement"
    else
      echo "  [3/3] ≈ LATERAL — committing (same score, new strategy)"
      COMMIT_TYPE="lateral"
    fi
    git add config/agents/
    git add .autoresearch/hypothesis-${EVAL_AGENT}.txt 2>/dev/null || true
    git commit -m "autoresearch: exp $EXPERIMENT score $BASELINE_SCORE→$SCORE

Hypothesis: $HYPOTHESIS"
    if [ "$COMMIT_TYPE" = "improvement" ]; then
      BASELINE_SCORE="$SCORE"
      echo "$SCORE" > "$BASELINE_FILE"
      IMPROVEMENTS=$((IMPROVEMENTS + 1))
      PLATEAU_COUNTER=0  # Reset on any improvement
    else
      PLATEAU_COUNTER=$((PLATEAU_COUNTER / 2))  # Halve, don't reset — laterals partially explore
    fi

    echo "{\"exp\":$EXPERIMENT,\"type\":\"$COMMIT_TYPE\",\"score\":$SCORE,\"prev\":$BASELINE_SCORE,\"hypothesis\":\"$HYPOTHESIS\",\"ts\":\"$(date -Iseconds)\"}" >> "$LOG_FILE"
  else
    echo "  [3/3] ✗ Regressed — reverting"
    git checkout -- config/agents/
    # NOTE: Do NOT revert hypothesis file — the mutator needs to see what was last tried
    PLATEAU_COUNTER=$((PLATEAU_COUNTER + 1))
    if [ "$PLATEAU_COUNTER" -ge "$PLATEAU_THRESHOLD" ] && [ "$EXPERIMENT" -ge "$MIN_EXPERIMENTS" ]; then
      echo "  ⚠ Plateau detected: $PLATEAU_COUNTER consecutive non-improvements. Stopping early."
      echo "{\"exp\":$EXPERIMENT,\"type\":\"revert\",\"score\":$SCORE,\"baseline\":$BASELINE_SCORE,\"hypothesis\":\"$HYPOTHESIS\",\"ts\":\"$(date -Iseconds)\"}" >> "$LOG_FILE"
      save_checkpoint
      break
    fi

    echo "{\"exp\":$EXPERIMENT,\"type\":\"revert\",\"score\":$SCORE,\"baseline\":$BASELINE_SCORE,\"hypothesis\":\"$HYPOTHESIS\",\"ts\":\"$(date -Iseconds)\"}" >> "$LOG_FILE"
  fi

  # Save checkpoint at end of each experiment
  save_checkpoint
done

# Clean up checkpoint on normal completion
rm -f "$CHECKPOINT_FILE"

# Summary
TOTAL_TIME=$(( ($(date +%s) - START_TIME) / 60 ))
FINAL_SCORE=$(cat "$BASELINE_FILE")

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  Autoresearch Complete                   ║"
echo "║  Experiments: $EXPERIMENT                         ║"
echo "║  Improvements: $IMPROVEMENTS                        ║"
echo "║  Final score: $FINAL_SCORE                       ║"
echo "║  Duration: ${TOTAL_TIME}m                          ║"
echo "╚══════════════════════════════════════════╝"

echo "{\"type\":\"complete\",\"experiments\":$EXPERIMENT,\"improvements\":$IMPROVEMENTS,\"final_score\":$FINAL_SCORE,\"duration_min\":$TOTAL_TIME,\"ts\":\"$(date -Iseconds)\"}" >> "$LOG_FILE"
