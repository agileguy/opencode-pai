---
name: content-analysis
description: Content extraction and analysis from videos, podcasts, articles. USE WHEN user says "extract wisdom", "analyze content", "key takeaways", "summarize video", "what did I learn".
---

# Content Analysis Skill

## Purpose

Extract structured insights from any content — videos, podcasts, articles, transcripts, or documents.

## Workflow

1. **Obtain content** — URL, transcript, or pasted text
2. **Identify type** — Video, podcast, article, paper, book excerpt
3. **Extract** using the appropriate template below
4. **Present** structured findings

## Extraction Template

### Core Extraction

For any content type, extract:

```markdown
## Content Analysis: [Title]

**Source**: [URL or reference]
**Author/Speaker**: [Name]
**Type**: [Video/Podcast/Article/Paper]
**Length**: [Duration or word count]

### Summary
[3-5 sentence overview of the entire piece]

### Key Ideas
1. [Most important idea — 1-2 sentences]
2. [Second key idea]
3. [Third key idea]
... (up to 10)

### Surprising Claims
- [Claim that challenges conventional wisdom]
- [Unexpected data point or finding]

### Actionable Advice
- [ ] [Specific thing the reader can do]
- [ ] [Another actionable step]
- [ ] [Third action item]

### Notable Quotes
> "[Exact or near-exact quote]" — [Speaker, timestamp if available]

### Agreements & Disagreements
- **Agrees with**: [mainstream views it supports]
- **Challenges**: [views it pushes back on]

### References Mentioned
- [Book, paper, or person referenced]
```

### Extended Analysis (For Deep Content)

Add these sections for longer or more complex content:

```markdown
### Mental Models Used
- [Framework or thinking tool applied]

### Logical Gaps
- [Where the argument is weak or unsupported]

### Connection to Other Ideas
- [How this relates to other known concepts]

### One-Sentence Takeaway
[The single most important thing from this content]
```

## Content-Specific Notes

### Videos/Podcasts
- Include timestamps where possible (e.g., [14:32])
- Note when speakers disagree with each other
- Capture the emotional arc, not just facts

### Articles/Papers
- Note methodology for research papers
- Flag if the content is opinion vs. research-backed
- Capture the thesis statement explicitly

### Books
- Extract per-chapter if full book
- Focus on frameworks and models, not anecdotes
- Identify the "one big idea" the author is pushing

## Rules

- Never fabricate quotes — mark approximate quotes with "~"
- Distinguish author claims from established facts
- Note content date — ideas may be outdated
- If content is behind a paywall, work with whatever is available
- Present findings neutrally — save judgment for the analysis section
