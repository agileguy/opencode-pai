---
name: scraping
description: Web scraping and content retrieval. USE WHEN user says "scrape", "fetch this page", "get content from URL", "can't access this site". Progressive fallback strategy.
---

# Scraping Skill

## Strategy: Progressive Escalation

Try each method in order. Move to the next only if the previous fails.

### Tier 1: Direct Fetch

Simple HTTP request with appropriate headers.

```bash
curl -sL -H "User-Agent: Mozilla/5.0" \
  -H "Accept: text/html" \
  --max-time 15 \
  "$URL"
```

**Works for**: Static pages, most blogs, documentation sites.

### Tier 2: Web Search Extraction

If direct fetch fails (403, captcha, paywall), search for cached or alternative versions.

- Search for the page title + site name
- Check Google cache or archive.org
- Look for the content on aggregators or mirrors

### Tier 3: Headless Browser

For JavaScript-rendered content that curl cannot retrieve.

```bash
# Using playwright or puppeteer if available
npx playwright screenshot "$URL" --full-page
```

### Tier 4: Proxy Service

If all else fails and the content is critical, use a proxy scraping service (e.g., Bright Data) if configured.

## Content Extraction

Once raw HTML is obtained, extract clean content:

1. **Strip HTML** — Remove tags, scripts, styles
2. **Extract main content** — Identify the article body (skip nav, sidebar, footer)
3. **Preserve structure** — Keep headings, lists, code blocks
4. **Convert to markdown** — Clean, readable output

### Extraction Heuristics

- Look for `<article>`, `<main>`, or `role="main"` elements
- Fall back to largest text block
- Remove boilerplate (nav, footer, ads, cookie banners)
- Preserve images as markdown references

## Output Format

```markdown
## Scraped: [Page Title]

**URL**: [URL]
**Date Retrieved**: [Date]
**Method**: [Which tier succeeded]

---

[Clean extracted content in markdown]
```

## Batch Scraping

For multiple URLs:
1. Process each URL independently
2. Report success/failure per URL
3. Aggregate results at the end

## Rules

- Respect `robots.txt` — check before scraping
- Add reasonable delays between requests (1-2 seconds)
- Do not scrape login-protected content without authorization
- Cache results to avoid re-fetching
- If a site actively blocks scraping, respect that decision
- Always include the source URL in output
