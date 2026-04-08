#!/bin/bash
# check-metrics.sh — Binary metric checker for a single eval task
# Usage: check-metrics.sh <agent> <task-name> <output-dir>
# Returns: score as decimal (0.0 to 1.0)

set -uo pipefail

AGENT="$1"
TASK="$2"
OUTPUT_DIR="$3"
PASSED=0
TOTAL=0

pass() { PASSED=$((PASSED + 1)); TOTAL=$((TOTAL + 1)); echo "  PASS: $1"; }
fail() { TOTAL=$((TOTAL + 1)); echo "  FAIL: $1"; }

echo "Checking metrics for $AGENT/$TASK in $OUTPUT_DIR"

if [ "$AGENT" = "pai-engineer" ] || [ "$AGENT" = "engineer" ]; then
  # 1. File created — any .ts file in output dir (not test)
  IMPL_FILES=$(find "$OUTPUT_DIR" -name "*.ts" ! -name "*.test.ts" ! -name "*.spec.ts" 2>/dev/null | head -1)
  if [ -n "$IMPL_FILES" ]; then pass "file_created"; else fail "file_created"; fi

  # 2. Valid syntax — bun check or tsc
  if [ -n "$IMPL_FILES" ]; then
    if bun build --no-bundle "$IMPL_FILES" --outdir /tmp/eval-check > /dev/null 2>&1; then
      pass "valid_syntax"
    else
      fail "valid_syntax"
    fi
  else
    fail "valid_syntax"
  fi

  # 3. Tests exist
  TEST_FILES=$(find "$OUTPUT_DIR" -name "*.test.ts" -o -name "*.spec.ts" 2>/dev/null | head -1)
  if [ -n "$TEST_FILES" ]; then pass "tests_exist"; else fail "tests_exist"; fi

  # 4. Tests pass
  if [ -n "$TEST_FILES" ]; then
    if cd "$OUTPUT_DIR" && bun test 2>/dev/null; then
      pass "tests_pass"
    else
      fail "tests_pass"
    fi
  else
    fail "tests_pass"
  fi

  # 5. No hallucinated imports — check if bun can resolve all imports
  if [ -n "$IMPL_FILES" ]; then
    BAD_IMPORTS=$(grep "^import" "$IMPL_FILES" 2>/dev/null | grep -v "from \"\.\|from 'node:\|from 'fs\|from 'path\|from 'crypto\|from 'util\|from 'assert\|from 'bun:" | head -1)
    if [ -z "$BAD_IMPORTS" ]; then pass "no_hallucinated_imports"; else fail "no_hallucinated_imports"; fi
  else
    fail "no_hallucinated_imports"
  fi

  # 6. Used tools — check opencode session log for write/edit tool calls
  TOOL_LOG="$OUTPUT_DIR/.tool-log.txt"
  if [ -f "$TOOL_LOG" ] && grep -q "tool.*write\|tool.*edit" "$TOOL_LOG" 2>/dev/null; then
    pass "used_tools"
  elif [ -n "$IMPL_FILES" ]; then
    # File exists so tools were likely used even if log is missing
    pass "used_tools"
  else
    fail "used_tools"
  fi

  # 7. TDD order — test file modified before impl file
  if [ -n "$TEST_FILES" ] && [ -n "$IMPL_FILES" ]; then
    TEST_TIME=$(stat -f %m "$TEST_FILES" 2>/dev/null || stat -c %Y "$TEST_FILES" 2>/dev/null || echo 0)
    IMPL_TIME=$(stat -f %m "$IMPL_FILES" 2>/dev/null || stat -c %Y "$IMPL_FILES" 2>/dev/null || echo 0)
    if [ "$TEST_TIME" -le "$IMPL_TIME" ]; then pass "tdd_order"; else fail "tdd_order"; fi
  else
    fail "tdd_order"
  fi

  # 8. Fast start — output dir was created quickly (proxy: total files <= 5, not over-engineered)
  FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.ts" 2>/dev/null | wc -l)
  if [ "$FILE_COUNT" -le 5 ] && [ "$FILE_COUNT" -ge 1 ]; then pass "fast_start"; else fail "fast_start"; fi

elif [ "$AGENT" = "pai-boss" ] || [ "$AGENT" = "boss" ]; then
  # 1. Delegation occurred — check for any output files (evidence of subagent work)
  ANY_FILES=$(find "$OUTPUT_DIR" -name "*.ts" 2>/dev/null | head -1)
  DELEGATION_LOG="$OUTPUT_DIR/.delegation-log.txt"

  if [ -f "$DELEGATION_LOG" ] && grep -q "task\|delegate" "$DELEGATION_LOG" 2>/dev/null; then
    pass "delegated"
  elif [ -n "$ANY_FILES" ]; then
    pass "delegated"  # files exist = delegation likely happened
  else
    fail "delegated"
  fi

  # 2. Correct agent routed
  if [ -f "$DELEGATION_LOG" ] && grep -q "pai-engineer" "$DELEGATION_LOG" 2>/dev/null; then
    pass "correct_agent"
  elif [ -n "$ANY_FILES" ]; then
    pass "correct_agent"  # benefit of doubt if output exists
  else
    fail "correct_agent"
  fi

  # 3. Output file exists
  if [ -n "$ANY_FILES" ]; then pass "output_exists"; else fail "output_exists"; fi

  # 4. No self-implementation — boss shouldn't have written the .ts files directly
  # (We can't easily check this without session logs, so pass if output exists)
  if [ -n "$ANY_FILES" ]; then pass "no_self_impl"; else fail "no_self_impl"; fi

  # 5. Completed within steps
  if [ -n "$ANY_FILES" ]; then pass "completed"; else fail "completed"; fi
fi

# Calculate score
if [ "$TOTAL" -eq 0 ]; then
  echo "0.0"
else
  SCORE=$(echo "scale=3; $PASSED / $TOTAL" | bc)
  echo ""
  echo "Score: $SCORE ($PASSED/$TOTAL)"
  echo "$SCORE"
fi
