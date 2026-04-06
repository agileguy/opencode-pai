#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0
E2E_TIMEOUT="${E2E_TIMEOUT:-180}"

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

echo "Running: Algorithm auto-trigger test (timeout ${E2E_TIMEOUT}s)..."
echo "  Sending a non-trivial task WITHOUT explicitly asking for the Algorithm..."
echo "  The AGENTS.md instructions should cause it to activate automatically."

# Send a clearly non-trivial task — multi-step, requires planning
ALGO_OUTPUT=$(timeout "$E2E_TIMEOUT" opencode run \
    "Build a TypeScript CLI tool that reads a CSV file and outputs JSON. It should handle headers, quoted fields, and empty values. Plan this out before implementing." 2>&1)
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 124 ]; then
    fail "Non-trivial task timed out after ${E2E_TIMEOUT}s"
    echo ""
    echo "E2E-ALGORITHM-AUTO: $PASS passed, $FAIL failed"
    exit 1
fi

# Test 1: Got a response
if [ -n "$ALGO_OUTPUT" ] && [ ${#ALGO_OUTPUT} -gt 100 ]; then
    pass "Produced substantial output (${#ALGO_OUTPUT} chars)"
else
    fail "Produced substantial output (got ${#ALGO_OUTPUT} chars)"
fi

# Test 2: Algorithm was triggered (skill invoked or phases referenced)
if echo "$ALGO_OUTPUT" | grep -qiE 'pai-algorithm|OBSERVE|━━━.*phase|ISC[-_ ]?[0-9]|effort.tier|ideal.state'; then
    pass "Algorithm was triggered for non-trivial task"
else
    fail "Algorithm was NOT triggered — AGENTS.md instruction may not be followed"
fi

# Test 3: Task was understood (CSV/JSON mentioned in output)
if echo "$ALGO_OUTPUT" | grep -qiE "csv|json|header|parse"; then
    pass "Task context understood (CSV/JSON referenced)"
else
    fail "Task context not reflected in output"
fi

echo ""
echo "E2E-ALGORITHM-AUTO: $PASS passed, $FAIL failed"
echo ""
echo "--- Output Preview (first 30 lines) ---"
echo "$ALGO_OUTPUT" | head -30
echo "--- (end preview) ---"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
