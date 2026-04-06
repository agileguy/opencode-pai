# Effort Tiers

Detailed guide for selecting the right Algorithm effort tier.

## Standard (<2 min, 8-16 ISC)

The default tier. Use for everyday tasks that need structure but not ceremony.

**Examples:**
- Add a new config option to an existing file
- Fix a failing test
- Rename a variable across a codebase
- Write a single utility function with tests

**Algorithm behavior:** Phases are brief. THINK and PLAN may be 2-3 sentences each. The full Algorithm can complete in a single response.

## Extended (<8 min, 16-32 ISC)

When the work must be notably high quality or involves multiple steps.

**Examples:**
- Implement a new CLI command with argument parsing
- Add a feature with multiple edge cases to test
- Refactor a module while maintaining backward compatibility
- Write a comprehensive test suite for existing code

**Algorithm behavior:** Each phase gets real depth. PLAN should list specific files and changes. VERIFY should run actual tests.

## Advanced (<16 min, 24-48 ISC)

Multi-file work that touches several parts of the system.

**Examples:**
- Add a new skill with SKILL.md and reference files
- Implement an API endpoint with route, handler, validation, and tests
- Create a new agent configuration with all supporting files
- Migrate a subsystem from one pattern to another

**Algorithm behavior:** THINK includes research into existing patterns. PLAN is a detailed numbered list. BUILD proceeds file-by-file.

## Deep (<32 min, 40-80 ISC)

Complex design work or significant system integration.

**Examples:**
- Design and implement a plugin system
- Build a multi-step workflow engine
- Create a monitoring dashboard with multiple data sources
- Architect a new subsystem with clear boundaries

**Algorithm behavior:** THINK includes alternatives analysis with tradeoff matrices. PLAN may include architecture sketches. VERIFY is comprehensive.

## Comprehensive (<120 min, 64-150 ISC)

No time pressure. Full-scope builds or major system changes.

**Examples:**
- Build an entire application from scratch
- Port a system from one framework to another
- Implement a complete test harness with CI integration
- Design and build a multi-agent coordination system

**Algorithm behavior:** Full ceremony. OBSERVE produces a detailed PRD. THINK is a thorough analysis. PLAN is exhaustive. BUILD follows TDD strictly. VERIFY runs all tests with evidence. LEARN captures reusable patterns.
