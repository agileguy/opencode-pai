#!/usr/bin/env bash
set -euo pipefail

PASS=0; FAIL=0
PLUGIN_DIR="/home/developer/.config/opencode/plugins"

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Test: plugin directory exists
if [ -d "$PLUGIN_DIR" ]; then
  pass "Plugin directory exists"
else
  fail "Plugin directory missing"
  echo "PLUGIN-HOOKS: $PASS passed, $FAIL failed"; exit 1
fi

# Test: package.json exists
if [ -f "${PLUGIN_DIR}/package.json" ]; then
  pass "package.json present"
else
  fail "package.json missing"
fi

# Test: .ts plugin files exist
PLUGIN_COUNT=0
for plugin in "$PLUGIN_DIR"/*.ts; do
  [ -f "$plugin" ] || continue
  PLUGIN_COUNT=$((PLUGIN_COUNT+1))
  NAME=$(basename "$plugin")

  # Basic syntax check — look for export
  if grep -q "export" "$plugin"; then
    pass "${NAME} has export statement"
  else
    fail "${NAME} missing export"
  fi
done

if [ "$PLUGIN_COUNT" -gt 0 ]; then
  pass "${PLUGIN_COUNT} plugin files found"
else
  fail "No .ts plugin files found"
fi

echo ""
echo "PLUGIN-HOOKS: $PASS passed, $FAIL failed (${PLUGIN_COUNT} plugins)"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
