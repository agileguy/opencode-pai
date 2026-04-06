#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Agent definitions directory — inside container this maps to ~/.config/opencode/agents/
AGENTS_DIR="${AGENTS_DIR:-$HOME/.config/opencode/agents}"

# Phase 1 agents — extend this array as new agents are added in Phase 2+
REQUIRED_AGENTS=(
    "pai-architect"
    "pai-engineer"
    "pai-researcher"
)

for AGENT in "${REQUIRED_AGENTS[@]}"; do
    AGENT_FILE="${AGENTS_DIR}/${AGENT}.md"

    # Test: Agent file exists
    if [ -f "$AGENT_FILE" ]; then
        pass "${AGENT}.md exists"
    else
        fail "${AGENT}.md exists (not found at ${AGENT_FILE})"
        # Skip frontmatter checks if file missing
        fail "${AGENT}.md has description: in frontmatter (file missing)"
        fail "${AGENT}.md has mode: in frontmatter (file missing)"
        continue
    fi

    # Test: Has description: in frontmatter
    if head -20 "$AGENT_FILE" | grep -q "^description:"; then
        pass "${AGENT}.md has description: in frontmatter"
    else
        fail "${AGENT}.md has description: in frontmatter"
    fi

    # Test: Has mode: in frontmatter
    if head -20 "$AGENT_FILE" | grep -q "^mode:"; then
        pass "${AGENT}.md has mode: in frontmatter"
    else
        fail "${AGENT}.md has mode: in frontmatter"
    fi
done

echo ""
echo "AGENT-DEFS: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
