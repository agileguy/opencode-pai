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
MAX_EXPERIMENTS="${MAX_EXPERIMENTS:-50}"
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

  # Agent prompt file path
  AGENT_PROMPT_FILE="config/agents/${EVAL_AGENT}.md"

  MUTATE_PROMPT="You are the PAI Autoresearch mutator. Read .autoresearch/program.md for full instructions.

Current baseline score: $BASELINE_SCORE
Recent experiment log:
$RECENT

Focus: the '$FOCUS_NAME' task is currently underperforming. Read the task at eval/tasks/$TASK_DIR_NAME/$FOCUS_NAME.txt, then read the current agent prompt at $AGENT_PROMPT_FILE.

Make exactly ONE targeted mutation to $AGENT_PROMPT_FILE that you hypothesize will improve the agent's score on this task. Write your hypothesis to .autoresearch/current-hypothesis.txt.

Remember: ONLY edit the markdown body of the agent file, not the YAML frontmatter. Keep the prompt SHORT (under 80 lines)."

  timeout 180 opencode \
    --prompt "$MUTATE_PROMPT" \
    --pure \
    2>/dev/null >/dev/null || true

  # Check if anything actually changed
  if git diff --quiet config/agents/; then
    echo "  No mutation made — skipping eval"
    echo "{\"exp\":$EXPERIMENT,\"type\":\"no_mutation\",\"ts\":\"$(date -Iseconds)\"}" >> "$LOG_FILE"
    continue
  fi

  HYPOTHESIS=$(cat "$AR_DIR/current-hypothesis.txt" 2>/dev/null || echo "unknown")
  DIFF_STAT=$(git diff --stat config/agents/ | tail -1)
  echo "  Mutation: $DIFF_STAT"
  echo "  Hypothesis: $HYPOTHESIS"

  # 2. EVALUATE — Run eval suite
  echo "  [2/3] Running eval suite..."
  SCORE=$(bash "$EVAL_DIR/run-eval.sh" "$EVAL_AGENT" 2>&1 | tail -1)

  # Handle non-numeric
  if ! echo "$SCORE" | grep -qE '^[0-9]'; then
    SCORE="0.0000"
  fi

  echo "  Score: $SCORE (baseline: $BASELINE_SCORE)"

  # 3. DECIDE — Keep or revert
  IMPROVED=$(echo "$SCORE > $BASELINE_SCORE" | bc -l 2>/dev/null || echo 0)

  if [ "$IMPROVED" = "1" ]; then
    echo "  [3/3] ✓ IMPROVED — committing"
    git add config/agents/
    git add .autoresearch/current-hypothesis.txt 2>/dev/null || true
    git commit -m "autoresearch: exp $EXPERIMENT score $BASELINE_SCORE→$SCORE

Hypothesis: $HYPOTHESIS"
    BASELINE_SCORE="$SCORE"
    echo "$SCORE" > "$BASELINE_FILE"
    IMPROVEMENTS=$((IMPROVEMENTS + 1))

    echo "{\"exp\":$EXPERIMENT,\"type\":\"improvement\",\"score\":$SCORE,\"prev\":$BASELINE_SCORE,\"hypothesis\":\"$HYPOTHESIS\",\"ts\":\"$(date -Iseconds)\"}" >> "$LOG_FILE"
  else
    echo "  [3/3] ✗ Regressed — reverting"
    git checkout -- config/agents/
    git checkout -- .autoresearch/current-hypothesis.txt 2>/dev/null || true

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
