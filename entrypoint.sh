#!/bin/bash
set -euo pipefail

echo "============================================"
echo "  PAI-OpenCode Environment"
echo "============================================"
echo ""
echo "Versions:"
echo "  Node.js : $(node --version 2>/dev/null || echo 'not found')"
echo "  Bun     : $(bun --version 2>/dev/null || echo 'not found')"
echo "  Python  : $(python3 --version 2>/dev/null || echo 'not found')"
echo "  OpenCode: $(opencode --version 2>/dev/null || echo 'not found')"
echo "  gh      : $(gh --version 2>/dev/null | head -1 || echo 'not found')"
echo ""

# Validate OMLX_API_KEY
if [ -z "${OMLX_API_KEY:-}" ]; then
    echo "WARNING: OMLX_API_KEY is not set. oMLX provider will not authenticate."
    echo "         Set it in .env or pass via environment."
    echo ""
fi

exec "$@"
