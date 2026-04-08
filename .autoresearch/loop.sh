#!/bin/bash
# PAI Autoresearch Loop
# Applies Karpathy's autoresearch pattern to PAI agent prompt optimization.
# Runs overnight — mutates agent prompts, evaluates, keeps improvements.
#
# Usage: nohup bash .autoresearch/loop.sh > .autoresearch/output.log 2>&1 &
# Monitor: tail -f .autoresearch/output.log
# Stop: touch .autoresearch/STOP

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

AR_DIR="$REPO_DIR/.autoresearch"
EVAL_DIR="$REPO_DIR/eval"
LOG_FILE="$AR_DIR/log.jsonl"
BASELINE_FILE="$AR_DIR/baseline-score.txt"
STOP_FILE="$AR_DIR/STOP"
TRIED_FILE="$AR_DIR/tried-mutations.log"
MAX_EXPERIMENTS="${MAX_EXPERIMENTS:-50}"
NO_MUTATION_STREAK=0
MAX_NO_MUTATION_STREAK=3  # After this many no-mutations, force diversity
# Agent names use pai- prefix (pai-engineer, pai-boss)
EVAL_AGENT="${EVAL_AGENT:-pai-engineer}"  # pai-engineer, pai-boss, or all

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

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  PAI Autoresearch Loop                   ║"
echo "║  Baseline: $BASELINE_SCORE                         ║"
echo "║  Max experiments: $MAX_EXPERIMENTS                    ║"
echo "║  Evaluating: $EVAL_AGENT                       ║"
echo "║  Stop: touch .autoresearch/STOP          ║"
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
Focus: the '$FOCUS_NAME' task is currently underperforming. Read the task at eval/tasks/$TASK_DIR_NAME/$FOCUS_NAME.txt, then read the current agent prompt at $AGENT_PROMPT_FILE.

Make exactly ONE targeted mutation to $AGENT_PROMPT_FILE that you hypothesize will improve the agent's score on this task. Your mutation MUST be different from everything in the ALREADY TRIED list above. Write your hypothesis to .autoresearch/current-hypothesis.txt.

Remember: ONLY edit the markdown body of the agent file, not the YAML frontmatter. Keep the prompt SHORT (under 80 lines). You MUST make a file change — do not just read and exit."

  timeout 180 opencode run \
    --dangerously-skip-permissions \
    --pure \
    "$MUTATE_PROMPT" \
    2>/dev/null >/dev/null || true

  # Check if anything actually changed
  if git diff --quiet config/agents/; then
    echo "  No mutation made — skipping eval"
    NO_MUTATION_STREAK=$((NO_MUTATION_STREAK + 1))
    echo "{\"exp\":$EXPERIMENT,\"type\":\"no_mutation\",\"streak\":$NO_MUTATION_STREAK,\"ts\":\"$(date -Iseconds)\"}" >> "$LOG_FILE"
    continue
  fi
  NO_MUTATION_STREAK=0  # Reset streak on successful mutation

  HYPOTHESIS=$(cat "$AR_DIR/current-hypothesis.txt" 2>/dev/null || echo "unknown")
  DIFF_SUMMARY=$(git diff --stat config/agents/ | tail -1)
  DIFF_PATCH=$(git diff config/agents/ | head -40)
  echo "  Mutation: $DIFF_SUMMARY"
  echo "  Hypothesis: $HYPOTHESIS"

  # Log this mutation attempt to tried-mutations (so future experiments avoid repeats)
  echo "--- Exp $EXPERIMENT: $HYPOTHESIS | Diff: $DIFF_SUMMARY" >> "$TRIED_FILE"

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
    git add .autoresearch/current-hypothesis.txt 2>/dev/null || true
    git commit -m "autoresearch: exp $EXPERIMENT score $BASELINE_SCORE→$SCORE

Hypothesis: $HYPOTHESIS"
    if [ "$COMMIT_TYPE" = "improvement" ]; then
      BASELINE_SCORE="$SCORE"
      echo "$SCORE" > "$BASELINE_FILE"
      IMPROVEMENTS=$((IMPROVEMENTS + 1))
    fi

    echo "{\"exp\":$EXPERIMENT,\"type\":\"$COMMIT_TYPE\",\"score\":$SCORE,\"prev\":$BASELINE_SCORE,\"hypothesis\":\"$HYPOTHESIS\",\"ts\":\"$(date -Iseconds)\"}" >> "$LOG_FILE"
  else
    echo "  [3/3] ✗ Regressed — reverting"
    git checkout -- config/agents/
    # NOTE: Do NOT revert current-hypothesis.txt — the mutator needs to see what was last tried

    echo "{\"exp\":$EXPERIMENT,\"type\":\"revert\",\"score\":$SCORE,\"baseline\":$BASELINE_SCORE,\"hypothesis\":\"$HYPOTHESIS\",\"ts\":\"$(date -Iseconds)\"}" >> "$LOG_FILE"
  fi
done

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
