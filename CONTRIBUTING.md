# Contributing to the MLB Analytics Platform

This repository contains the PostgreSQL-first MLB analytics and prediction platform, plus a growing Python application layer (`baseball`) for ingestion workers, APIs, agents, and tools.

The goal of this document is to make it easy to contribute in a consistent, safe way that respects the database-centric architecture already defined in `docs/` and `sql/`.

## Development Setup

```bash
# Clone
git clone https://github.com/cbwinslow/mlb.git
cd mlb

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate

# Install in editable mode with all deps
pip install -e .

# Copy env template
cp .env.example .env
# Edit .env with your local DATABASE_URL

# Verify CLI works
baseball --help
baseball db-init
```

## Repository layout (quick recap)

See `docs/project-summary.md` and `docs/architecture.md` for the full picture.

At a high level:

- `sql/` – all schemas, tables, functions, indexes, constraints (the source of truth for the database).
- `docs/` – architecture, data-dictionary, security, ingestion, modeling, and operations design docs.
- `tests/sql/` – SQL smoke tests and validation queries.
- `baseball/` – Python app layer (CLI, settings, and future workers/APIs).
- `.github/` – CI workflows, issue templates, and GitHub configuration.

## Branching and pull requests

- Default branch: `main` — stable, always deployable.
- Feature branches: use descriptive names following these conventions:
  - `feature/<name>` — new features (e.g. `feature/python-app-layer`, `feature/ingest-retrosheet-cli`)
  - `fix/<name>` — bug fixes (e.g. `fix/sql-core-game-constraints`)
  - `docs/<name>` — documentation only
  - `chore/<name>` — housekeeping (deps, CI, etc.)
- Always open a pull request into `main`.
- Keep PRs focused on a cohesive set of changes (schema change, CLI feature, CI improvement) rather than mixing many concerns.

### PR checklist (recommended)

Before requesting review:

- [ ] All AI review comments addressed before requesting human review
- [ ] `sql/` changes compile and apply cleanly in order (010 → 090).
- [ ] Any new SQL objects are reflected in the relevant doc (`architecture.md`, `data-dictionary.md`, or others).
- [ ] Python code passes `python -m compileall baseball` and basic linting if configured.
- [ ] New CLI commands are documented in `docs/python-app-layer.md`.
- [ ] Tests added/updated for new code.
- [ ] `pyproject.toml` updated if new dependencies added.
- [ ] `ROADMAP.md` updated if milestone items completed.
- [ ] No hardcoded credentials or secrets.
- [ ] Database URL is never printed unmasked.
- [ ] CI passes for the branch.

## Commit Message Format

```
type(scope): short description

Longer explanation if needed.

Fixes #issue-number
```

Types: `feat`, `fix`, `docs`, `chore`, `test`, `refactor`, `ci`

## SQL changes

The SQL design is intentionally layered and ordered; changing it requires care.

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

The Python app layer is designed to sit on top of the existing schemas, not replace them.

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

Future commands will cover ingestion workers, ML runs, and job inspection based on the `meta`, `ml`, and `ops` schemas.

## Testing

### SQL tests

- Add SQL tests under `tests/sql/`.
- Smoke tests should be idempotent and safe to run repeatedly against a test database.

### Python tests

- Place Python tests under `tests/` in a subdirectory such as `tests/python/`.
- Prefer `pytest`, but keep dependencies minimal.
- Aim for tests that exercise both CLI wiring and DB interactions using a disposable database.

```bash
pytest tests/
```

## Code style and tooling

- Python: `ruff` for linting, `black` for formatting; follow PEP 8 where reasonable; use type hints.
- SQL: lowercase keywords, snake_case identifiers.
- Prefer async functions for DB interactions.
- All settings via `baseball.settings.AppSettings` — never `os.environ` directly.
- Avoid putting business logic in ad-hoc scripts; prefer modules under `baseball/` and unit tests.

## Security and safety

The platform is designed with workspaces, row-level security, and API identities in mind.

- Avoid granting broad `SUPERUSER`-like privileges to application roles.
- Prefer the existing `auth`, `api`, and `ops` patterns for new operational flows.
- When designing agent-facing tools, ensure they operate through constrained verbs (e.g. enqueue job, read predictions) rather than arbitrary SQL.

If you're unsure how to model a change, start a discussion issue before opening a PR.
