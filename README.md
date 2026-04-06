# PAI-OpenCode

Dockerized OpenCode environment connected to host oMLX inference server for local AI-powered development.

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

## Available Commands

| Command | Description |
|---------|-------------|
| `make build` | Build the Docker image |
| `make up` | Start the container |
| `make down` | Stop the container |
| `make shell` | Open a shell in the container |
| `make rebuild` | Full rebuild (no cache) |
| `make test-quick` | Validate tool versions |
| `make test` | Run full test suite |
| `make test-e2e` | Run end-to-end tests |
| `make logs` | Tail container logs |

## Architecture

The container connects to the host's oMLX server via `host.docker.internal:8000`. OpenCode is configured with custom oMLX provider definitions in `config/opencode.json`.

Host volumes mounted:
- `~/repos` -> `/workspace/repos` (your code)
- `~/.ssh` -> read-only SSH keys
- `~/.gitconfig` -> git configuration
- `~/.config/gh` -> GitHub CLI auth
