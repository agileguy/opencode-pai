---
name: utilities
description: Developer utilities and tools. USE WHEN user says "create CLI", "parse", "convert", "generate", "scaffold". Includes CLI generation, parsing, format conversion, and scaffolding.
---

# Utilities Skill

## CLI Generation

### Stack

- **Language**: TypeScript
- **Runtime**: Bun
- **No frameworks** unless complexity demands it (prefer raw arg parsing for simple CLIs)

### CLI Template

```typescript
#!/usr/bin/env bun

const args = process.argv.slice(2);

function usage(): never {
  console.log(`Usage: tool-name <command> [options]

Commands:
  run       Execute the main operation
  help      Show this help message

Options:
  --output, -o    Output file path
  --format, -f    Output format (json, text, csv)
  --verbose, -v   Verbose output
  --help, -h      Show help`);
  process.exit(0);
}

if (args.length === 0 || args.includes('--help') || args.includes('-h')) {
  usage();
}

// Main logic here
```

### CLI Standards

1. **Always include `--help`** with clear usage examples
2. **Exit codes**: 0 = success, 1 = error, 2 = invalid usage
3. **Error messages** go to stderr: `console.error()`
4. **Structured output** with `--format json` option
5. **No interactive prompts** in default mode — support piping

### Setup

```bash
mkdir my-cli && cd my-cli
bun init -y
# Edit package.json: add "bin" field
# Edit tsconfig.json: target ESNext, module ESNext
```

## Format Conversion

### Common Patterns

| From | To | Tool/Method |
|------|----|-------------|
| JSON | CSV | `jq -r` or custom script |
| CSV | JSON | `bun` script with parsing |
| YAML | JSON | `yq -o json` |
| JSON | YAML | `yq -P` |
| Markdown | HTML | `marked` or `markdown-it` |
| HTML | Markdown | `turndown` |

### JSON Processing

```bash
# Pretty print
cat file.json | jq '.'

# Extract field
cat file.json | jq '.data[] | {name, value}'

# Convert to CSV
cat file.json | jq -r '.[] | [.field1, .field2] | @csv'
```

## Scaffolding

### Project Scaffolding Checklist

When scaffolding a new project:

1. **Directory structure** — src/, tests/, config/
2. **Package manager** — `bun init`
3. **TypeScript config** — tsconfig.json with strict mode
4. **Linting** — biome.json or eslint
5. **Git** — .gitignore, initial commit
6. **Tests** — test framework setup, first test
7. **CI** — GitHub Actions or equivalent
8. **README** — Purpose, setup, usage

### Minimal Project

```bash
mkdir project && cd project
bun init -y
mkdir -p src tests
cat > src/index.ts << 'EOF'
export function main(): void {
  console.log("Hello");
}

if (import.meta.main) {
  main();
}
EOF
cat > tests/index.test.ts << 'EOF'
import { expect, test } from "bun:test";
import { main } from "../src/index";

test("main runs without error", () => {
  expect(main).not.toThrow();
});
EOF
bun test
```

## Parsing

### Common Parsing Tasks

- **Log files**: Extract timestamps, levels, messages
- **Configuration**: Parse env files, TOML, YAML
- **Structured text**: Tables, CSVs, fixed-width

### Log Parsing Example

```bash
# Extract errors with timestamps
grep -E "ERROR|FATAL" app.log | awk '{print $1, $2, $NF}'

# Count by log level
awk '{print $3}' app.log | sort | uniq -c | sort -rn
```

## Rules

- TypeScript over Python for new tools
- Bun over Node for runtime
- Include `--help` in every CLI
- Write at least one test for every utility
- Prefer streaming for large file processing
- Use exit codes consistently
