#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Test 1: opencode binary exists and runs
if command -v opencode &>/dev/null && opencode --version &>/dev/null; then
    OC_VERSION=$(opencode --version 2>&1 | head -1)
    pass "opencode binary available (${OC_VERSION})"
else
    fail "opencode binary available"
fi

# Test 2: opencode models omlx lists models containing "gemma"
MODELS_OUTPUT=$(opencode models omlx 2>/dev/null) || MODELS_OUTPUT=""
if echo "$MODELS_OUTPUT" | grep -qi "gemma"; then
    pass "opencode models omlx lists gemma models"
else
    fail "opencode models omlx lists gemma models"
fi

# Test 3: ripgrep (rg) available
if command -v rg &>/dev/null; then
    RG_VERSION=$(rg --version | head -1)
    pass "ripgrep available (${RG_VERSION})"
else
    fail "ripgrep available"
fi

# Test 4: git available
if command -v git &>/dev/null; then
    GIT_VERSION=$(git --version)
    pass "git available (${GIT_VERSION})"
else
    fail "git available"
fi

# Test 5: bun available
if command -v bun &>/dev/null; then
    BUN_VERSION=$(bun --version 2>&1)
    pass "bun available (${BUN_VERSION})"
else
    fail "bun available"
fi

# Test 6: gh CLI available and authenticated
if command -v gh &>/dev/null; then
    GH_VERSION=$(gh --version 2>&1 | head -1)
    if gh auth status &>/dev/null; then
        pass "gh CLI available and authenticated (${GH_VERSION})"
    else
        fail "gh CLI available but NOT authenticated (${GH_VERSION})"
    fi
else
    fail "gh CLI available"
fi

# Test 7: /workspace directory writable
if [ -d /workspace ] && touch /workspace/.write-test 2>/dev/null; then
    rm -f /workspace/.write-test
    pass "/workspace directory writable"
else
    fail "/workspace directory writable"
fi

echo ""
echo "TOOL-ACCESS: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
