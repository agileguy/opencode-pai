#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0
E2E_TIMEOUT="${E2E_TIMEOUT:-120}"

pass() { echo "PASS: $1"; ((PASS++)); }
fail() { echo "FAIL: $1"; ((FAIL++)); }

# Test 1: opencode run — basic prompt produces PONG
echo "Running: opencode run (PONG test, timeout ${E2E_TIMEOUT}s)..."
PONG_OUTPUT=$(timeout "$E2E_TIMEOUT" opencode run \
    "Reply with exactly the word PONG and nothing else" 2>&1) && PONG_EXIT=0 || PONG_EXIT=$?

if [ "$PONG_EXIT" -eq 124 ]; then
    fail "opencode run timed out after ${E2E_TIMEOUT}s"
elif echo "$PONG_OUTPUT" | grep -qi "PONG"; then
    pass "opencode run returns PONG"
else
    fail "opencode run unexpected output: $(echo "$PONG_OUTPUT" | head -3)"
fi

# Test 2: opencode run with agent — pai-researcher answers 2+2
echo "Running: opencode run --agent pai-researcher (2+2 test, timeout ${E2E_TIMEOUT}s)..."
MATH_OUTPUT=$(timeout "$E2E_TIMEOUT" opencode run \
    --agent pai-researcher \
    "What is 2+2? Reply with just the number." 2>&1) && MATH_EXIT=0 || MATH_EXIT=$?

if [ "$MATH_EXIT" -eq 124 ]; then
    fail "opencode run --agent pai-researcher timed out after ${E2E_TIMEOUT}s"
elif echo "$MATH_OUTPUT" | grep -q "4"; then
    pass "opencode run --agent pai-researcher returns 4"
else
    fail "opencode run --agent pai-researcher unexpected output: $(echo "$MATH_OUTPUT" | head -3)"
fi

echo ""
echo "E2E-SMOKE: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
