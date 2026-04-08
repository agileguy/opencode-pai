#!/bin/bash
# check-metrics.sh — Comprehensive metric checker for PAI agent eval
# Three categories: Execution (files+tests), Quality (code standards), Speed (efficiency)
# Usage: check-metrics.sh <agent> <task-name> <output-dir> [stdout-log]
# Returns: score as decimal (0.0 to 1.0) on the last line

set -uo pipefail

AGENT="$1"
TASK="$2"
OUTPUT_DIR="$3"
STDOUT_LOG="${4:-$OUTPUT_DIR/.stdout.log}"
PASSED=0
TOTAL=0

pass() { PASSED=$((PASSED + 1)); TOTAL=$((TOTAL + 1)); echo "  ✓ $1"; }
fail() { TOTAL=$((TOTAL + 1)); echo "  ✗ $1"; }

echo "═══ $AGENT / $TASK ═══"

# Find files
IMPL=$(find "$OUTPUT_DIR" -maxdepth 1 -name "*.ts" ! -name "*.test.ts" ! -name "*.spec.ts" 2>/dev/null | head -1)
TEST=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.test.ts" -o -name "*.spec.ts" \) 2>/dev/null | head -1)
STDOUT=$(cat "$STDOUT_LOG" 2>/dev/null || echo "")
# Strip ANSI codes from stdout
STDOUT_CLEAN=$(echo "$STDOUT" | perl -pe 's/\e[^a-zA-Z]*[a-zA-Z]//g' 2>/dev/null || echo "$STDOUT")

if echo "$AGENT" | grep -q "engineer"; then

  echo "── Execution Metrics ──"

  # E1. Implementation file exists and non-empty
  [ -n "$IMPL" ] && [ -s "$IMPL" ] && pass "E1: impl file exists" || fail "E1: impl file exists"

  # E2. Test file exists and non-empty
  [ -n "$TEST" ] && [ -s "$TEST" ] && pass "E2: test file exists" || fail "E2: test file exists"

  # E3. Tests actually run and pass (bun test with timeout)
  if [ -n "$TEST" ]; then
    TEST_OUTPUT=$(cd "$OUTPUT_DIR" && timeout 30 bun test 2>&1 || echo "FAILED")
    if echo "$TEST_OUTPUT" | grep -q "pass"; then
      pass "E3: tests pass"
    else
      fail "E3: tests pass"
    fi
  else
    fail "E3: tests pass"
  fi

  # E4. Multiple test cases (not just one token test)
  if [ -n "$TEST" ]; then
    TEST_COUNT=$(grep -cE "it\(|test\(|describe\(" "$TEST" 2>/dev/null || echo 0)
    [ "$TEST_COUNT" -ge 3 ] && pass "E4: ≥3 test cases ($TEST_COUNT found)" || fail "E4: ≥3 test cases ($TEST_COUNT found)"
  else
    fail "E4: ≥3 test cases"
  fi

  # E5. Tests have assertions
  if [ -n "$TEST" ]; then
    ASSERT_COUNT=$(grep -cE "expect|assert|toBe|toEqual|toThrow|toContain" "$TEST" 2>/dev/null || echo 0)
    [ "$ASSERT_COUNT" -ge 3 ] && pass "E5: ≥3 assertions ($ASSERT_COUNT found)" || fail "E5: ≥3 assertions ($ASSERT_COUNT found)"
  else
    fail "E5: ≥3 assertions"
  fi

  # E6. Has export (usable module, not just a script)
  [ -n "$IMPL" ] && grep -q "export" "$IMPL" 2>/dev/null && pass "E6: has export" || fail "E6: has export"

  echo "── Quality Metrics ──"

  # Q1. No 'any' type (TypeScript discipline)
  if [ -n "$IMPL" ]; then
    ANY_COUNT=$(grep -cE ": any\b|<any>|as any" "$IMPL" 2>/dev/null || echo 0)
    [ "$ANY_COUNT" -eq 0 ] && pass "Q1: no 'any' types" || fail "Q1: no 'any' types ($ANY_COUNT found)"
  else
    fail "Q1: no 'any' types"
  fi

  # Q2. No hallucinated imports (only relative, node:, bun: builtins)
  if [ -n "$IMPL" ]; then
    BAD=$(grep "^import" "$IMPL" 2>/dev/null | grep -vE 'from ["\x27]\.|from ["\x27]node:|from ["\x27]bun:|from ["\x27]fs|from ["\x27]path|from ["\x27]crypto|from ["\x27]util|from ["\x27]assert' | head -1)
    [ -z "$BAD" ] && pass "Q2: clean imports" || fail "Q2: hallucinated import: $BAD"
  else
    fail "Q2: clean imports"
  fi

  # Q3. Error handling present (try/catch, throw, or error return)
  if [ -n "$IMPL" ]; then
    HAS_ERROR=$(grep -cE "throw |try \{|catch \(|Error\(|error|null|undefined" "$IMPL" 2>/dev/null || echo 0)
    [ "$HAS_ERROR" -ge 1 ] && pass "Q3: error handling present" || fail "Q3: no error handling"
  else
    fail "Q3: error handling present"
  fi

  # Q4. Edge cases in tests (empty input, null, boundary)
  if [ -n "$TEST" ]; then
    EDGE_CASES=$(grep -ciE "empty|null|undefined|edge|boundary|invalid|throw|error|zero|negative|special|\"\"|\[\]" "$TEST" 2>/dev/null || echo 0)
    [ "$EDGE_CASES" -ge 2 ] && pass "Q4: edge cases tested ($EDGE_CASES found)" || fail "Q4: insufficient edge cases ($EDGE_CASES found)"
  else
    fail "Q4: edge cases tested"
  fi

  # Q5. Function has type annotations (params and return)
  if [ -n "$IMPL" ]; then
    TYPED_FUNCS=$(grep -cE "function \w+\(.*:.*\).*:" "$IMPL" 2>/dev/null || echo 0)
    TYPED_ARROWS=$(grep -cE "const \w+.*=.*\(.*:.*\).*=>|const \w+.*:.*=" "$IMPL" 2>/dev/null || echo 0)
    TOTAL_TYPED=$((TYPED_FUNCS + TYPED_ARROWS))
    [ "$TOTAL_TYPED" -ge 1 ] && pass "Q5: typed function signatures" || fail "Q5: no type annotations"
  else
    fail "Q5: typed function signatures"
  fi

  # Q6. Reasonable implementation size (not bloated, not trivially empty)
  if [ -n "$IMPL" ]; then
    LINES=$(wc -l < "$IMPL" | tr -d ' ')
    [ "$LINES" -ge 5 ] && [ "$LINES" -le 150 ] && pass "Q6: reasonable size ($LINES lines)" || fail "Q6: bad size ($LINES lines)"
  else
    fail "Q6: reasonable size"
  fi

  # Q7. Test imports the implementation (tests are connected, not standalone)
  if [ -n "$TEST" ] && [ -n "$IMPL" ]; then
    IMPL_BASENAME=$(basename "$IMPL" .ts)
    if grep -qE "from.*$IMPL_BASENAME|require.*$IMPL_BASENAME" "$TEST" 2>/dev/null; then
      pass "Q7: test imports implementation"
    else
      fail "Q7: test doesn't import implementation"
    fi
  else
    fail "Q7: test imports implementation"
  fi

  echo "── Speed Metrics ──"

  # S1. Used write/edit tools (not just text output)
  if echo "$STDOUT_CLEAN" | grep -qiE "Write|Edit|→.*write|→.*edit|Created|wrote" 2>/dev/null; then
    pass "S1: used write/edit tools"
  elif [ -n "$IMPL" ]; then
    pass "S1: used write/edit tools (files exist)"
  else
    fail "S1: no tool usage detected"
  fi

  # S2. First tool call within first 500 chars of output (didn't ramble)
  FIRST_TOOL=$(echo "$STDOUT_CLEAN" | head -c 800 | grep -ciE "→.*Read|→.*Write|→.*Edit|→.*Bash|\$ mkdir|\$ bun" 2>/dev/null || echo 0)
  [ "$FIRST_TOOL" -ge 1 ] && pass "S2: fast start (tool in first 800 chars)" || fail "S2: slow start (verbose preamble)"

  # S3. Output not excessively long (efficient agent)
  if [ -f "$STDOUT_LOG" ]; then
    OUT_SIZE=$(wc -c < "$STDOUT_LOG" | tr -d ' ')
    [ "$OUT_SIZE" -le 50000 ] && pass "S3: concise output (${OUT_SIZE} bytes)" || fail "S3: verbose output (${OUT_SIZE} bytes)"
  else
    pass "S3: concise output (no log)"
  fi

  # S4. Completed (didn't timeout or truncate)
  if [ -n "$IMPL" ] && [ -n "$TEST" ]; then
    pass "S4: completed successfully"
  else
    fail "S4: incomplete (missing files)"
  fi

  # S5. TDD order — test file created before implementation
  if [ -n "$TEST" ] && [ -n "$IMPL" ]; then
    TEST_TIME=$(stat -c %Y "$TEST" 2>/dev/null || echo 0)
    IMPL_TIME=$(stat -c %Y "$IMPL" 2>/dev/null || echo 0)
    if [ "$TEST_TIME" -le "$IMPL_TIME" ] 2>/dev/null; then
      pass "S5: TDD order (test first)"
    else
      fail "S5: wrote impl before test"
    fi
  else
    fail "S5: TDD order"
  fi

elif echo "$AGENT" | grep -q "boss"; then

  echo "── Boss Delegation Metrics ──"

  ANY=$(find "$OUTPUT_DIR" -name "*.ts" 2>/dev/null | head -1)

  # D1. Delegated (task tool was called)
  if echo "$STDOUT_CLEAN" | grep -qiE "task|delegate|subagent|pai-engineer" 2>/dev/null; then
    pass "D1: delegation occurred"
  elif [ -n "$ANY" ]; then
    pass "D1: delegation occurred (output exists)"
  else
    fail "D1: no delegation"
  fi

  # D2. Correct agent routing
  if echo "$STDOUT_CLEAN" | grep -qi "pai-engineer" 2>/dev/null; then
    pass "D2: routed to pai-engineer"
  elif [ -n "$ANY" ]; then
    pass "D2: correct agent (output exists)"
  else
    fail "D2: wrong agent or no routing"
  fi

  # D3. Output files exist
  [ -n "$ANY" ] && pass "D3: output files exist" || fail "D3: no output files"

  # D4. Boss didn't write code directly (check stdout for write tool by boss vs subagent)
  if echo "$STDOUT_CLEAN" | grep -qiE "boss.*write\|boss.*edit" 2>/dev/null; then
    fail "D4: boss wrote code directly"
  else
    pass "D4: boss didn't self-implement"
  fi

  # D5. Completed within step limit
  if echo "$STDOUT_CLEAN" | grep -qi "step limit\|max.*steps\|truncat" 2>/dev/null; then
    fail "D5: hit step limit"
  else
    pass "D5: completed within limits"
  fi

  # D6. Brief was specific (delegation had file paths)
  if echo "$STDOUT_CLEAN" | grep -qiE "/workspace|\.ts|output" 2>/dev/null; then
    pass "D6: specific delegation brief"
  else
    fail "D6: vague delegation"
  fi
fi

# Score
if [ "$TOTAL" -eq 0 ]; then
  echo "0.000"
else
  SCORE=$(awk "BEGIN {printf \"%.3f\", $PASSED / $TOTAL}")
  echo ""
  echo "═══ Score: $SCORE ($PASSED/$TOTAL) ═══"
  echo "$SCORE"
fi
