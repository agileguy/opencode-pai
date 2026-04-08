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
    TEST_COUNT=$(grep -cE "it\(|test\(|describe\(" "$TEST" 2>/dev/null | head -1 || echo 0)
    [ "$TEST_COUNT" -ge 3 ] && pass "E4: ≥3 test cases ($TEST_COUNT found)" || fail "E4: ≥3 test cases ($TEST_COUNT found)"
  else
    fail "E4: ≥3 test cases"
  fi

  # E5. Tests have assertions
  if [ -n "$TEST" ]; then
    ASSERT_COUNT=$(grep -cE "expect|assert|toBe|toEqual|toThrow|toContain" "$TEST" 2>/dev/null | head -1 || echo 0)
    [ "$ASSERT_COUNT" -ge 3 ] && pass "E5: ≥3 assertions ($ASSERT_COUNT found)" || fail "E5: ≥3 assertions ($ASSERT_COUNT found)"
  else
    fail "E5: ≥3 assertions"
  fi

  # E6. Has export (usable module, not just a script)
  [ -n "$IMPL" ] && grep -q "export" "$IMPL" 2>/dev/null && pass "E6: has export" || fail "E6: has export"

  echo "── Quality Metrics ──"

  # Q1. No 'any' type (TypeScript discipline)
  if [ -n "$IMPL" ]; then
    ANY_COUNT=$(grep -cE ": any\b|<any>|as any" "$IMPL" 2>/dev/null | head -1 || echo 0)
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
    HAS_ERROR=$(grep -cE "throw |try \{|catch \(|Error\(|null|undefined" "$IMPL" 2>/dev/null | head -1 || echo 0)
    [ "$HAS_ERROR" -ge 1 ] && pass "Q3: error handling present" || fail "Q3: no error handling"
  else
    fail "Q3: error handling present"
  fi

  # Q4. Edge cases in tests (empty input, null, boundary)
  if [ -n "$TEST" ]; then
    EDGE_CASES=$(grep -ciE "empty|null|undefined|edge|boundary|invalid|throw|error|zero|negative|special" "$TEST" 2>/dev/null | head -1 || echo 0)
    [ "$EDGE_CASES" -ge 2 ] && pass "Q4: edge cases tested ($EDGE_CASES found)" || fail "Q4: insufficient edge cases ($EDGE_CASES found)"
  else
    fail "Q4: edge cases tested"
  fi

  # Q5. Function has type annotations (params and return)
  if [ -n "$IMPL" ]; then
    TYPED_FUNCS=$(grep -cE "function \w+\(.*:.*\).*:" "$IMPL" 2>/dev/null | head -1 || echo 0)
    TYPED_ARROWS=$(grep -cE "const \w+.*=.*\(.*:.*\).*=>|const \w+.*:.*=" "$IMPL" 2>/dev/null | head -1 || echo 0)
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

elif echo "$AGENT" | grep -q "architect"; then

  echo "── Architect Output Metrics ──"

  # Find the output markdown file
  DOC=$(find "$OUTPUT_DIR" -maxdepth 1 -name "*.md" ! -name "README.md" 2>/dev/null | head -1)
  DOC_CONTENT=""
  DOC_LINES=0
  if [ -n "$DOC" ] && [ -s "$DOC" ]; then
    DOC_CONTENT=$(cat "$DOC")
    DOC_LINES=$(wc -l < "$DOC" | tr -d ' ')
  fi

  # A1. Output document exists and is non-empty
  [ -n "$DOC" ] && [ -s "$DOC" ] && pass "A1: design doc exists" || fail "A1: no design doc produced"

  # A2. Has clear structure (markdown headers)
  if [ -n "$DOC_CONTENT" ]; then
    HEADER_COUNT=$(echo "$DOC_CONTENT" | grep -cE "^#{1,3} " 2>/dev/null || echo 0)
    [ "$HEADER_COUNT" -ge 3 ] && pass "A2: structured ($HEADER_COUNT sections)" || fail "A2: poorly structured ($HEADER_COUNT sections)"
  else
    fail "A2: structured document"
  fi

  # A3. Contains trade-off analysis
  if [ -n "$DOC_CONTENT" ]; then
    TRADEOFF=$(echo "$DOC_CONTENT" | grep -ciE "trade.?off|pros? and cons?|advantage|disadvantage|versus|vs\.|compared to|alternative" 2>/dev/null || echo 0)
    [ "$TRADEOFF" -ge 2 ] && pass "A3: trade-off analysis present ($TRADEOFF refs)" || fail "A3: missing trade-off analysis ($TRADEOFF refs)"
  else
    fail "A3: trade-off analysis"
  fi

  # A4. Addresses constraints and requirements
  if [ -n "$DOC_CONTENT" ]; then
    CONSTRAINTS=$(echo "$DOC_CONTENT" | grep -ciE "require|constraint|must|should|limit|boundar|scale|performance|latency|throughput" 2>/dev/null || echo 0)
    [ "$CONSTRAINTS" -ge 3 ] && pass "A4: addresses constraints ($CONSTRAINTS refs)" || fail "A4: ignores constraints ($CONSTRAINTS refs)"
  else
    fail "A4: addresses constraints"
  fi

  # A5. Has concrete recommendation (not just open-ended discussion)
  if [ -n "$DOC_CONTENT" ]; then
    RECOMMEND=$(echo "$DOC_CONTENT" | grep -ciE "recommend|suggest|propose|chosen|decision|conclusion|prefer|best option|go with" 2>/dev/null || echo 0)
    [ "$RECOMMEND" -ge 1 ] && pass "A5: makes a recommendation" || fail "A5: no clear recommendation"
  else
    fail "A5: makes a recommendation"
  fi

  # A6. Reasonable length (not too short, not bloated — 30 to 300 lines)
  if [ -n "$DOC" ]; then
    [ "$DOC_LINES" -ge 30 ] && [ "$DOC_LINES" -le 300 ] && pass "A6: reasonable length ($DOC_LINES lines)" || fail "A6: bad length ($DOC_LINES lines)"
  else
    fail "A6: reasonable length"
  fi

  # A7. No implementation code (stayed in architect lane)
  if [ -n "$DOC_CONTENT" ]; then
    CODE_BLOCKS=$(echo "$DOC_CONTENT" | grep -cE "^(import |const |function |class |export |let |var |async )" 2>/dev/null || echo 0)
    [ "$CODE_BLOCKS" -le 2 ] && pass "A7: no implementation code" || fail "A7: contains implementation code ($CODE_BLOCKS lines)"
  else
    fail "A7: no implementation code"
  fi

  # A8. Considers failure modes or risks
  if [ -n "$DOC_CONTENT" ]; then
    RISKS=$(echo "$DOC_CONTENT" | grep -ciE "fail|risk|edge case|downtime|fallback|degrad|error|disaster|recovery|rollback|mitiga" 2>/dev/null || echo 0)
    [ "$RISKS" -ge 2 ] && pass "A8: failure modes addressed ($RISKS refs)" || fail "A8: missing failure analysis ($RISKS refs)"
  else
    fail "A8: failure modes"
  fi

  echo "── Speed Metrics ──"

  # A9. Fast start (tool call in first 800 chars)
  FIRST_TOOL=$(echo "$STDOUT_CLEAN" | head -c 800 | grep -ciE "→.*Read|→.*Write|→.*Bash" 2>/dev/null || echo 0)
  [ "$FIRST_TOOL" -ge 1 ] && pass "A9: fast start" || fail "A9: slow start"

  # A10. Concise agent output
  if [ -f "$STDOUT_LOG" ]; then
    OUT_SIZE=$(wc -c < "$STDOUT_LOG" | tr -d ' ')
    [ "$OUT_SIZE" -le 50000 ] && pass "A10: concise output (${OUT_SIZE} bytes)" || fail "A10: verbose output (${OUT_SIZE} bytes)"
  else
    pass "A10: concise output (no log)"
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
