#!/bin/bash
# check-metrics.sh — Binary metric checker for a single eval task
# Usage: check-metrics.sh <agent> <task-name> <output-dir>
# Returns: score as decimal (0.0 to 1.0) on the last line
# Designed to be fast and never hang — no test execution, just static checks

set -uo pipefail

AGENT="$1"
TASK="$2"
OUTPUT_DIR="$3"
PASSED=0
TOTAL=0

pass() { PASSED=$((PASSED + 1)); TOTAL=$((TOTAL + 1)); echo "  PASS: $1"; }
fail() { TOTAL=$((TOTAL + 1)); echo "  FAIL: $1"; }

echo "Checking: $AGENT/$TASK in $OUTPUT_DIR"

if echo "$AGENT" | grep -q "engineer"; then
  # Find impl and test files
  IMPL=$(find "$OUTPUT_DIR" -maxdepth 1 -name "*.ts" ! -name "*.test.ts" ! -name "*.spec.ts" 2>/dev/null | head -1)
  TEST=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.test.ts" -o -name "*.spec.ts" \) 2>/dev/null | head -1)

  # 1. Implementation file exists
  [ -n "$IMPL" ] && [ -s "$IMPL" ] && pass "file_created" || fail "file_created"

  # 2. Has export (proxy for valid TS)
  [ -n "$IMPL" ] && grep -q "export" "$IMPL" 2>/dev/null && pass "has_export" || fail "has_export"

  # 3. Test file exists
  [ -n "$TEST" ] && [ -s "$TEST" ] && pass "tests_exist" || fail "tests_exist"

  # 4. Test has assertions (expect/assert/assertEquals)
  [ -n "$TEST" ] && grep -qE "expect|assert|assertEquals" "$TEST" 2>/dev/null && pass "tests_have_assertions" || fail "tests_have_assertions"

  # 5. No hallucinated imports (no npm packages that aren't bun builtins)
  if [ -n "$IMPL" ]; then
    # Allow: relative imports, node: builtins, bun: builtins
    BAD=$(grep "^import" "$IMPL" 2>/dev/null | grep -vE 'from ["\x27]\.|from ["\x27]node:|from ["\x27]bun:|from ["\x27]fs|from ["\x27]path|from ["\x27]crypto|from ["\x27]util' | head -1)
    [ -z "$BAD" ] && pass "clean_imports" || fail "clean_imports"
  else
    fail "clean_imports"
  fi

  # 6. Implementation has function/class (not just comments)
  [ -n "$IMPL" ] && grep -qE "function |class |const .* =" "$IMPL" 2>/dev/null && pass "has_logic" || fail "has_logic"

  # 7. Test imports implementation (connected, not standalone)
  [ -n "$TEST" ] && grep -qE "import|require" "$TEST" 2>/dev/null && pass "test_imports_impl" || fail "test_imports_impl"

  # 8. Reasonable size (not empty, not bloated)
  if [ -n "$IMPL" ]; then
    LINES=$(wc -l < "$IMPL" | tr -d ' ')
    [ "$LINES" -ge 3 ] && [ "$LINES" -le 200 ] && pass "reasonable_size" || fail "reasonable_size"
  else
    fail "reasonable_size"
  fi

elif echo "$AGENT" | grep -q "boss"; then
  ANY=$(find "$OUTPUT_DIR" -name "*.ts" 2>/dev/null | head -1)
  [ -n "$ANY" ] && pass "delegated" || fail "delegated"
  [ -n "$ANY" ] && pass "output_exists" || fail "output_exists"
  [ -n "$ANY" ] && pass "correct_agent" || fail "correct_agent"
  [ -n "$ANY" ] && pass "completed" || fail "completed"
  [ -z "$ANY" ] && { fail "delegated"; fail "output_exists"; fail "correct_agent"; fail "completed"; } 2>/dev/null || true
fi

# Score
if [ "$TOTAL" -eq 0 ]; then
  echo "0.000"
else
  SCORE=$(awk "BEGIN {printf \"%.3f\", $PASSED / $TOTAL}")
  echo "Score: $SCORE ($PASSED/$TOTAL)"
  echo "$SCORE"
fi
