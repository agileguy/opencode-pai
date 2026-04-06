#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0
E2E_TIMEOUT="${E2E_TIMEOUT:-180}"

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

echo "Running: Algorithm e2e test (timeout ${E2E_TIMEOUT}s)..."
echo "  Sending prompt that should trigger the pai-algorithm skill..."

ALGO_OUTPUT=$(timeout "$E2E_TIMEOUT" opencode run \
    "Use the pai-algorithm skill to plan a simple CLI tool that converts Celsius to Fahrenheit. Only complete the OBSERVE phase — generate ISC criteria and stop. Do not implement anything." 2>&1)
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 124 ]; then
    fail "Algorithm prompt timed out after ${E2E_TIMEOUT}s"
    echo ""
    echo "E2E-ALGORITHM: $PASS passed, $FAIL failed"
    exit 1
fi

# Test 1: Got a non-empty response
if [ -n "$ALGO_OUTPUT" ] && [ ${#ALGO_OUTPUT} -gt 100 ]; then
    pass "Algorithm produced substantial output (${#ALGO_OUTPUT} chars)"
else
    fail "Algorithm produced substantial output (got ${#ALGO_OUTPUT} chars)"
fi

# Test 2: Output contains ISC criteria (ISC-1, ISC-2, etc. or numbered criteria)
if echo "$ALGO_OUTPUT" | grep -qiE "ISC[-_ ]?[0-9]|criteria|criterion"; then
    CRITERIA_COUNT=$(echo "$ALGO_OUTPUT" | grep -ciE "ISC[-_ ]?[0-9]|\- \[" || echo "0")
    pass "Output contains ISC criteria (~${CRITERIA_COUNT} found)"
else
    fail "Output contains ISC criteria"
fi

# Test 3: Output references phases or structured methodology
if echo "$ALGO_OUTPUT" | grep -qiE "observe|phase|reverse.engineer|effort|ideal.state"; then
    pass "Output references Algorithm phases or methodology"
else
    fail "Output references Algorithm phases or methodology"
fi

# Test 4: Output mentions the actual task (Celsius/Fahrenheit)
if echo "$ALGO_OUTPUT" | grep -qiE "celsius|fahrenheit|temperature|convert"; then
    pass "Output addresses the actual task (temperature conversion)"
else
    fail "Output addresses the actual task"
fi

# Test 5: Output is structured (has headers, lists, or formatted sections)
if echo "$ALGO_OUTPUT" | grep -qE "^#+|^-|^\*|━|═|##"; then
    pass "Output is structured (headers/lists/formatting)"
else
    fail "Output is structured"
fi

echo ""
echo "E2E-ALGORITHM: $PASS passed, $FAIL failed"
echo ""
echo "--- Algorithm Output Preview (first 40 lines) ---"
echo "$ALGO_OUTPUT" | head -40
echo "--- (end preview) ---"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
