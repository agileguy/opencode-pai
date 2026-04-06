# ACP Integration (Agent Client Protocol)

PAI agents are accessible from any ACP-compatible editor via `opencode acp`.

## Supported Editors

- Zed
- JetBrains (2025.3+)
- Neovim (Avante.nvim, CodeCompanion.nvim)

## Zed Configuration

Add to `~/.config/zed/settings.json`:

```json
{
  "agent_servers": {
    "PAI-OpenCode": {
      "command": "docker",
      "args": ["compose", "-f", "/path/to/opencode-pai/docker-compose.yml", "exec", "-T", "opencode-pai", "opencode", "acp"]
    }
  }
}
```

## JetBrains Configuration

Create `acp.json` in your project:

```json
{
  "name": "PAI-OpenCode",
  "command": "docker",
  "args": ["compose", "-f", "/path/to/opencode-pai/docker-compose.yml", "exec", "-T", "opencode-pai", "opencode", "acp"]
}
```

## Direct (non-Docker) Usage

If running OpenCode natively:

```bash
opencode acp
```

## Available Agents via ACP

All PAI agents are available:

- pai-architect, pai-engineer, pai-designer
- pai-qa, pai-pentester, pai-artist
- pai-researcher, pai-sre, pai-pm

## Limitations

- `/undo` and `/redo` slash commands not supported via ACP
- Session persistence depends on OpenCode daemon running
