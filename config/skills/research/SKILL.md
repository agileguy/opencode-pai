---
name: research
description: Comprehensive research and analysis. USE WHEN user says "research", "do research", "investigate", "look into". Supports quick (single query), standard (3 perspectives), and extensive (9 parallel agents) modes.
---

# Research Skill

## Mode Selection

Determine mode from context:

| Mode | Trigger | Approach |
|------|---------|----------|
| **Quick** | "quick research", simple factual question | Single focused search, concise answer |
| **Standard** | Default for "research X" | 3 parallel perspectives, synthesized report |
| **Extensive** | "deep research", "extensive", complex topic | 9 parallel queries, comprehensive analysis |

## Quick Mode

1. Formulate one precise search query
2. Search and extract relevant facts
3. Return concise answer with sources

## Standard Mode (Default)

1. **Decompose** the topic into 3 focused angles:
   - Angle A: Core facts and current state
   - Angle B: Expert opinions and analysis
   - Angle C: Contrarian views or risks
2. **Search** all 3 in parallel
3. **Synthesize** findings into a structured report:
   - Executive summary (3-5 sentences)
   - Key findings per angle
   - Consensus vs disagreement
   - Sources with verified URLs

## Extensive Mode

1. **Decompose** into 9 queries across dimensions:
   - 3 factual/data queries
   - 3 analysis/opinion queries
   - 3 contrarian/risk queries
2. **Execute** all 9 searches in parallel
3. **Cross-reference** findings for consistency
4. **Synthesize** into comprehensive report with confidence levels

## Output Format

```
## Research: [Topic]

### Summary
[3-5 sentence executive summary]

### Key Findings
1. [Finding with source]
2. [Finding with source]
...

### Analysis
[Synthesis across perspectives]

### Sources
- [Title](URL) — [one-line relevance note]
```

## Rules

- Verify all URLs exist before including them
- Never fabricate sources or citations
- State confidence level for each claim
- Distinguish facts from opinions
- Note when information is outdated or conflicting
- If a search returns no results, say so honestly
