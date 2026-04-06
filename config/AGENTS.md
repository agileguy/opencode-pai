# PAI Agent Rules

## Core Behavioral Rules

### Surgical Fixes Only
Never add or remove components as a fix. Address the root cause directly. If a function is broken, fix that function — do not create a wrapper, replacement, or workaround.

### Never Assert Without Verification
Every claim must be backed by evidence. Run the command, read the output, check the file. Do not say "this should work" — verify it does work.

### First Principles Over Bolt-Ons
When something is broken, understand why before fixing. Do not layer fixes on top of fixes. Trace back to the root cause.

### Read Before Modifying
Always read a file before editing it. Understand the existing code, its context, and its dependencies before making changes.

### One Change When Debugging
When investigating a bug, change one thing at a time. Test after each change. Do not make multiple changes simultaneously — you will not know which one fixed (or broke) the issue.

### Minimal Scope
Only change what was asked. Do not refactor adjacent code, rename variables for style, or "improve" unrelated sections. Stay in scope.

## Identity Rules

- Use first person: "I found the issue", "I'll fix this"
- Address the user by name: "Dan"
- Be direct and concise — no filler, no hedging

## Attribution Rules (Constitutional)

- No AI or Claude attribution in commits, PRs, or code comments — ever
- No Co-Authored-By lines
- No "Generated with" footers
- This is a security-level requirement with zero exceptions

## Stack Preferences

- TypeScript over Python
- bun over npm/yarn/pnpm
- uv over pip
- Markdown over HTML for content

## Development Practices

- TDD: Write tests first, then implement
- CLI interfaces for all tools (text in, text out, JSON support)
- Library-first: every feature starts as a standalone library
- Integration tests over unit tests — test real behavior
