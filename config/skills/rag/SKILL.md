---
name: rag
description: Local knowledge base interaction via LightRAG. USE WHEN user says "rag", "query knowledge base", "search knowledge", "insert into rag", "rag status". Requires LightRAG running at host.docker.internal:9621.
---

# RAG Skill

## Service

LightRAG instance at `http://host.docker.internal:9621`

## Health Check

```bash
curl -s http://host.docker.internal:9621/health | jq .
```

Expected: `{"status": "healthy"}` or similar 200 response.

## Query Modes

| Mode | Use Case | Description |
|------|----------|-------------|
| `naive` | Simple lookup | Direct text search, fastest |
| `local` | Focused context | Entity-level retrieval |
| `global` | Broad overview | Community-level summaries |
| `hybrid` | Best general use | Combines local + global (default) |

### Query API

```bash
curl -s -X POST http://host.docker.internal:9621/query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "<user question>",
    "mode": "hybrid"
  }' | jq .
```

### Mode Selection Guide

- **User asks a specific fact** -> `local`
- **User asks for an overview** -> `global`
- **User asks a general question** -> `hybrid` (default)
- **User wants raw text match** -> `naive`

## Insert Documents

### Insert Text

```bash
curl -s -X POST http://host.docker.internal:9621/documents/text \
  -H "Content-Type: application/json" \
  -d '{
    "text": "<content to insert>",
    "description": "<what this content is>"
  }' | jq .
```

### Insert File

```bash
curl -s -X POST http://host.docker.internal:9621/documents/file \
  -F "file=@/path/to/document.pdf" \
  -F "description=<what this file contains>" | jq .
```

## Status Check

```bash
# Health
curl -s http://host.docker.internal:9621/health | jq .

# Document count (if endpoint available)
curl -s http://host.docker.internal:9621/documents | jq '.count // length'
```

## WebUI

Available at `http://host.docker.internal:9621/webui` for browser-based interaction.

## Workflow

1. **Check health** before any operation
2. **Query** with appropriate mode for the question
3. **Insert** new knowledge when user provides content worth remembering
4. **Report** what was found or inserted

## Output Format

### For Queries

```markdown
## RAG Query: [Question]

**Mode**: [hybrid/local/global/naive]

### Answer
[Response from RAG]

### Sources
[Referenced documents if available]
```

### For Inserts

```markdown
## RAG Insert

**Description**: [What was inserted]
**Size**: [Approximate content size]
**Status**: [Success/Failure]
```

## Rules

- Always check health before first operation in a session
- Default to `hybrid` mode unless user specifies otherwise
- Report if the service is unreachable
- Do not insert duplicate content
- Include the query mode used in the response
