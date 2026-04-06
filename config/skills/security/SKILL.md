---
name: security
description: Security assessment and testing. USE WHEN user says "security audit", "pen test", "vulnerability scan", "OWASP", "security review". Includes web app testing, network recon, and prompt injection testing.
---

# Security Skill

## Ethical Boundaries

- Only test systems you are **authorized** to test
- Confirm authorization before any active scanning
- Never exfiltrate real user data
- Report vulnerabilities responsibly
- Stop immediately if scope is exceeded

## Methodology: OWASP Top 10

### Phase 1: Reconnaissance

1. **Passive recon** — DNS records, WHOIS, certificate transparency
2. **Technology fingerprinting** — Server headers, framework detection
3. **Attack surface mapping** — Endpoints, forms, APIs, auth flows

```bash
# DNS enumeration
dig +short A target.com
dig +short MX target.com
dig +short TXT target.com

# Certificate transparency
curl -s "https://crt.sh/?q=%.target.com&output=json" | jq '.[].name_value'

# HTTP headers
curl -sI https://target.com
```

### Phase 2: Vulnerability Testing

Test against OWASP Top 10 (2021):

| # | Category | Quick Check |
|---|----------|-------------|
| A01 | Broken Access Control | Test IDOR, path traversal, missing auth |
| A02 | Cryptographic Failures | Check TLS config, exposed secrets |
| A03 | Injection | SQL, XSS, command injection inputs |
| A04 | Insecure Design | Business logic flaws |
| A05 | Security Misconfiguration | Default creds, verbose errors, open dirs |
| A06 | Vulnerable Components | Check dependency versions against CVEs |
| A07 | Auth Failures | Brute force, session management |
| A08 | Data Integrity Failures | Deserialization, unsigned updates |
| A09 | Logging Failures | Missing audit trails |
| A10 | SSRF | Internal URL access from inputs |

### Phase 3: Prompt Injection Testing (AI Systems)

For AI/LLM applications:
1. Direct injection — Override system prompts
2. Indirect injection — Embedded instructions in retrieved content
3. Extraction — Attempt to leak system prompts or training data
4. Jailbreak — Bypass safety filters

### Phase 4: Reporting

```markdown
## Security Assessment: [Target]

### Executive Summary
[1-2 paragraph overview]

### Findings

#### [CRITICAL/HIGH/MEDIUM/LOW] — [Finding Title]
- **Description**: What was found
- **Impact**: What an attacker could do
- **Evidence**: Steps to reproduce
- **Remediation**: How to fix it

### Recommendations
[Prioritized list of fixes]
```

## Rules

- Always confirm scope and authorization first
- Classify findings by severity (Critical/High/Medium/Low)
- Provide remediation steps for every finding
- Never store or transmit discovered credentials
- Document everything for reproducibility
