# Contributing to the MLB Analytics Platform

This repository contains the PostgreSQL-first MLB analytics and prediction platform, plus a growing Python application layer (`baseball`) for ingestion workers, APIs, agents, and tools.[cite:2]

The goal of this document is to make it easy to contribute in a consistent, safe way that respects the database-centric architecture already defined in `docs/` and `sql/`.[cite:2]

## Repository layout (quick recap)

See `docs/project-summary.md` and `docs/architecture.md` for the full picture.[cite:2]

At a high level:

- `sql/` – all schemas, tables, functions, indexes, constraints (the source of truth for the database).[cite:2]
- `docs/` – architecture, data-dictionary, security, ingestion, modeling, and operations design docs.[cite:2]
- `tests/sql/` – SQL smoke tests and validation queries.
- `baseball/` – Python app layer (CLI, settings, and future workers/APIs).
- `.github/` – CI workflows, issue templates, and GitHub configuration.[cite:9]

## Branching and pull requests

- Default branch: `main`.
- Feature branches: use descriptive names, for example:
  - `feature/python-app-layer`
  - `feature/ingest-retrosheet-cli`
  - `fix/sql-core-game-constraints`
- Always open a pull request into `main`.
- Keep PRs focused on a cohesive set of changes (schema change, CLI feature, CI improvement) rather than mixing many concerns.

### PR checklist (recommended)

Before requesting review:

- [ ] `sql/` changes compile and apply cleanly in order (010 → 090).
- [ ] Any new SQL objects are reflected in the relevant doc (`architecture.md`, `data-dictionary.md`, or others).[cite:2]
- [ ] Python code passes `python -m compileall baseball` and basic linting if configured.
- [ ] New CLI commands are documented in `docs/python-app-layer.md`.
- [ ] CI passes for the branch.

## SQL changes

The SQL design is intentionally layered and ordered; changing it requires care.[cite:2]

- New tables or functions should be added to the appropriate folder under `sql/`:
  - Extensions → `sql/010_extensions/`
  - Schemas → `sql/020_schemas/`
  - Meta/control plane → `sql/030_meta/`
  - Raw source landing → `sql/040_raw/`
  - Staging/identity bridges → `sql/050_staging/`
  - Canonical core tables → `sql/060_core/`
  - ML + ops layer → `sql/070_ml_ops/`
  - Shared functions → `sql/080_functions/`
  - Indexes/constraints → `sql/090_constraints_indexes/`
- Preserve execution order: new files should be named with numeric prefixes consistent with the existing pattern (e.g. `011_new_extension.sql`).
- If you change semantics (meaning, not just performance), update the relevant design doc in `docs/`.

## Python application layer (`baseball`)

The Python app layer is designed to sit on top of the existing schemas, not replace them.[cite:2]

- Package name and CLI: `baseball`.
- Python version: `>=3.12`.
- Core dependencies:
  - `SQLAlchemy` (async) + `asyncpg` for PostgreSQL access.
  - `Typer` for the CLI.
  - `Pydantic` for settings.
  - `rich` for nicer CLI output.

### Settings

Configuration is read from environment variables using `pydantic-settings` in `baseball/settings.py`.

Key env vars:

- `APP_ENV` – `local`, `test`, or `production`.
- `DATABASE_URL` – SQLAlchemy-style async URL (e.g. `postgresql+asyncpg://user:pass@host:5432/dbname`).
- `DB_SCHEMA_SEARCH_PATH` – optional comma-separated search_path override.
- `DEFAULT_WORKSPACE_CODE` – logical workspace for workspace-aware operations.
- `DEFAULT_QUEUE_NAME` – default `ops.jobqueue.queuename`.

For local development, copy `.env.example` to `.env` and adjust values.

### CLI commands

The Typer CLI lives in `baseball/cli.py`.

Initial commands:

- `baseball db-init` – **currently a dry-run stub** that prints the planned environment, `DATABASE_URL`, and `sql/` root. It will be extended to actually apply the numbered SQL folders in order.
- `baseball db-smoke` – **currently a dry-run stub** that prints the environment, `DATABASE_URL`, and `tests/sql` root. It will be extended to execute SQL smoke tests.

Future commands will cover ingestion workers, ML runs, and job inspection based on the `meta`, `ml`, and `ops` schemas.[cite:2]

## Testing

### SQL tests

- Add SQL tests under `tests/sql/`.
- Smoke tests should be idempotent and safe to run repeatedly against a test database.

### Python tests

- Place Python tests under `tests/` in a subdirectory such as `tests/python/`.
- Prefer `pytest`, but keep dependencies minimal.
- Aim for tests that exercise both CLI wiring and DB interactions using a disposable database.

## Code style and tooling

- Python: follow PEP 8 where reasonable; use type hints.
- Prefer async functions for DB interactions.
- Avoid putting business logic in ad-hoc scripts; prefer modules under `baseball/` and unit tests.

## Security and safety

The platform is designed with workspaces, row-level security, and API identities in mind.[cite:2]

- Avoid granting broad `SUPERUSER`-like privileges to application roles.
- Prefer the existing `auth`, `api`, and `ops` patterns for new operational flows.[cite:2]
- When designing agent-facing tools, ensure they operate through constrained verbs (e.g. enqueue job, read predictions) rather than arbitrary SQL.

If you’re unsure how to model a change, start a discussion issue before opening a PR.
