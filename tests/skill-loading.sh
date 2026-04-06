#!/usr/bin/env bash
set -euo pipefail

PASS=0; FAIL=0
SKILL_DIR="/home/developer/.config/opencode/skills"

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Test: skills directory exists
if [ -d "$SKILL_DIR" ]; then
  pass "Skills directory exists"
else
  fail "Skills directory missing"
  echo "SKILL-LOADING: $PASS passed, $FAIL failed"; exit 1
fi

# Test each skill has valid SKILL.md
for SKILL_PATH in "$SKILL_DIR"/*/SKILL.md; do
  [ -f "$SKILL_PATH" ] || continue
  SKILL_NAME=$(basename "$(dirname "$SKILL_PATH")")

  if head -10 "$SKILL_PATH" | grep -q "^name:"; then
    pass "${SKILL_NAME} has name field"
  else
    fail "${SKILL_NAME} missing name"
  fi

  if head -10 "$SKILL_PATH" | grep -q "^description:"; then
    pass "${SKILL_NAME} has description field"
  else
    fail "${SKILL_NAME} missing description"
  fi
done

SKILL_COUNT=$(find "$SKILL_DIR" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "SKILL-LOADING: $PASS passed, $FAIL failed (${SKILL_COUNT} skills)"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
