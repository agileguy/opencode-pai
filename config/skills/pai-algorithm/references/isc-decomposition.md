# ISC Decomposition Guide

How to write good Ideal State Criteria — atomic, binary-testable checkpoints.

## The Splitting Test

Every criterion must pass all four tests. If any test fails, split it.

### Test 1: AND Test
Does it contain "and" joining two verifiable things?
- BAD: `ISC-1: Config file exists and contains valid JSON`
- GOOD: `ISC-1: Config file exists at expected path` + `ISC-2: Config file contains valid JSON`

### Test 2: WITH Test
Does "with" add a second concern?
- BAD: `ISC-1: API endpoint returns 200 with correct schema`
- GOOD: `ISC-1: API endpoint returns HTTP 200` + `ISC-2: Response body matches expected schema`

### Test 3: Domain Test
Does it span two domains (UI, data, logic, infra)?
- BAD: `ISC-1: Form validates input and saves to database`
- GOOD: `ISC-1: Form rejects invalid email format` + `ISC-2: Valid submission writes row to users table`

### Test 4: Verification Test
Would you check two different things to verify it?
- BAD: `ISC-1: Deployment succeeds and service is healthy`
- GOOD: `ISC-1: Deploy command exits with code 0` + `ISC-2: Health endpoint returns 200`

## Decomposition by Domain

When generating ISC criteria, consider each domain that the task touches:

| Domain | What to verify | Example criteria |
|--------|---------------|-----------------|
| **UI** | Visual state, user interaction | "Button appears in header navigation bar" |
| **Data** | Storage, retrieval, format | "Record persists after page refresh" |
| **Logic** | Business rules, computation | "Discount applies only to orders over fifty dollars" |
| **Content** | Text, labels, messages | "Error message displays specific validation failure" |
| **Infrastructure** | Files, configs, services | "Docker container starts without error logs" |

## Coarse vs Atomic: Examples

### Coarse (bad — not verifiable as single checks)
- "Authentication system works correctly"
- "Dashboard displays all required data"
- "API handles errors gracefully"

### Atomic (good — each is one verifiable thing)
- "Login with valid credentials returns JWT token"
- "Login with wrong password returns HTTP 401"
- "JWT token expires after 24 hours"
- "Dashboard shows user count from database"
- "Dashboard refreshes data every 30 seconds"
- "API returns 400 for missing required fields"
- "API returns structured error with message field"

## Anti-Criteria (ISC-A)

Things that must NOT happen. Just as important as positive criteria.

Common anti-criteria:
- `ISC-A1: No existing tests broken by changes`
- `ISC-A2: No hardcoded credentials in source code`
- `ISC-A3: No unrelated files modified in changeset`
- `ISC-A4: No console errors in browser developer tools`
- `ISC-A5: No regression in page load time`

## Writing Checklist

For each criterion you write, confirm:
- [ ] 8-12 words (scannable, specific)
- [ ] One thing to verify (atomic)
- [ ] Clear pass/fail (binary)
- [ ] Verifiable with evidence (not subjective)
- [ ] Passes all four splitting tests
