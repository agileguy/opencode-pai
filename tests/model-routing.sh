#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0
OMLX_HOST="${OMLX_HOST:-host.docker.internal}"
OMLX_PORT="${OMLX_PORT:-8000}"
BASE_URL="http://${OMLX_HOST}:${OMLX_PORT}/v1"
AUTH_HEADER="Authorization: Bearer ${OMLX_API_KEY:-}"

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

REQUIRED_MODELS=(
    "gemma-4-26b-a4b-it-4bit"
)

# Fetch models list once
MODELS_RESPONSE=$(curl -sf -m 10 \
    -H "$AUTH_HEADER" \
    "${BASE_URL}/models" 2>/dev/null) || MODELS_RESPONSE=""

if [ -z "$MODELS_RESPONSE" ]; then
    echo "FAIL: Cannot reach oMLX API — skipping all model tests"
    FAIL=${#REQUIRED_MODELS[@]}
    FAIL=$((FAIL * 2))
    echo ""
    echo "MODEL-ROUTING: ${PASS} passed, ${FAIL} failed"
    exit 1
fi

for MODEL in "${REQUIRED_MODELS[@]}"; do
    # Test: Model listed in /v1/models
    if echo "$MODELS_RESPONSE" | jq -e ".data[] | select(.id == \"$MODEL\")" &>/dev/null; then
        pass "${MODEL} listed in /v1/models"
    else
        fail "${MODEL} listed in /v1/models"
        # Skip chat completion test if model not listed
        fail "${MODEL} responds to chat completion (model not listed)"
        continue
    fi

    # Test: Model responds to chat completion
    CHAT_RESPONSE=$(curl -sf -m 60 \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"${MODEL}\",
            \"messages\": [{\"role\": \"user\", \"content\": \"Reply with exactly: PING\"}],
            \"max_tokens\": 10
        }" \
        "${BASE_URL}/chat/completions" 2>/dev/null) || CHAT_RESPONSE=""

    if [ -n "$CHAT_RESPONSE" ] && echo "$CHAT_RESPONSE" | jq -e '.choices[0].message.content' &>/dev/null; then
        CONTENT=$(echo "$CHAT_RESPONSE" | jq -r '.choices[0].message.content')
        pass "${MODEL} responds to chat completion (got: ${CONTENT:0:30})"
    else
        fail "${MODEL} responds to chat completion"
    fi
done

echo ""
echo "MODEL-ROUTING: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
