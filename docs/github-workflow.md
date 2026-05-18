# GitHub Workflow and Project Practices

This document describes how we use GitHub features for the MLB analytics platform repository.
It builds on the SQL-first architecture and is meant to keep contributions organized and observable.[cite:2]

## Issues and milestones

We use GitHub Issues to track work across SQL, Python, and infrastructure.

Recommended conventions:

- Use clear, action-oriented titles, e.g.:
  - `Implement baseball db-init CLI command`
  - `Add async SQLAlchemy models for core.game`
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
  - Basic `ml.problemdefinition` / `ml.modeldefinition` flows via Python layer.[cite:2]

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

See the individual template files for details.

## Pull request workflow

- Open PRs against `main`.
- Link PRs to issues using `Fixes #123` or `Closes #123` where appropriate.
- Ensure CI is green before requesting review.
- Keep PR descriptions focused on *why* and *how*, not just *what*.

## Continuous Integration (CI)

Current workflows (see `.github/workflows/`):[cite:9]

- `sql-ci.yml` – runs SQL-related checks and tests.
- `python-ci.yml` – runs Python packaging checks and basic CLI sanity tests (added with the Python app layer).

The intention is to have all SQL and Python changes validated automatically on each push and pull request.

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

The `docs/security.md` file describes workspace, role, and row-level security in the database.[cite:2]

At the GitHub level:

- Use protected branches for `main` where appropriate.
- Require status checks (CI) to pass before merge.
- Use code reviews for schema and security-sensitive changes.

## Updating this document

As we add more automation (e.g. release workflows, label bots, or project automation), this document should be updated to describe how those pieces fit into the overall platform lifecycle.
