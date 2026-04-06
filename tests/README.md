# Test Harness

Validation scripts for the PAI OpenCode environment. All tests run inside the Docker container.

## Test Scripts

| Script | Category | What it tests |
|--------|----------|---------------|
| `connectivity.sh` | Infrastructure | oMLX API reachable, returns models, LightRAG optional, DNS resolution |
| `model-routing.sh` | Models | Each required model is listed and responds to chat completions |
| `agent-defs.sh` | Configuration | Agent definition files exist with required frontmatter fields |
| `tool-access.sh` | Toolchain | opencode, rg, git, bun, gh available; /workspace writable |
| `e2e-smoke.sh` | End-to-end | opencode run produces output; agent routing works |

## Running Tests

**Quick tests** (no LLM calls, runs in seconds):

```bash
make test-quick
# Runs: connectivity, agent-defs, tool-access
```

**End-to-end tests** (requires running oMLX, takes 1-3 minutes):

```bash
make test-e2e
# Runs: model-routing, e2e-smoke
```

**All tests:**

```bash
make test
# Runs all test scripts
```

**Individual test:**

```bash
bash tests/connectivity.sh
```

## Prerequisites

- oMLX running on host at port 8000
- `OMLX_API_KEY` environment variable set
- Docker container built and running
- For e2e tests: at least one model loaded in oMLX

## Output Format

Every test prints structured output:

```
PASS: description of what passed
FAIL: description of what failed
...
CATEGORY: N passed, M failed
```

Exit code 0 means all tests passed. Exit code 1 means at least one failed.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OMLX_API_KEY` | (required) | API key for oMLX authentication |
| `OMLX_HOST` | `host.docker.internal` | oMLX host address |
| `OMLX_PORT` | `8000` | oMLX port |
| `LIGHTRAG_HOST` | `host.docker.internal` | LightRAG host address |
| `LIGHTRAG_PORT` | `9621` | LightRAG port |
| `AGENTS_DIR` | `~/.config/opencode/agents` | Agent definitions directory |
| `E2E_TIMEOUT` | `120` | Timeout in seconds for e2e tests |
