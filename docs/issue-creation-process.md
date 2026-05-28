# Standardized GitHub Issue Creation Process

> **Purpose:** A repeatable, MCP-integrated process for creating issues with maximum context and traceability.

---

## Overview

This document defines the standardized workflow for creating GitHub issues in the MLB analytics platform. It integrates with existing MCP servers (GitHub, memory, sequential-thinking) and follows industry-standard protocols.

---

## Phase 1: Issue Discovery & Classification

### Step 1: Identify the Issue Type

Choose from existing templates:

| Template | When to Use | Labels Applied |
|----------|-------------|--------------|
| `Bug report` (`.github/ISSUE_TEMPLATE/bug-report.yml`) | Unexpected behavior, test failures, incorrect data | `type:bug` |
| `Feature request` (`.github/ISSUE_TEMPLATE/feature-request.yml`) | New functionality, improvements | `type:feature` |
| `Data source` (`.github/ISSUE_TEMPLATE/data-source.yml`) | Retrosheet, Statcast, MLB API, FanGraphs, BRef, ESPN, odds ingestion | `area:ingestion`, `type:task` |
| `Modeling task` (`.github/ISSUE_TEMPLATE/modeling-task.yml`) | ML features, training runs, predictions | `area:modeling` |

### Step 2: Apply Priority Labels

| Priority | When to Use |
|----------|-------------|
| `priority:critical` | Data loss risk, security vulnerability, CI blocking |
| `priority:high` | Core functionality broken, schema violations |
| `priority:medium` | Feature gaps, performance improvements |
| `priority:low` | Technical debt, documentation |

---

## Phase 2: MCP-Integrated Issue Creation

### Step 3: Store Context in MCP Memory (Optional but Recommended)

Before creating an issue, store technical context for session continuity:

```
# Using MCP memory server
memory://issues/[issue-number]/context
├── problem: "Technical description"
├── root_cause: "Analysis from code review"
├── files_affected: ["path/to/file.py", "sql/schema/file.sql"]
├── related_issues: ["#123", "#456"]
└── layer: "raw|staging|core|ml|api"
```

### Step 4: Create the Issue

#### Method A: GitHub CLI (Recommended)

```bash
# For bugs
gh issue create \
  --title "BUG: [component] Brief description of the bug" \
  --body "$(cat <<'EOF'
**Layer affected:** staging/sql/python/mcp

**Root cause:**
Technical analysis of the problem

**Files affected:**
- `baseball/ingestion/statcast.py:147`
- `baseball/cli.py:142`

**Steps to reproduce:**
1. Run `baseball ingest statcast --season 2023`
2. Observe error in processing

**Expected behavior:**
Description of correct behavior

**Actual behavior:**
Current incorrect behavior

**Proposed fix:**
Technical approach

**Related:**
Fixes #[related-issue]
EOF
)" \
  --label "type:bug,priority:high,area:ingestion"
```

#### Method B: VS Code Integration

1. Open Source Control panel (`Ctrl+Shift+G`)
2. Click "Create Issue" button
3. Select appropriate template
4. Fill in technical details

---

## Phase 3: Branch Association & Development

### Step 5: Create Branch with Consistent Naming

```bash
# Convention: component/issue-number-brief-description
git checkout -b fix/statcast-db-pool/37-statcast-param-style
# OR
git checkout -b feature/mlb-ingestion/42-lahman-ingester
```

| Branch Type | Format | Example |
|-------------|--------|---------|
| Bug fix | `fix/<component>/<number>-<description>` | `fix/statcast/37-param-style` |
| Feature | `feature/<component>/<number>-<description>` | `feature/ingestion/42-lahman-ingester` |
| Documentation | `docs/<number>-<description>` | `docs/45-update-arch-notes` |
| Chore | `chore/<component>/<description>` | `chore/ci/update-workflow` |

### Step 6: Link Branch to Issue

```bash
# Push branch - GitHub auto-links with issue
git push origin fix/statcast-db-pool/37-statcast-param-style

# Or explicitly link (creates webhook connection)
gh issue edit 37 --add-to-project "mlb"
```

---

## Phase 4: Issue Metadata Management

### Step 7: Update Issue Status During Development

Track progress in MCP memory alongside GitHub status:

```
memory://issues/[number]/progress
├── status: "in_progress|blocked|needs_review|completed"
├── assignee: "developer-name"
├── branch: "fix/component/number-desc"
├── pr_number: null|#pr-number
└── completion_notes: "..."
```

### Step 8: Link Related Artifacts

Add cross-references in the issue:

- Link to related SQL files: `sql/050_staging/002_identity_trigger_and_indexes.sql`
- Link to tests: `tests/python/test_statcast.py`
- Link to design docs: `docs/ingestion.md`
- Link to prior issues: `Related to #23`

---

## Phase 5: Issue Resolution Protocol

### Step 9: Close with Reference

Issues are closed via commit message:

```bash
git commit -m "fix(statcast): correct parameter style to tuple format

Changed psycopg async parameter style from dict to tuple for consistency
with pool.connection() API. This fixes the mixed parameter style bug that
could cause runtime errors.

Fixes #37

Technical details:
- statcast.py:147 changed to (%s,) tuple style
- BaseIngester._get_source_endpoint_id updated
- All tests pass (433/433)"
```

---

## MCP Server Integration Points

### Database Validation (postgres MCP)
```sql
-- Before describing schema changes in issue
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'ingest_run';
```

### Sequential Thinking (sequential-thinking MCP)
Use for complex root cause analysis before writing issue body.

### File System References (filesystem MCP)
Reference for exact line numbers and code snippets.

### Architecture Context (fetch MCP  
Reference design decisions from `docs/architecture.md` and `OBJECTIVES.md`.

---

## Industry Standards Compliance

This process follows:

- **Conventional Commits** - Issue titles use `type(scope): description`
- **Semantic Versioning** - Critical/hotfix issues affect PATCH; features affect MINOR
- **GitFlow-lite** - `main` branch protected; feature branches merge via PR
- **Issue-Driven Development** - Every change traces to an issue

---

## Quick Reference Checklist

- [ ] Issue uses appropriate template
- [ ] Title is action-oriented and descriptive
- [ ] Priority label applied
- [ ] Area label applied (`area:sql`, `area:python`, `area:ingestion`, etc.)
- [ ] Technical details include file paths and line numbers
- [ ] Steps to reproduce documented (for bugs)
- [ ] Related issues linked
- [ ] Branch name follows convention
- [ ] MCP memory context captured (optional)
- [ ] Issue assigned to milestone

---

## Examples

### Bug Issue Template
```yaml
# Already configured in .github/ISSUE_TEMPLATE/bug-report.yml
# Extends with MCP context notes in body
```

### Feature Issue Template
```yaml
# Already configured in .github/ISSUE_TEMPLATE/feature-request.yml
# Add: "Proposed implementation" section with MCP-validated approaches
```

### Ingestion Issue Template
```yaml
# Already configured in .github/ISSUE_TEMPLATE/data-source.yml
# Add: SQL layer impact (040|050|060|070) in body
```

---

## Integration with .pr_agent.toml

PR Agent automatically processes issues with:
- Focus on: bugs, security, workspace_id gaps, ingestion violations
- Generate labels based on issue content
- Create structured PR descriptions

Ensure issues include technical context for optimal PR Agent performance.

---

## Maintenance

This document lives in `docs/issue-creation-process.md`. Update when:
- New MCP servers are added
- Workflow conventions change
- Issue templates evolve
- CI/CD process changes

Last updated: 2026-05-28