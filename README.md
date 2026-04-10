# PAI-OpenCode

PAI (Personal AI Infrastructure) running on OpenCode — a fully Dockerized, multi-agent development environment powered by local oMLX inference. Nine specialized agents, custom skills, plugins, memory, and the PAI Algorithm methodology, all running cost-free on local hardware.

## Prerequisites

- Docker (colima or Docker Desktop)
- oMLX running on host (port 8000)
- Git, SSH keys configured on host

## Quick Start

```bash
cp .env.example .env
# Edit .env with your API keys

make build
make up
make shell
```

Once inside the container, OpenCode launches with all PAI agents, skills, and plugins pre-configured.

## Architecture

### Agents

Nine specialized agents, each with defined roles and model routing:

| Agent | Model | Role |
|-------|-------|------|
| pai-architect | gemma-4-31b | System design, architectural decisions |
| pai-engineer | gemma-4-31b | Implementation, TDD, code quality |
| pai-designer | gemma-4-26b | UI/UX design and review |
| pai-qa | gemma-4-26b | Testing and validation |
| pai-pentester | gemma-4-26b | Security assessment |
| pai-artist | gemma-4-26b | Visual content and image prompts |
| pai-researcher | gemma-4-26b | Research synthesis |
| pai-sre | gemma-4-26b | Infrastructure operations |
| pai-pm | gemma-4-26b | Project orchestration |

### Skills

10 priority skills ported from PAI: research, blogging, content analysis, media, security, thinking, investigation, scraping, RAG, and utilities.

### Plugins

- **Context Loader** — Injects PAI context (user profile, DA identity, steering rules) into every session
- **Memory** — PRD sync and rating signal capture

### Memory

Persistent memory layer with learning signals, research cache, security logs, and state tracking.

### PAI Algorithm

The 7-phase PAI Algorithm skill (ISC decomposition, PRD format, effort tiers) provides structured methodology for complex work.

## Testing

```bash
make test-quick    # Structural tests (no model needed)
make test-e2e      # End-to-end tests (requires oMLX)
make test          # All tests
```

Structural tests validate agent definitions, skill loading, and plugin hooks. E2E tests verify model connectivity and routing.

## Eval Suite

Eval tasks test each agent type against specific criteria. Run baselines to measure current agent performance:

```bash
make eval-engineer    # 15 tasks: palindrome, debounce, csv2json, stack, LRU cache, rate limiter, etc.
make eval-boss        # 7 tasks: email-validator, slug-generator, multi-file refactor, design+implement, etc.
make eval-architect   # 7 tasks: cache strategy, auth spec, API versioning, data migration, etc.
make eval-all         # Run all three sequentially
```

Each eval task runs the agent via `opencode run`, then scores the output against weighted metrics:

| Agent | Metrics | Categories |
|-------|---------|------------|
| pai-engineer | 28 | Execution (file/test existence, tests pass), Quality (types, imports, naming, edge cases), Speed (TDD order, conciseness) |
| pai-boss | 13 | Delegation (routing, output exists, delegated tests pass, constraints in brief, no self-implementation) |
| pai-architect | 18 | Design (structure, trade-offs, pros/cons, recommendation, quantitative estimates, migration plan, security) |

Eval tasks live in `eval/tasks/{engineer,boss,architect}/`. Scoring logic is in `eval/check-metrics.sh`.

## Autoresearch

Automated prompt optimization using Karpathy's autoresearch pattern. Mutates agent prompts, evaluates against the eval suite, and keeps improvements while reverting regressions.

```bash
make research-engineer    # Launch engineer prompt optimization (background)
make research-boss        # Launch boss prompt optimization (background)
make research-architect   # Launch architect prompt optimization (background)
make research-all         # Launch all three in parallel

make research-status      # Dashboard: checkpoints, baselines, latest logs, process count
make research-stop        # Create stop files — loops halt after current experiment
```

Each run executes up to 50 experiments. Per experiment:
1. **Mutate** — An LLM modifies the agent prompt using a rotating strategy (remove verbose, reorder, add example, shrink, change sequencing, explicit tool calls)
2. **Evaluate** — Full eval suite runs against the mutated prompt
3. **Keep or revert** — If score improves, keep the mutation and update baseline; otherwise revert

Autoresearch state is in `.autoresearch/` — baselines, checkpoints, logs, mutation history. The loop supports adaptive early stopping after 10 consecutive non-improvements.

## ACP Integration

Connect PAI agents to Zed, JetBrains, or Neovim via the Agent Client Protocol. See [config/acp/README.md](config/acp/README.md).

## Headless Server Mode

Run PAI-OpenCode as a headless server for programmatic control and batch processing. See [config/server/README.md](config/server/README.md).

## Cost Routing

Assign different models to different agents — run 100% local for free, or selectively upgrade agents to cloud models. See [docs/cost-routing.md](docs/cost-routing.md).

## Available Commands

| Command | Description |
|---------|-------------|
| `make build` | Build the Docker image |
| `make up` | Start the container |
| `make down` | Stop the container |
| `make shell` | Open a shell in the container |
| `make rebuild` | Full rebuild (no cache) |
| `make test-quick` | Structural validation tests |
| `make test` | Run full test suite |
| `make test-e2e` | Run end-to-end tests |
| `make logs` | Tail container logs |
| `make eval-engineer` | Run engineer eval (15 tasks) |
| `make eval-boss` | Run boss eval (7 tasks) |
| `make eval-architect` | Run architect eval (7 tasks) |
| `make eval-all` | Run all evals sequentially |
| `make research-all` | Launch all autoresearch in parallel |
| `make research-stop` | Stop all autoresearch loops |
| `make research-status` | Show autoresearch dashboard |

## Directory Structure

```
opencode-pai/
  config/
    acp/              # ACP editor integration docs
    agents/           # Agent definition files (9 agents)
    opencode.json     # OpenCode configuration + model routing
    pai/
      context/        # DA identity, user profile, steering rules
      history/        # Session history
      memory/         # Learning signals, research, state
    plugins/          # Context loader + memory plugins
    server/           # Headless server mode docs
    skills/           # 10 priority skills
    AGENTS.md         # PAI behavioral rules
  eval/
    check-metrics.sh  # Scoring engine (28/13/18 metrics per agent)
    run-eval.sh       # Eval runner (per-agent or all)
    tasks/
      engineer/       # 15 eval tasks (palindrome → dependency-graph)
      boss/           # 7 eval tasks (email-validator → design-and-implement)
      architect/      # 7 eval tasks (cache-strategy → data-migration)
    fixtures/         # Test fixtures for boss eval tasks
  .autoresearch/
    loop.sh           # Main autoresearch loop
    program.md        # Mutator instructions
    baseline-*.txt    # Current baselines per agent
    checkpoint-*.json # Resume state per agent
    output-*.log      # Run logs
  docs/
    cost-routing.md   # Multi-model cost routing guide
  tests/              # Test harness (structural + e2e)
  .github/workflows/  # CI validation
  docker-compose.yml
  Dockerfile
  Makefile
  CHANGELOG.md
```

## Infrastructure

The container connects to the host oMLX server via `host.docker.internal:8000`. Host volumes mounted:

- `~/repos` -> `/workspace/repos` (your code)
- `~/.ssh` -> read-only SSH keys
- `~/.gitconfig` -> git configuration
- `~/.config/gh` -> GitHub CLI auth
