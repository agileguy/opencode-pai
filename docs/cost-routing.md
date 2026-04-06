# Multi-Model Cost Routing

PAI-OpenCode's key advantage: assign different models to different agents based on task complexity and cost.

## Current Routing

| Agent | Model | Cost | Rationale |
|-------|-------|------|-----------|
| pai-architect | omlx/gemma-4-31b | Free (local) | Complex reasoning, can upgrade to cloud Opus |
| pai-engineer | omlx/gemma-4-31b | Free (local) | Implementation, TDD |
| pai-designer | omlx/gemma-4-26b | Free (local) | UI/UX design |
| pai-qa | omlx/gemma-4-26b | Free (local) | Testing and validation |
| pai-pentester | omlx/gemma-4-26b | Free (local) | Security assessment |
| pai-artist | omlx/gemma-4-26b | Free (local) | Image prompt crafting |
| pai-researcher | omlx/gemma-4-26b | Free (local) | Research synthesis |
| pai-sre | omlx/gemma-4-26b | Free (local) | Infrastructure ops |
| pai-pm | omlx/gemma-4-26b | Free (local) | Project orchestration |

## Upgrading to Cloud Models

Override model per agent in opencode.json:

```json
{
  "agent": {
    "pai-architect": { "model": "anthropic/claude-opus-4-5" },
    "pai-researcher": { "model": "google/gemini-2.5-flash" }
  }
}
```

## Adding Cloud Providers

### Anthropic

```json
{
  "provider": {
    "anthropic": {
      "api_key": "{env:ANTHROPIC_API_KEY}"
    }
  }
}
```

### Google

```json
{
  "provider": {
    "google": {
      "api_key": "{env:GEMINI_API_KEY}"
    }
  }
}
```

### OpenAI

```json
{
  "provider": {
    "openai": {
      "api_key": "{env:OPENAI_API_KEY}"
    }
  }
}
```

## Cost Projection

| Scenario | Monthly Cost |
|----------|-------------|
| 100% local (oMLX) | $0 |
| 70% local / 30% cloud cheap | ~$30-50 |
| 50% local / 50% cloud premium | ~$100-200 |
| 100% cloud (Claude Max equivalent) | ~$200+ |
