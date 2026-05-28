# GitHub Workflow and Project Practices

This document describes how we use GitHub features for the MLB analytics platform repository.
It builds on the SQL-first architecture and is meant to keep contributions organized and observable.

## Issues and milestones

We use GitHub Issues to track work across SQL, Python, and infrastructure.

Recommended conventions:

- Use clear, action-oriented titles, e.g.:
  - `Implement baseball db-init CLI command`
  - `Add async SQLAlchemy models for core.games`
  - `Model: moneyline win probability v1`
- Use labels to categorize work, e.g.:
  - `area:sql`, `area:python`, `area:ingestion`, `area:modeling`, `area:ops`, `area:docs`.
  - `priority:high`, `priority:medium`, `priority:low`.
  - `type:bug`, `type:feature`, `type:task`.

### Milestones

Milestones should reflect meaningful platform increments. Suggested initial milestones:

- **v0.1 – Local Bootstrap**
  - Python app layer scaffolding (`pyproject.toml`, `baseball` package).
  - `baseball db-init` and `db-smoke` wired to real execution.
  - Local Postgres bootstrap documented.

- **v0.2 – Ingestion & Registry**
  - First source ingestion worker accessible via CLI.
  - Basic `ml.problemdefinition` / `ml.modeldefinition` flows via Python layer.

- **v0.3 – First E2E Model**
  - Feature snapshot creation.
  - Training and prediction runs stored in `ml.*` tables.
  - Basic job processing via `ops.jobqueue`.

Create and manage milestones via the GitHub UI, then assign issues to milestones as appropriate.

## Issue templates

Issue templates live under `.github/ISSUE_TEMPLATE/` and cover common flows:

- Bug reports.
- Feature requests.
- Data source/ingestion tasks.
- Modeling tasks.

See the individual template files for details. For optimal issue creation with technical context, follow the process in `docs/issue-creation-process.md`.

## Pull request workflow

- Open PRs against `main`.
- Link PRs to issues using `Fixes #123` or `Closes #123` where appropriate.
- Follow the standardized process in `docs/issue-creation-process.md` for creating well-formed issues with full technical context.
- Ensure CI is green before requesting review.
- Keep PR descriptions focused on *why* and *how*, not just *what*.

## Continuous Integration (CI)

All CI workflows live in `.github/workflows/`. The full current workflow inventory is:

| Workflow | Trigger | Purpose | Runner |
|---|---|---|---|
| `ci.yml` | push / PR to `main` | Combined fast gate: package install + import smoke | `ubuntu-latest` |
| `python-ci.yml` | push to `main`/`feature/*`, PR | Python lint (Ruff), type check (Mypy), pytest, coverage | `ubuntu-latest` |
| `sql-ci.yml` | SQL/docs file changes, PR | DB bootstrap via `scripts/bootstrap_db.sh`, pgTAP SQL tests | `ubuntu-latest` |
| `aider_ci_autofix.yml` | Issue labeled `aider` | Aider AI autofix on labeled issues | `ubuntu-latest` |
| `gemini_autofix.yml` | Issue / PR event | Gemini AI autofix | `ubuntu-latest` |
| `gemini_pr_review.yml` | PR opened/updated | Gemini automated code review | `ubuntu-latest` |
| `openrouter_review.yml` | PR opened/updated | OpenRouter AI review | `ubuntu-latest` |
| `auto_issue_creation.yml` | push to `main` | Auto-creates issues from TODOs/FIXMEs | `ubuntu-latest` |
| `codebase_review.yml` | Manual / scheduled | Comprehensive AI codebase review | `ubuntu-latest` |
| `issue_triage.yml` | Issue opened | Auto-label and triage new issues | `ubuntu-latest` |
| `labeler.yml` | PR opened/updated | Auto-applies path-based labels to PRs | `ubuntu-latest` |
| `pr-title.yml` | PR opened/updated | Enforces conventional commit title format | `ubuntu-latest` |

The intention is to have all SQL and Python changes validated automatically on each push and pull request.

### CI must-pass requirements

Before any PR merges to `main`, the following must be green:
- `ruff check .` — zero lint errors
- `mypy baseball/` — zero type errors
- `pytest tests/python/ --cov=baseball` — all tests pass, coverage target met
- SQL bootstrap and pgTAP tests pass against a clean `postgres:16` container

## Self-hosted runner

This repository has a **self-hosted GitHub Actions runner** registered locally. It is used for:

- Integration tests that require a live, persistent PostgreSQL instance (the homelab Postgres).
- Heavy fixture-loading jobs (Chadwick full event file, Lahman full backfill) that exceed typical GitHub-hosted runner time limits.
- Workflows where local filesystem access to data archives is needed.

### Using the self-hosted runner in a workflow

To route a job to the self-hosted runner, set:

```yaml
runs-on: [self-hosted, linux]
```

To run a job on both GitHub-hosted and self-hosted environments (e.g. for portability testing):

```yaml
strategy:
  matrix:
    runner: [ubuntu-latest, [self-hosted, linux]]
runs-on: ${{ matrix.runner }}
```

### Runner maintenance

- The runner process is managed as a systemd service on the homelab host.
- Check runner status at: **Repository Settings → Actions → Runners**.
- If the runner shows as offline, log into the homelab host and restart the service.
- See `docs/local-runner.md` for full setup, registration, and maintenance instructions.

## Package management with `uv`

All Python dependency management uses **`uv`**. Do not use `pip install` directly in workflows or local dev.

### Installing the project locally

```bash
# Install all runtime deps
uv sync

# Install runtime + dev deps (for testing, linting)
uv sync --group dev

# Run any tool through uv
uv run pytest
uv run ruff check .
uv run mypy baseball/
```

### In GitHub Actions workflows

```yaml
- name: Install uv
  uses: astral-sh/setup-uv@v3
  with:
    version: "latest"

- name: Install project + dev deps
  run: uv sync --group dev

- name: Run tests
  run: uv run pytest tests/python/ --cov=baseball --cov-report=xml
```

Do not use `actions/setup-python` + `pip install` for new workflows — use `astral-sh/setup-uv` instead.

## Testing workflow

See `docs/testing.md` for the comprehensive test guide. The short version:

- **Python tests**: `uv run pytest tests/python/ -v --cov=baseball`
- **SQL unit tests** (pgTAP): `pg_prove -d mlb_dev tests/sql/unit/`
- **SQL integration tests**: `pg_prove -d mlb_dev tests/sql/integration/`
- **SQL bootstrap smoke**: `psql -d mlb_dev -f tests/sql/bootstrap/001_smoke.sql`
- **Lint**: `uv run ruff check . && uv run ruff format --check .`
- **Type check**: `uv run mypy baseball/`

Test output, coverage reports, and pgTAP TAP output are all uploaded as CI artifacts.

## Projects and triage

GitHub Projects can be used to organize work into a board with columns such as:

- `Backlog`
- `Ready`
- `In Progress`
- `In Review`
- `Done`

Recommended triage flow:

1. New issues land in `Backlog`.
2. During triage sessions, label issues, assign them to milestones, and move them to `Ready`.
3. When work begins, move issues to `In Progress` and link them to a branch.
4. When a PR is opened, move to `In Review`.
5. After merge and deployment, move to `Done`.

This workflow helps keep changes visible across ingestion, modeling, and operations.

## Security and access

The `docs/security.md` file describes workspace, role, and row-level security in the database.

At the GitHub level:

- Use protected branches for `main` where appropriate.
- Require status checks (CI) to pass before merge.
- Use code reviews for schema and security-sensitive changes.

## Updating this document

As we add more automation (e.g. release workflows, label bots, or project automation), this document should be updated to describe how those pieces fit into the overall platform lifecycle.