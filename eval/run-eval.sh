#!/bin/bash
# run-eval.sh — Runs the eval suite against current agent prompts
# Usage: run-eval.sh [engineer|boss|all]
# Returns: aggregate score (0.0 to 1.0)

set -uo pipefail

EVAL_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT="${1:-all}"
TIMEOUT=300  # 5 min per task
TOTAL_SCORE=0
TOTAL_TASKS=0
RESULTS_DIR="$EVAL_DIR/results/$(date +%Y%m%d-%H%M%S)"

mkdir -p "$RESULTS_DIR"

run_task() {
  local agent="$1"
  local task_file="$2"
  local task_name="$(basename "$task_file" .txt)"
  local output_dir="/workspace/eval/output/${agent}-${task_name}"

  echo ""
  echo "━━━ $agent / $task_name ━━━"

  # Clean output dir
  rm -rf "$output_dir" 2>/dev/null
  mkdir -p "$output_dir"

  # Read task prompt
  local prompt
  prompt=$(cat "$task_file")

  # Run opencode with the agent
  echo "  Running task (timeout ${TIMEOUT}s)..."
  timeout "$TIMEOUT" opencode \
    --agent "$agent" \
    --prompt "$prompt" \
    --pure \
    2>"$output_dir/.stderr.log" \
    >"$output_dir/.stdout.log" \
    || true

  # Check metrics
  local score
  score=$(bash "$EVAL_DIR/check-metrics.sh" "$agent" "$task_name" "$output_dir" 2>&1 | tail -1)

  # Handle non-numeric score
  if ! echo "$score" | grep -qE '^[0-9]'; then
    score="0.000"
  fi

  echo "  → Score: $score"

  # Log result
  echo "{\"agent\":\"$agent\",\"task\":\"$task_name\",\"score\":$score,\"ts\":\"$(date -Iseconds)\"}" >> "$RESULTS_DIR/results.jsonl"

  TOTAL_SCORE=$(echo "$TOTAL_SCORE + $score" | bc)
  TOTAL_TASKS=$((TOTAL_TASKS + 1))
}

echo "═══ PAI Eval Suite ═══"
echo "Time: $(date)"
echo "Results: $RESULTS_DIR"

# Run engineer tasks
if [ "$AGENT" = "engineer" ] || [ "$AGENT" = "all" ]; then
  echo ""
  echo "── pai-engineer tasks ──"
  for task in "$EVAL_DIR/tasks/engineer/"*.txt; do
    [ -f "$task" ] && run_task "pai-engineer" "$task"
  done
fi

# Run boss tasks
if [ "$AGENT" = "boss" ] || [ "$AGENT" = "all" ]; then
  echo ""
  echo "── pai-boss tasks ──"
  for task in "$EVAL_DIR/tasks/boss/"*.txt; do
    [ -f "$task" ] && run_task "pai-boss" "$task"
  done
fi

# Aggregate score
if [ "$TOTAL_TASKS" -gt 0 ]; then
  AGG_SCORE=$(echo "scale=4; $TOTAL_SCORE / $TOTAL_TASKS" | bc)
else
  AGG_SCORE="0.0000"
fi

echo ""
echo "═══ AGGREGATE ═══"
echo "Tasks: $TOTAL_TASKS"
echo "Aggregate score: $AGG_SCORE"
echo ""

# Write aggregate to file for the loop to read
echo "$AGG_SCORE" > "$RESULTS_DIR/aggregate-score.txt"

# Also output just the number on last line for scripting
echo "$AGG_SCORE"
