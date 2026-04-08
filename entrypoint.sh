#!/bin/bash
set -euo pipefail

# Fix OpenCode data directory ownership (named volume may be root-owned)
sudo chown -R developer:developer /home/developer/.local/share/opencode 2>/dev/null || \
  mkdir -p /home/developer/.local/share/opencode

# Fix SSH key permissions (mounted read-only from host with wrong UID)
if [ -d /home/developer/.ssh-host ]; then
  mkdir -p /home/developer/.ssh
  cp /home/developer/.ssh-host/* /home/developer/.ssh/ 2>/dev/null || true
  chmod 700 /home/developer/.ssh
  chmod 600 /home/developer/.ssh/* 2>/dev/null || true
  chmod 644 /home/developer/.ssh/*.pub 2>/dev/null || true
fi

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

# Install plugin dependencies (config dir is bind-mounted, node_modules may not exist)
OPENCODE_CONFIG="/home/developer/.config/opencode"
if [ -f "$OPENCODE_CONFIG/package.json" ] && [ ! -d "$OPENCODE_CONFIG/node_modules" ]; then
    echo "Installing OpenCode plugin dependencies..."
    cd "$OPENCODE_CONFIG" && npm install --silent 2>/dev/null || true
    cd /workspace
fi

# Validate OMLX_API_KEY
if [ -z "${OMLX_API_KEY:-}" ]; then
    echo "WARNING: OMLX_API_KEY is not set. oMLX provider will not authenticate."
    echo "         Set it in .env or pass via environment."
    echo ""
fi

exec "$@"
