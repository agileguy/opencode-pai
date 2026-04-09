#!/bin/bash
# run-eval.sh — Runs the eval suite against current agent prompts
# Usage: run-eval.sh [engineer|boss|all]
# Returns: aggregate score (0.0 to 1.0)

set -uo pipefail

EVAL_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT="${1:-all}"  # pai-engineer, pai-boss, or all
TIMEOUT=300  # 5 min per task
MAX_TASKS="${MAX_TASKS:-999}"  # Run all tasks by default
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

  # Read task prompt and inject output dir
  local raw_prompt
  raw_prompt=$(cat "$task_file")
  local prompt="${raw_prompt} IMPORTANT: Save ALL output files to ${output_dir}/"

  # Run opencode with the agent
  echo "  Running task (timeout ${TIMEOUT}s)..."
  echo "  Output dir: $output_dir"
  timeout "$TIMEOUT" opencode run \
    --agent "$agent" \
    --dangerously-skip-permissions \
    --pure \
    --dir /workspace \
    "$prompt" \
    2>"$output_dir/.stderr.log" \
    >"$output_dir/.stdout.log" \
    || true

  # Scan for files the agent may have created in alternative locations
  local short_name="$(echo "$task_name" | sed 's/^[0-9]*-//')"
  for alt_dir in \
    "/workspace/eval/output/$short_name" \
    "/workspace/$short_name" \
    "/workspace/eval/output/${agent}-${short_name}" \
    "/workspace/output/$short_name"; do
    if [ -d "$alt_dir" ] && [ "$alt_dir" != "$output_dir" ]; then
      echo "  Found files in $alt_dir — copying to $output_dir"
      cp -a "$alt_dir"/* "$output_dir/" 2>/dev/null || true
    fi
  done
  # Also find any .ts files created anywhere under /workspace/eval/output that match
  find /workspace/eval/output -maxdepth 2 -name "*.ts" -newer "$output_dir/.stderr.log" 2>/dev/null | while read f; do
    cp -n "$f" "$output_dir/" 2>/dev/null || true
  done

  # Check metrics — capture full output for per-metric logging
  local metrics_output
  metrics_output=$(bash "$EVAL_DIR/check-metrics.sh" "$agent" "$task_name" "$output_dir" 2>&1)
  local score
  score=$(echo "$metrics_output" | tail -1)

  # Handle non-numeric score
  if ! echo "$score" | grep -qE '^[0-9]'; then
    score="0.000"
  fi

  # Extract compact metrics string (e.g. "E1:pass E2:fail E3:pass ...")
  local metrics_compact
  metrics_compact=$(echo "$metrics_output" | grep -E '^\s+[✓✗]' | sed -E 's/^\s+✓ ([A-Z][0-9]+):.*/\1:pass/; s/^\s+✗ ([A-Z][0-9]+):.*/\1:fail/' | tr '\n' ' ' | sed 's/ $//')

  echo "  → Score: $score"

  # Log result with per-metric detail
  echo "{\"agent\":\"$agent\",\"task\":\"$task_name\",\"score\":$score,\"metrics\":\"$metrics_compact\",\"ts\":\"$(date -Iseconds)\"}" >> "$RESULTS_DIR/results.jsonl"

  TOTAL_SCORE=$(awk "BEGIN {print $TOTAL_SCORE + $score}")
  TOTAL_TASKS=$((TOTAL_TASKS + 1))
}

echo "═══ PAI Eval Suite ═══"
echo "Time: $(date)"
echo "Results: $RESULTS_DIR"

# Run engineer tasks
if [ "$AGENT" = "pai-engineer" ] || [ "$AGENT" = "all" ]; then
  echo ""
  echo "── pai-engineer tasks (first $MAX_TASKS) ──"
  TASK_COUNT=0
  for task in $(ls "$EVAL_DIR/tasks/engineer/"*.txt 2>/dev/null | sort | head -"$MAX_TASKS"); do
    [ -f "$task" ] && run_task "pai-engineer" "$task"
    TASK_COUNT=$((TASK_COUNT + 1))
  done
fi

# Run boss tasks
if [ "$AGENT" = "pai-boss" ] || [ "$AGENT" = "all" ]; then
  echo ""
  echo "── pai-boss tasks (first $MAX_TASKS) ──"
  TASK_COUNT=0
  for task in $(ls "$EVAL_DIR/tasks/boss/"*.txt 2>/dev/null | sort | head -"$MAX_TASKS"); do
    [ -f "$task" ] && run_task "pai-boss" "$task"
    TASK_COUNT=$((TASK_COUNT + 1))
  done
fi

# Run architect tasks
if [ "$AGENT" = "pai-architect" ] || [ "$AGENT" = "all" ]; then
  echo ""
  echo "── pai-architect tasks (first $MAX_TASKS) ──"
  TASK_COUNT=0
  for task in $(ls "$EVAL_DIR/tasks/architect/"*.txt 2>/dev/null | sort | head -"$MAX_TASKS"); do
    [ -f "$task" ] && run_task "pai-architect" "$task"
    TASK_COUNT=$((TASK_COUNT + 1))
  done
fi

# Aggregate score
if [ "$TOTAL_TASKS" -gt 0 ]; then
  AGG_SCORE=$(awk "BEGIN {printf \"%.4f\", $TOTAL_SCORE / $TOTAL_TASKS}")
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
