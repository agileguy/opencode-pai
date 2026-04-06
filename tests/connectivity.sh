#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0
OMLX_HOST="${OMLX_HOST:-host.docker.internal}"
OMLX_PORT="${OMLX_PORT:-8000}"
LIGHTRAG_HOST="${LIGHTRAG_HOST:-host.docker.internal}"
LIGHTRAG_PORT="${LIGHTRAG_PORT:-9621}"

pass() { echo "PASS: $1"; ((PASS++)); }
fail() { echo "FAIL: $1"; ((FAIL++)); }

# Test 1: host.docker.internal DNS resolves
if getent hosts "$OMLX_HOST" &>/dev/null || ping -c1 -W2 "$OMLX_HOST" &>/dev/null; then
    pass "host.docker.internal DNS resolves"
else
    fail "host.docker.internal DNS resolves"
fi

# Test 2: oMLX API reachable
MODELS_RESPONSE=$(curl -sf -m 10 \
    -H "Authorization: Bearer ${OMLX_API_KEY:-}" \
    "http://${OMLX_HOST}:${OMLX_PORT}/v1/models" 2>/dev/null) || MODELS_RESPONSE=""

if [ -n "$MODELS_RESPONSE" ]; then
    pass "oMLX API reachable at ${OMLX_HOST}:${OMLX_PORT}"
else
    fail "oMLX API reachable at ${OMLX_HOST}:${OMLX_PORT}"
fi

# Test 3: oMLX returns >0 models
if [ -n "$MODELS_RESPONSE" ]; then
    MODEL_COUNT=$(echo "$MODELS_RESPONSE" | jq -r '.data | length' 2>/dev/null || echo "0")
    if [ "$MODEL_COUNT" -gt 0 ] 2>/dev/null; then
        pass "oMLX returns ${MODEL_COUNT} models"
    else
        fail "oMLX returns >0 models (got ${MODEL_COUNT})"
    fi
else
    fail "oMLX returns >0 models (API unreachable)"
fi

# Test 4: LightRAG reachable (optional — SKIP if not running)
LIGHTRAG_RESPONSE=$(curl -sf -m 5 "http://${LIGHTRAG_HOST}:${LIGHTRAG_PORT}/health" 2>/dev/null) || LIGHTRAG_RESPONSE=""

if [ -n "$LIGHTRAG_RESPONSE" ]; then
    pass "LightRAG reachable at ${LIGHTRAG_HOST}:${LIGHTRAG_PORT}"
else
    echo "SKIP: LightRAG not reachable at ${LIGHTRAG_HOST}:${LIGHTRAG_PORT} (optional)"
fi

echo ""
echo "CONNECTIVITY: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
