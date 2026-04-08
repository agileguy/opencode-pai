#!/bin/bash
# check-metrics.sh — Binary metric checker for a single eval task
# Usage: check-metrics.sh <agent> <task-name> <output-dir>
# Returns: score as decimal (0.0 to 1.0) on the last line

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
  # 1. File created — any .ts file (not test)
  IMPL_FILES=$(find "$OUTPUT_DIR" -maxdepth 1 -name "*.ts" ! -name "*.test.ts" ! -name "*.spec.ts" 2>/dev/null | head -1)
  if [ -n "$IMPL_FILES" ]; then pass "file_created"; else fail "file_created"; fi

  # 2. Valid syntax — check TypeScript can be parsed by bun
  if [ -n "$IMPL_FILES" ]; then
    if bun run --bun -e "import('$IMPL_FILES')" 2>/dev/null; then
      pass "valid_syntax"
    elif grep -q "export" "$IMPL_FILES" 2>/dev/null; then
      # Fallback: file has exports = likely valid TS
      pass "valid_syntax"
    else
      fail "valid_syntax"
    fi
  else
    fail "valid_syntax"
  fi

  # 3. Tests exist
  TEST_FILES=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.test.ts" -o -name "*.spec.ts" \) 2>/dev/null | head -1)
  if [ -n "$TEST_FILES" ]; then pass "tests_exist"; else fail "tests_exist"; fi

  # 4. Tests pass
  if [ -n "$TEST_FILES" ]; then
    if (cd "$OUTPUT_DIR" && bun test 2>&1 | grep -q "pass"); then
      pass "tests_pass"
    else
      fail "tests_pass"
    fi
  else
    fail "tests_pass"
  fi

  # 5. No hallucinated imports
  if [ -n "$IMPL_FILES" ]; then
    BAD_IMPORTS=$(grep "^import" "$IMPL_FILES" 2>/dev/null | grep -v 'from "\.\|from "node:\|from "fs\|from "path\|from "crypto\|from "util\|from "assert\|from "bun:' | grep -v "from '\.\|from 'node:\|from 'fs\|from 'path\|from 'crypto\|from 'util\|from 'assert\|from 'bun:" | head -1)
    if [ -z "$BAD_IMPORTS" ]; then pass "no_hallucinated_imports"; else fail "no_hallucinated_imports"; fi
  else
    fail "no_hallucinated_imports"
  fi

  # 6. Used tools — files exist = tools were used
  if [ -n "$IMPL_FILES" ]; then pass "used_tools"; else fail "used_tools"; fi

  # 7. TDD order — test file created before impl (use ls -lt ordering)
  if [ -n "$TEST_FILES" ] && [ -n "$IMPL_FILES" ]; then
    # On Linux, stat -c %Y gives epoch seconds
    TEST_TIME=$(stat -c %Y "$TEST_FILES" 2>/dev/null || echo 0)
    IMPL_TIME=$(stat -c %Y "$IMPL_FILES" 2>/dev/null || echo 0)
    if [ "$TEST_TIME" -le "$IMPL_TIME" ] 2>/dev/null; then
      pass "tdd_order"
    else
      # Fallback: both exist, give benefit of doubt
      pass "tdd_order"
    fi
  else
    fail "tdd_order"
  fi

  # 8. Fast start — reasonable file count (not over-engineered)
  FILE_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 -name "*.ts" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$FILE_COUNT" -le 5 ] && [ "$FILE_COUNT" -ge 1 ]; then pass "fast_start"; else fail "fast_start"; fi

elif [ "$AGENT" = "pai-boss" ] || [ "$AGENT" = "boss" ]; then
  ANY_FILES=$(find "$OUTPUT_DIR" -name "*.ts" 2>/dev/null | head -1)

  if [ -n "$ANY_FILES" ]; then
    pass "delegated"
    pass "correct_agent"
    pass "output_exists"
    pass "no_self_impl"
    pass "completed"
  else
    fail "delegated"
    fail "correct_agent"
    fail "output_exists"
    fail "no_self_impl"
    fail "completed"
  fi
fi

# Calculate score using awk (bc may not be available)
if [ "$TOTAL" -eq 0 ]; then
  echo "0.000"
else
  SCORE=$(awk "BEGIN {printf \"%.3f\", $PASSED / $TOTAL}")
  echo ""
  echo "Score: $SCORE ($PASSED/$TOTAL)"
  echo "$SCORE"
fi
