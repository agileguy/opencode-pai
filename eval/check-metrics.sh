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
PASSED_WEIGHT=0
TOTAL_WEIGHT=0

pass() {
  local w="${2:-1}"
  PASSED_WEIGHT=$(awk "BEGIN {print $PASSED_WEIGHT + $w}")
  TOTAL_WEIGHT=$(awk "BEGIN {print $TOTAL_WEIGHT + $w}")
  echo "  ✓ $1 [${w}x]"
}
fail() {
  local w="${2:-1}"
  TOTAL_WEIGHT=$(awk "BEGIN {print $TOTAL_WEIGHT + $w}")
  echo "  ✗ $1 [${w}x]"
}

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
  [ -n "$IMPL" ] && [ -s "$IMPL" ] && pass "E1: impl file exists" 2 || fail "E1: impl file exists" 2

  # E2. Test file exists and non-empty
  [ -n "$TEST" ] && [ -s "$TEST" ] && pass "E2: test file exists" 2 || fail "E2: test file exists" 2

  # E3. Tests actually run and pass (bun test with timeout)
  # Check for bun's actual exit code, not just grepping for "pass" in output
  if [ -n "$TEST" ]; then
    TEST_OUTPUT=$(cd "$OUTPUT_DIR" && timeout 30 bun test 2>&1)
    TEST_EXIT=$?
    if [ "$TEST_EXIT" -eq 0 ] && echo "$TEST_OUTPUT" | grep -qE "[0-9]+ pass"; then
      pass "E3: tests pass" 3
    else
      fail "E3: tests pass" 3
    fi
  else
    fail "E3: tests pass" 3
  fi

  # E4. Multiple test cases (not just one token test)
  if [ -n "$TEST" ]; then
    TEST_COUNT=$(grep -cE "it\(|test\(|describe\(" "$TEST" 2>/dev/null | tr -d '[:space:]' || echo 0)
    [ "$TEST_COUNT" -ge 3 ] && pass "E4: ≥3 test cases ($TEST_COUNT found)" || fail "E4: ≥3 test cases ($TEST_COUNT found)"
  else
    fail "E4: ≥3 test cases"
  fi

  # E5. Tests have assertions
  if [ -n "$TEST" ]; then
    ASSERT_COUNT=$(grep -cE "expect|assert|toBe|toEqual|toThrow|toContain" "$TEST" 2>/dev/null | tr -d '[:space:]' || echo 0)
    [ "$ASSERT_COUNT" -ge 3 ] && pass "E5: ≥3 assertions ($ASSERT_COUNT found)" || fail "E5: ≥3 assertions ($ASSERT_COUNT found)"
  else
    fail "E5: ≥3 assertions"
  fi

  # E6. Has export (usable module, not just a script)
  [ -n "$IMPL" ] && grep -q "export" "$IMPL" 2>/dev/null && pass "E6: has export" 2 || fail "E6: has export" 2

  echo "── Quality Metrics ──"

  # Q1. No 'any' type (TypeScript discipline)
  if [ -n "$IMPL" ]; then
    ANY_COUNT=$(grep -cE ": any\b|<any>|as any" "$IMPL" 2>/dev/null | tr -d '[:space:]' || echo 0)
    [ "$ANY_COUNT" -eq 0 ] && pass "Q1: no 'any' types" || fail "Q1: no 'any' types ($ANY_COUNT found)"
  else
    fail "Q1: no 'any' types"
  fi

  # Q2. No hallucinated imports (only relative, node:, bun: builtins)
  if [ -n "$IMPL" ]; then
    BAD=$(grep "^import" "$IMPL" 2>/dev/null | grep -vE 'from ["\x27]\.|from ["\x27]node:|from ["\x27]bun:|from ["\x27]fs|from ["\x27]path|from ["\x27]crypto|from ["\x27]util|from ["\x27]assert|from ["\x27]events|from ["\x27]stream|from ["\x27]http|from ["\x27]os|from ["\x27]url|from ["\x27]buffer|from ["\x27]zlib' | head -1)
    [ -z "$BAD" ] && pass "Q2: clean imports" || fail "Q2: hallucinated import: $BAD"
  else
    fail "Q2: clean imports"
  fi

  # Q3. Error handling present (try/catch, throw, or error return)
  if [ -n "$IMPL" ]; then
    HAS_ERROR=$(grep -cE "throw |try \{|catch \(|Error\(|null|undefined" "$IMPL" 2>/dev/null | tr -d '[:space:]' || echo 0)
    [ "$HAS_ERROR" -ge 1 ] && pass "Q3: error handling present" || fail "Q3: no error handling"
  else
    fail "Q3: error handling present"
  fi

  # Q4. Edge cases in tests (empty input, null, boundary)
  # Check both test descriptions AND actual edge case values in assertions
  if [ -n "$TEST" ]; then
    EDGE_DESC=$(grep -ciE "empty|null|undefined|edge|boundary|invalid|throw|error|zero|negative|special" "$TEST" 2>/dev/null | tr -d '[:space:]' || echo 0)
    EDGE_VALUES=$(grep -cE '""|\[\]|\{\}|null|undefined|NaN|Infinity|-1|0\b' "$TEST" 2>/dev/null | tr -d '[:space:]' || echo 0)
    EDGE_TOTAL=$((EDGE_DESC + EDGE_VALUES))
    [ "$EDGE_TOTAL" -ge 3 ] && pass "Q4: edge cases tested ($EDGE_DESC desc + $EDGE_VALUES values)" || fail "Q4: insufficient edge cases ($EDGE_TOTAL found, need 3)"
  else
    fail "Q4: edge cases tested"
  fi

  # Q5. Function has type annotations (params and return)
  if [ -n "$IMPL" ]; then
    TYPED_FUNCS=$(grep -cE "function \w+\(.*:.*\).*:" "$IMPL" 2>/dev/null | tr -d '[:space:]' || echo 0)
    TYPED_ARROWS=$(grep -cE "const \w+.*=.*\(.*:.*\).*=>|const \w+.*:.*=" "$IMPL" 2>/dev/null | tr -d '[:space:]' || echo 0)
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
      pass "Q7: test imports implementation" 2
    else
      fail "Q7: test doesn't import implementation" 2
    fi
  else
    fail "Q7: test imports implementation" 2
  fi

  # Q8. Tests actually call the implementation (not just asserting constants)
  if [ -n "$TEST" ] && [ -n "$IMPL" ]; then
    IMPL_BASENAME=$(basename "$IMPL" .ts)
    # Count function calls from the imported module in test assertions/expects
    FUNC_CALLS=$(grep -cE "$IMPL_BASENAME|expect\(.*\(" "$TEST" 2>/dev/null | tr -d '[:space:]' || echo 0)
    TRIVIAL_ASSERTS=$(grep -cE "expect\(true\)|expect\(1\)|expect\(false\)|expect\(0\)" "$TEST" 2>/dev/null | tr -d '[:space:]' || echo 0)
    if [ "$FUNC_CALLS" -ge 2 ] && [ "$TRIVIAL_ASSERTS" -le 1 ]; then
      pass "Q8: tests exercise implementation ($FUNC_CALLS calls, $TRIVIAL_ASSERTS trivial)"
    else
      fail "Q8: tests may be trivial ($FUNC_CALLS calls, $TRIVIAL_ASSERTS trivial)"
    fi
  else
    fail "Q8: tests exercise implementation"
  fi

  # Q9. No console.log left in implementation (clean production code)
  if [ -n "$IMPL" ]; then
    LOG_COUNT=$(grep -cE "console\.(log|debug|info)" "$IMPL" 2>/dev/null | tr -d '[:space:]' || echo 0)
    [ "$LOG_COUNT" -eq 0 ] && pass "Q9: no console.log in impl" || fail "Q9: console.log in impl ($LOG_COUNT found)"
  else
    fail "Q9: no console.log in impl"
  fi

  # Q10. No duplicate code between impl and test
  if [ -n "$IMPL" ] && [ -n "$TEST" ]; then
    # Extract 4-line blocks from impl, check if they exist in test
    DUPES=0
    # Simple approach: check if any function body from impl is copy-pasted into test
    IMPL_FUNCS=$(grep -E "^(export )?(async )?function |^const \w+ = " "$IMPL" 2>/dev/null | wc -l | tr -d '[:space:]')
    TEST_IMPL_CODE=$(grep -cE "^(export )?(async )?function |^const \w+ = .*=>" "$TEST" 2>/dev/null | tr -d '[:space:]' || echo 0)
    # If test has implementation-style function declarations (not imports), it might be copy-paste
    [ "$TEST_IMPL_CODE" -le 1 ] && pass "Q10: no duplicate code" || fail "Q10: possible copy-paste ($TEST_IMPL_CODE impl-style declarations in test)"
  else
    fail "Q10: no duplicate code"
  fi

  # Q11. Exported function matches task expectation
  if [ -n "$IMPL" ]; then
    case "$TASK" in
      01-palindrome) EXPECTED="isPalindrome" ;;
      02-debounce) EXPECTED="debounce" ;;
      03-csv2json) EXPECTED="csvToJson" ;;
      04-fix-sort) EXPECTED="sort" ;;
      05-stack) EXPECTED="Stack" ;;
      06-linked-list) EXPECTED="LinkedList" ;;
      07-retry) EXPECTED="retry" ;;
      08-event-emitter) EXPECTED="EventEmitter" ;;
      09-lru-cache) EXPECTED="LRUCache" ;;
      10-validator) EXPECTED="Schema\|Validator\|validate" ;;
      11-promise-pool) EXPECTED="PromisePool\|promisePool" ;;
      12-json-diff) EXPECTED="deepDiff\|jsonDiff" ;;
      13-cli-parser) EXPECTED="parseArgs\|parseCliArgs" ;;
      14-rate-limiter) EXPECTED="RateLimiter\|rateLimiter\|TokenBucket" ;;
      15-dependency-graph) EXPECTED="DependencyGraph\|dependencyGraph" ;;
      *) EXPECTED="" ;;
    esac
    if [ -n "$EXPECTED" ]; then
      if grep -qE "export.*(${EXPECTED})" "$IMPL" 2>/dev/null; then
        pass "Q11: exports expected name ($EXPECTED)"
      else
        fail "Q11: missing expected export ($EXPECTED)"
      fi
    else
      pass "Q11: no expected name (unknown task)"
    fi
  else
    fail "Q11: function name matches task"
  fi

  echo "── Speed Metrics ──"

  # S1. Used write/edit tools (not just text output)
  if echo "$STDOUT_CLEAN" | grep -qiE "Write|Edit|→.*write|→.*edit|Created|wrote" 2>/dev/null; then
    pass "S1: used write/edit tools" 0.5
  elif [ -n "$IMPL" ]; then
    pass "S1: used write/edit tools (files exist)" 0.5
  else
    fail "S1: no tool usage detected" 0.5
  fi

  # S2. First tool call within first 500 chars of output (didn't ramble)
  FIRST_TOOL=$(echo "$STDOUT_CLEAN" | head -c 800 | grep -ciE "→.*Read|→.*Write|→.*Edit|→.*Bash|\$ mkdir|\$ bun" 2>/dev/null | tr -d '[:space:]' || echo 0)
  [ "$FIRST_TOOL" -ge 1 ] && pass "S2: fast start (tool in first 800 chars)" 0.5 || fail "S2: slow start (verbose preamble)" 0.5

  # S3. Output not excessively long (efficient agent)
  if [ -f "$STDOUT_LOG" ]; then
    OUT_SIZE=$(wc -c < "$STDOUT_LOG" | tr -d ' ')
    [ "$OUT_SIZE" -le 50000 ] && pass "S3: concise output (${OUT_SIZE} bytes)" 0.5 || fail "S3: verbose output (${OUT_SIZE} bytes)" 0.5
  else
    pass "S3: concise output (no log)" 0.5
  fi

  # S4. Completed (didn't timeout or truncate)
  if [ -n "$IMPL" ] && [ -n "$TEST" ]; then
    pass "S4: completed successfully" 0.5
  else
    fail "S4: incomplete (missing files)" 0.5
  fi

  # S5. TDD order — test file created before implementation
  if [ -n "$TEST" ] && [ -n "$IMPL" ]; then
    TEST_TIME=$(stat -c %Y "$TEST" 2>/dev/null || echo 0)
    IMPL_TIME=$(stat -c %Y "$IMPL" 2>/dev/null || echo 0)
    if [ "$TEST_TIME" -le "$IMPL_TIME" ] 2>/dev/null; then
      pass "S5: TDD order (test first)" 2
    else
      fail "S5: wrote impl before test" 2
    fi
  else
    fail "S5: TDD order" 2
  fi

  # --- E7: Tests cover happy + sad paths (weight 2) ---
  SAD_PATH_COUNT=$(grep -cE '(throw|Error|reject|rejects|toThrow)' "$TEST" 2>/dev/null | tr -d '[:space:]')
  HAPPY_PATH_COUNT=$(grep -cE '(toBe|toEqual|toContain|toMatch|toBeTruthy|toBeDefined|toHaveLength)' "$TEST" 2>/dev/null | tr -d '[:space:]')
  SAD_PATH_COUNT=${SAD_PATH_COUNT:-0}
  HAPPY_PATH_COUNT=${HAPPY_PATH_COUNT:-0}
  if [ "$SAD_PATH_COUNT" -ge 1 ] && [ "$HAPPY_PATH_COUNT" -ge 2 ]; then
    pass "E7: Tests cover happy + sad paths (${HAPPY_PATH_COUNT} happy, ${SAD_PATH_COUNT} sad)" 2
  else
    fail "E7: Tests cover happy + sad paths (${HAPPY_PATH_COUNT} happy, ${SAD_PATH_COUNT} sad — need >=2 happy, >=1 sad)" 2
  fi

  # --- Q12: No hardcoded test values in impl (weight 1) ---
  HARDCODED_HITS=0
  if [ -f "$TEST" ] && [ -f "$IMPL" ]; then
    LITERALS=$(grep -oE "(toBe|toEqual)\([\"'][^\"']+[\"']" "$TEST" 2>/dev/null \
      | sed "s/.*[\"']//;s/[\"']$//" \
      | sort -u)
    if [ -n "$LITERALS" ]; then
      while IFS= read -r lit; do
        [ -z "$lit" ] && continue
        COUNT=$(grep -cF "$lit" "$IMPL" 2>/dev/null | tr -d '[:space:]')
        COUNT=${COUNT:-0}
        HARDCODED_HITS=$((HARDCODED_HITS + COUNT))
      done <<< "$LITERALS"
    fi
  fi
  if [ "$HARDCODED_HITS" -le 3 ]; then
    pass "Q12: No hardcoded test values in impl (${HARDCODED_HITS} matches)" 1
  else
    fail "Q12: Hardcoded test values found in impl (${HARDCODED_HITS} matches — max 3)" 1
  fi

  # --- Q13: Consistent naming convention (weight 1) ---
  EXPORT_NAMES=$(grep -oE 'export\s+(const|function|class|type|interface)\s+[A-Za-z_][A-Za-z0-9_]*' "$IMPL" 2>/dev/null \
    | awk '{print $NF}')
  NAMING_OK=true
  if [ -n "$EXPORT_NAMES" ]; then
    while IFS= read -r name; do
      [ -z "$name" ] && continue
      if echo "$name" | grep -qE '^[a-z][a-zA-Z0-9]*$' 2>/dev/null; then
        : # camelCase — valid for functions/consts
      elif echo "$name" | grep -qE '^[A-Z][a-zA-Z0-9]*$' 2>/dev/null; then
        : # PascalCase — valid for classes/types/interfaces
      else
        NAMING_OK=false
      fi
    done <<< "$EXPORT_NAMES"
  fi
  if [ "$NAMING_OK" = true ] && [ -n "$EXPORT_NAMES" ]; then
    pass "Q13: Consistent naming convention (camelCase/PascalCase exports)" 1
  else
    fail "Q13: Inconsistent naming convention in exports" 1
  fi

  # --- Q14: Test descriptions are meaningful (weight 1) ---
  BAD_DESCRIPTIONS=0
  TOTAL_DESCRIPTIONS=0
  if [ -f "$TEST" ]; then
    DESCRIPTIONS=$(grep -oE "(test|it)\([\"'][^\"']*[\"']" "$TEST" 2>/dev/null \
      | sed "s/^[^\"']*[\"']//;s/[\"']$//" )
    if [ -n "$DESCRIPTIONS" ]; then
      while IFS= read -r desc; do
        [ -z "$desc" ] && continue
        TOTAL_DESCRIPTIONS=$((TOTAL_DESCRIPTIONS + 1))
        DESC_LEN=${#desc}
        if [ "$DESC_LEN" -lt 10 ]; then
          BAD_DESCRIPTIONS=$((BAD_DESCRIPTIONS + 1))
        elif echo "$desc" | grep -qE '^test [0-9]+$' 2>/dev/null; then
          BAD_DESCRIPTIONS=$((BAD_DESCRIPTIONS + 1))
        fi
      done <<< "$DESCRIPTIONS"
    fi
  fi
  if [ "$BAD_DESCRIPTIONS" -eq 0 ] && [ "$TOTAL_DESCRIPTIONS" -gt 0 ]; then
    pass "Q14: Test descriptions are meaningful (${TOTAL_DESCRIPTIONS} tests, all descriptive)" 1
  elif [ "$TOTAL_DESCRIPTIONS" -eq 0 ]; then
    fail "Q14: Test descriptions are meaningful (no test descriptions found)" 1
  else
    fail "Q14: Test descriptions are meaningful (${BAD_DESCRIPTIONS}/${TOTAL_DESCRIPTIONS} are too short or generic)" 1
  fi

  # --- S6: No unnecessary reads (weight 0.5) ---
  READ_COUNT=$(grep -c '→ Read' "$STDOUT_LOG" 2>/dev/null | tr -d '[:space:]')
  READ_COUNT=${READ_COUNT:-0}
  if [ "$READ_COUNT" -le 5 ]; then
    pass "S6: No unnecessary reads (${READ_COUNT} reads)" 0.5
  else
    fail "S6: Too many file reads (${READ_COUNT} — max 5)" 0.5
  fi

  # --- S7: Single implementation attempt (weight 0.5) ---
  IMPL_BASENAME=$(basename "$IMPL" 2>/dev/null)
  IMPL_BASENAME=${IMPL_BASENAME:-"__NO_IMPL__"}
  WRITE_COUNT=$(grep -c "→ Write.*${IMPL_BASENAME}" "$STDOUT_LOG" 2>/dev/null | tr -d '[:space:]')
  WRITE_COUNT=${WRITE_COUNT:-0}
  if [ "$WRITE_COUNT" -le 2 ]; then
    pass "S7: Single implementation attempt (${WRITE_COUNT} writes to impl)" 0.5
  else
    fail "S7: Multiple implementation attempts (${WRITE_COUNT} writes — max 2)" 0.5
  fi

elif echo "$AGENT" | grep -q "boss"; then

  echo "── Boss Delegation Metrics ──"

  ANY=$(find "$OUTPUT_DIR" -name "*.ts" 2>/dev/null | head -1)

  # D1. Delegated (task tool was called)
  if echo "$STDOUT_CLEAN" | grep -qiE "task|delegate|subagent|pai-engineer" 2>/dev/null; then
    pass "D1: delegation occurred" 3
  elif [ -n "$ANY" ]; then
    pass "D1: delegation occurred (output exists)" 3
  else
    fail "D1: no delegation" 3
  fi

  # D2. Correct agent routing
  if echo "$STDOUT_CLEAN" | grep -qi "pai-engineer" 2>/dev/null; then
    pass "D2: routed to pai-engineer" 2
  elif [ -n "$ANY" ]; then
    pass "D2: correct agent (output exists)" 2
  else
    fail "D2: wrong agent or no routing" 2
  fi

  # D3. Output files exist
  [ -n "$ANY" ] && pass "D3: output files exist" 3 || fail "D3: no output files" 3

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
    pass "D6: specific delegation brief" 2
  else
    fail "D6: vague delegation" 2
  fi

  # D7. Verified output (read the file after delegation)
  if echo "$STDOUT_CLEAN" | grep -qiE "→.*Read.*output\|reading.*output\|verified\|checking.*output" 2>/dev/null; then
    pass "D7: verified output"
  elif echo "$STDOUT_CLEAN" | grep -qiE "Read.*\.ts\|cat.*\.ts" 2>/dev/null; then
    pass "D7: verified output (read file)"
  else
    fail "D7: no verification step"
  fi

  # --- D8: Delegated output has tests (weight 3) ---
  TEST_FILES_FOUND=$(find "$OUTPUT_DIR" -name "*.test.ts" -type f 2>/dev/null | head -5)
  if [ -n "$TEST_FILES_FOUND" ]; then
    TEST_FILE_COUNT=$(echo "$TEST_FILES_FOUND" | wc -l | tr -d '[:space:]')
    pass "D8: Delegated output has tests (${TEST_FILE_COUNT} test file(s))" 3
  else
    fail "D8: Delegated output has tests (no .test.ts files found)" 3
  fi

  # --- D9: Delegated tests pass (weight 3) ---
  if [ -n "$TEST_FILES_FOUND" ]; then
    TEST_OUTPUT=$(cd "$OUTPUT_DIR" && timeout 30 bun test 2>&1)
    TEST_EXIT=$?
    if [ "$TEST_EXIT" -eq 0 ] && echo "$TEST_OUTPUT" | grep -qi 'pass' 2>/dev/null; then
      pass "D9: Delegated tests pass" 3
    else
      fail "D9: Delegated tests fail (exit code ${TEST_EXIT})" 3
    fi
  else
    fail "D9: Delegated tests pass (no tests to run)" 3
  fi

  # --- D10: Task decomposition <= 5 steps (weight 1) ---
  STEP_COUNT=$(echo "$STDOUT_CLEAN" | grep -cE '(Task [0-9]|Step [0-9]|^[0-9]+\.)' 2>/dev/null | tr -d '[:space:]')
  STEP_COUNT=${STEP_COUNT:-0}
  if [ "$STEP_COUNT" -le 5 ]; then
    pass "D10: Task decomposition <= 5 steps (${STEP_COUNT} steps)" 1
  else
    fail "D10: Task decomposition too granular (${STEP_COUNT} steps — max 5)" 1
  fi

  # --- D11: No repeated delegation (weight 1) ---
  DELEGATION_COUNT=$(echo "$STDOUT_CLEAN" | grep -ciE 'pai-engineer' 2>/dev/null | tr -d '[:space:]')
  DELEGATION_COUNT=${DELEGATION_COUNT:-0}
  if [ "$DELEGATION_COUNT" -le 4 ]; then
    pass "D11: No repeated delegation (${DELEGATION_COUNT} engineer mentions)" 1
  else
    fail "D11: Repeated delegation detected (${DELEGATION_COUNT} engineer mentions — max 4)" 1
  fi

  # --- D12: Delegation includes constraints (weight 2) ---
  HAS_CONSTRAINTS=$(echo "$STDOUT_CLEAN" | grep -ciE '(TDD|test|export|output)' 2>/dev/null | tr -d '[:space:]')
  HAS_CONSTRAINTS=${HAS_CONSTRAINTS:-0}
  if [ "$HAS_CONSTRAINTS" -ge 1 ]; then
    pass "D12: Delegation includes constraints (${HAS_CONSTRAINTS} constraint keywords)" 2
  else
    fail "D12: Delegation missing constraints (no TDD/test/export/output keywords)" 2
  fi

  # --- D13: All delegations specify output path (weight 1) ---
  HAS_OUTPUT_PATH=$(echo "$STDOUT_CLEAN" | grep -ciE '(/workspace|output)' 2>/dev/null | tr -d '[:space:]')
  HAS_OUTPUT_PATH=${HAS_OUTPUT_PATH:-0}
  if [ "$HAS_OUTPUT_PATH" -ge 1 ]; then
    pass "D13: Delegations specify output path" 1
  else
    fail "D13: Delegations missing output path specification" 1
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
  [ -n "$DOC" ] && [ -s "$DOC" ] && pass "A1: design doc exists" 3 || fail "A1: no design doc produced" 3

  # A2. Has clear structure (markdown headers)
  if [ -n "$DOC_CONTENT" ]; then
    HEADER_COUNT=$(echo "$DOC_CONTENT" | grep -cE "^#{1,3} " 2>/dev/null | tr -d '[:space:]')
    [ -z "$HEADER_COUNT" ] && HEADER_COUNT=0
    [ "$HEADER_COUNT" -ge 3 ] && pass "A2: structured ($HEADER_COUNT sections)" 2 || fail "A2: poorly structured ($HEADER_COUNT sections)" 2
  else
    fail "A2: structured document" 2
  fi

  # A3. Contains trade-off analysis
  if [ -n "$DOC_CONTENT" ]; then
    TRADEOFF=$(echo "$DOC_CONTENT" | grep -ciE "trade.?off|pros? and cons?|advantage|disadvantage|versus|vs\.|compared to|alternative" 2>/dev/null | tr -d '[:space:]')
    [ -z "$TRADEOFF" ] && TRADEOFF=0
    [ "$TRADEOFF" -ge 2 ] && pass "A3: trade-off analysis present ($TRADEOFF refs)" 3 || fail "A3: missing trade-off analysis ($TRADEOFF refs)" 3
  else
    fail "A3: trade-off analysis" 3
  fi

  # A4. Addresses constraints and requirements
  if [ -n "$DOC_CONTENT" ]; then
    CONSTRAINTS=$(echo "$DOC_CONTENT" | grep -ciE "require|constraint|must|should|limit|boundar|scale|performance|latency|throughput" 2>/dev/null | tr -d '[:space:]')
    [ -z "$CONSTRAINTS" ] && CONSTRAINTS=0
    [ "$CONSTRAINTS" -ge 3 ] && pass "A4: addresses constraints ($CONSTRAINTS refs)" 2 || fail "A4: ignores constraints ($CONSTRAINTS refs)" 2
  else
    fail "A4: addresses constraints" 2
  fi

  # A5. Has concrete recommendation (not just open-ended discussion)
  if [ -n "$DOC_CONTENT" ]; then
    RECOMMEND=$(echo "$DOC_CONTENT" | grep -ciE "recommend|suggest|propose|chosen|decision|conclusion|prefer|best option|go with" 2>/dev/null | tr -d '[:space:]')
    [ -z "$RECOMMEND" ] && RECOMMEND=0
    [ "$RECOMMEND" -ge 1 ] && pass "A5: makes a recommendation" 3 || fail "A5: no clear recommendation" 3
  else
    fail "A5: makes a recommendation" 3
  fi

  # A6. Reasonable length (not too short, not bloated — 30 to 300 lines)
  if [ -n "$DOC" ]; then
    [ "$DOC_LINES" -ge 30 ] && [ "$DOC_LINES" -le 300 ] && pass "A6: reasonable length ($DOC_LINES lines)" || fail "A6: bad length ($DOC_LINES lines)"
  else
    fail "A6: reasonable length"
  fi

  # A7. No implementation code (stayed in architect lane)
  if [ -n "$DOC_CONTENT" ]; then
    CODE_BLOCKS=$(echo "$DOC_CONTENT" | grep -cE "^(import |const |function |class |export |let |var |async )" 2>/dev/null | tr -d '[:space:]' || echo 0)
    [ -z "$CODE_BLOCKS" ] && CODE_BLOCKS=0
    [ "$CODE_BLOCKS" -le 2 ] && pass "A7: no implementation code" || fail "A7: contains implementation code ($CODE_BLOCKS lines)"
  else
    fail "A7: no implementation code"
  fi

  # A8. Considers failure modes or risks
  if [ -n "$DOC_CONTENT" ]; then
    RISKS=$(echo "$DOC_CONTENT" | grep -ciE "fail|risk|edge case|downtime|fallback|degrad|error|disaster|recovery|rollback|mitiga" 2>/dev/null | tr -d '[:space:]')
    [ -z "$RISKS" ] && RISKS=0
    [ "$RISKS" -ge 2 ] && pass "A8: failure modes addressed ($RISKS refs)" 2 || fail "A8: missing failure analysis ($RISKS refs)" 2
  else
    fail "A8: failure modes" 2
  fi

  echo "── Speed Metrics ──"

  # A9. Fast start (tool call in first 800 chars)
  FIRST_TOOL=$(echo "$STDOUT_CLEAN" | head -c 800 | grep -ciE "→.*Read|→.*Write|→.*Bash" 2>/dev/null | tr -d '[:space:]' || echo 0)
  [ -z "$FIRST_TOOL" ] && FIRST_TOOL=0
  [ "$FIRST_TOOL" -ge 1 ] && pass "A9: fast start" || fail "A9: slow start"

  # A10. Concise agent output
  if [ -f "$STDOUT_LOG" ]; then
    OUT_SIZE=$(wc -c < "$STDOUT_LOG" | tr -d ' ')
    [ "$OUT_SIZE" -le 50000 ] && pass "A10: concise output (${OUT_SIZE} bytes)" || fail "A10: verbose output (${OUT_SIZE} bytes)"
  else
    pass "A10: concise output (no log)"
  fi

  # A11. Contains quantitative estimates
  if [ -n "$DOC_CONTENT" ]; then
    QUANT=$(echo "$DOC_CONTENT" | grep -ciE "[0-9]+\s*(ms|seconds?|minutes?|hours?|req|requests?|qps|tps|%|percent|GB|MB|KB|rows?|records?|users?|connections?)" 2>/dev/null | tr -d '[:space:]')
    [ -z "$QUANT" ] && QUANT=0
    [ "$QUANT" -ge 3 ] && pass "A11: quantitative estimates ($QUANT found)" || fail "A11: lacks quantitative data ($QUANT found, need 3)"
  else
    fail "A11: quantitative estimates"
  fi

  # A12. Contains table or structured comparison
  if [ -n "$DOC_CONTENT" ]; then
    TABLES=$(echo "$DOC_CONTENT" | grep -cE "^\|.*\|.*\|" 2>/dev/null | tr -d '[:space:]')
    [ -z "$TABLES" ] && TABLES=0
    [ "$TABLES" -ge 3 ] && pass "A12: structured comparison ($TABLES table rows)" || fail "A12: no structured comparison"
  else
    fail "A12: structured comparison"
  fi

  # --- A13: Options section has >= 2 distinct options (weight 2) ---
  OPTION_COUNT=0
  if [ -n "$DOC_CONTENT" ]; then
    HEADER_OPTIONS=$(echo "$DOC_CONTENT" | grep -ciE '^#{2,3}\s.*(Option|Approach|Strategy|Alternative)' 2>/dev/null | tr -d '[:space:]')
    NUMBERED_OPTIONS=$(echo "$DOC_CONTENT" | grep -cE '^\s*[0-9]+\.\s' 2>/dev/null | tr -d '[:space:]')
    HEADER_OPTIONS=${HEADER_OPTIONS:-0}
    NUMBERED_OPTIONS=${NUMBERED_OPTIONS:-0}
    if [ "$HEADER_OPTIONS" -ge "$NUMBERED_OPTIONS" ]; then
      OPTION_COUNT=$HEADER_OPTIONS
    else
      OPTION_COUNT=$NUMBERED_OPTIONS
    fi
  fi
  if [ "$OPTION_COUNT" -ge 2 ]; then
    pass "A13: Options section has >= 2 distinct options (${OPTION_COUNT} found)" 2
  else
    fail "A13: Options section needs >= 2 options (${OPTION_COUNT} found)" 2
  fi

  # --- A14: Each option has pros AND cons (weight 2) ---
  HAS_PROS=$(echo "$DOC_CONTENT" | grep -ciE '(pro|advantage|benefit|strength)' 2>/dev/null | tr -d '[:space:]')
  HAS_CONS=$(echo "$DOC_CONTENT" | grep -ciE '(con|disadvantage|drawback|weakness|trade.?off)' 2>/dev/null | tr -d '[:space:]')
  HAS_PROS=${HAS_PROS:-0}
  HAS_CONS=${HAS_CONS:-0}
  if [ "$HAS_PROS" -ge 1 ] && [ "$HAS_CONS" -ge 1 ]; then
    pass "A14: Options have pros AND cons (${HAS_PROS} pro refs, ${HAS_CONS} con refs)" 2
  else
    fail "A14: Missing pros or cons analysis (pros: ${HAS_PROS}, cons: ${HAS_CONS})" 2
  fi

  # --- A15: Recommendation references an option (weight 1) ---
  RECOMMEND_SECTION=$(echo "$DOC_CONTENT" | sed -n '/[Rr]ecommend/,/^##/p' 2>/dev/null)
  if [ -n "$RECOMMEND_SECTION" ]; then
    REFS_OPTION=$(echo "$RECOMMEND_SECTION" | grep -ciE '(option|approach|[1-3])' 2>/dev/null | tr -d '[:space:]')
    REFS_OPTION=${REFS_OPTION:-0}
    if [ "$REFS_OPTION" -ge 1 ]; then
      pass "A15: Recommendation references a specific option" 1
    else
      fail "A15: Recommendation does not reference a specific option" 1
    fi
  else
    fail "A15: No recommendation section found" 1
  fi

  # --- A16: No unsupported claims (weight 1) ---
  BARE_CLAIMS=0
  if [ -n "$DOC_CONTENT" ]; then
    NUMERIC_LINES=$(echo "$DOC_CONTENT" | grep -nE '[0-9]+(x|ms|%|MB|GB|KB)' 2>/dev/null)
    if [ -n "$NUMERIC_LINES" ]; then
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        if ! echo "$line" | grep -qiE '(because|assuming|given|based on|approximately|about|around|roughly|estimated|typically)' 2>/dev/null; then
          BARE_CLAIMS=$((BARE_CLAIMS + 1))
        fi
      done <<< "$NUMERIC_LINES"
    fi
  fi
  if [ "$BARE_CLAIMS" -le 5 ]; then
    pass "A16: No unsupported claims (${BARE_CLAIMS} bare numeric claims)" 1
  else
    fail "A16: Unsupported numeric claims (${BARE_CLAIMS} — max 5 without context)" 1
  fi

  # --- A17: Migration/implementation section present (weight 2) ---
  HAS_MIGRATION=$(echo "$DOC_CONTENT" | grep -ciE '^#{2,3}\s.*(migrat|implement|rollout|deploy|transition|plan)' 2>/dev/null | tr -d '[:space:]')
  HAS_MIGRATION=${HAS_MIGRATION:-0}
  if [ "$HAS_MIGRATION" -ge 1 ]; then
    pass "A17: Migration/implementation section present" 2
  else
    fail "A17: Missing migration/implementation section" 2
  fi

  # --- A18: Security considerations for auth tasks (weight 2) ---
  if echo "$TASK" | grep -qi 'auth' 2>/dev/null; then
    SEC_MENTIONS=$(echo "$DOC_CONTENT" | grep -ciE '(security|identity|permission|encrypt|token|oauth|jwt|credential|access control)' 2>/dev/null | tr -d '[:space:]')
    SEC_MENTIONS=${SEC_MENTIONS:-0}
    if [ "$SEC_MENTIONS" -ge 3 ]; then
      pass "A18: Security considerations for auth task (${SEC_MENTIONS} security references)" 2
    else
      fail "A18: Insufficient security coverage for auth task (${SEC_MENTIONS} refs — need >= 3)" 2
    fi
  else
    pass "A18: Security considerations (N/A — not an auth task)" 2
  fi

fi

# Score
if [ "$(awk "BEGIN {print ($TOTAL_WEIGHT == 0)}")" -eq 1 ]; then
  echo "0.000"
else
  SCORE=$(awk "BEGIN {printf \"%.3f\", $PASSED_WEIGHT / $TOTAL_WEIGHT}")
  echo ""
  echo "═══ Score: $SCORE (weight ${PASSED_WEIGHT}/${TOTAL_WEIGHT}) ═══"
  echo "$SCORE"
fi
