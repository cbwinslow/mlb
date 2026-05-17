# Python Application Layer (`baseball`)

This document describes the Python application layer that sits on top of the PostgreSQL-first MLB analytics platform.
It is intentionally aligned with the architecture and schema design documented in `docs/architecture.md` and `docs/project-summary.md`.[cite:2]

## Purpose

The Python layer is responsible for:

- Providing a CLI (`baseball`) for developers and operators.
- Encapsulating connections to the PostgreSQL database (`meta`, `raw_*`, `stg`, `core`, `ml`, `ops`, `auth`, `api`, `mart`, `util`).[cite:2]
- Implementing ingestion workers, model training/scoring orchestration, and job processing.
- Exposing safe operations to future FastAPI services and AI agents.

The PostgreSQL schemas remain the system of record; the Python layer orchestrates rather than redefines them.[cite:2]

## Project layout

The recommended repository layout from `docs/project-summary.md` includes an `app/` directory for runtime components.
In this implementation, the Python package is called `baseball` and lives at the repository root, complementing `sql/` and `docs/`.[cite:2]

Key paths:

- `sql/` – all database objects (extensions, schemas, tables, functions, indexes, constraints).
- `docs/` – design docs for architecture, data dictionary, security, ingestion, modeling, and operations.[cite:2]
- `baseball/` – Python package.
- `.github/` – CI, issue templates, and GitHub configuration.

Within `baseball/`:

- `baseball/settings.py` – Pydantic-based configuration model.
- `baseball/cli.py` – Typer-based CLI entry point.
- Future subpackages (planned):
  - `baseball/db` – async engine/session management, SQLAlchemy models.
  - `baseball/ingestion` – wrappers around `meta` and `ops` for source ingest workflows.[cite:2]
  - `baseball/ml` – helpers for `ml.problemdefinition`, `ml.featureset`, `ml.modeldefinition`, runs, and predictions.[cite:2]
  - `baseball/ops` – job queue and live polling helpers around `ops.jobqueue`, `ops.livegamepoller`, and related tables.[cite:2]
  - `baseball/api` – future FastAPI app.

## Settings and environments

Settings are defined in `baseball/settings.py` using `pydantic-settings`.

### App environments

- `APP_ENV=local` – developer machines.
- `APP_ENV=test` – CI and automated test databases.
- `APP_ENV=production` – real deployments.

The `AppSettings` object also carries:

- `LOG_LEVEL` – `DEBUG`, `INFO`, `WARNING`, or `ERROR`.
- A nested `DatabaseSettings` model (URL, search_path override).
- A `WorkspaceSettings` model (default workspace code).
- An `OpsSettings` model (default queue name).

The canonical way to access configuration is via `get_settings()`.

### Database URL and search path

- `DATABASE_URL` is required and must be a valid SQLAlchemy URL (usually async via `postgresql+asyncpg`).
- `DB_SCHEMA_SEARCH_PATH` is optional; if provided, the application can set `search_path` when opening connections.

The search path should generally include the schemas described in `docs/data-dictionary.md` (meta, ref, raw_retrosheet, raw_chadwick, raw_lahman, raw_statcast, raw_mlbapi, raw_fangraphs, raw_bref, raw_espn, raw_odds, stg, core, mart, ml, ops, auth, api, util).[cite:2]

## CLI commands

The CLI is implemented with Typer in `baseball/cli.py`.

### `baseball db-init`

- Reads configuration via `get_settings()`.
- Locates the `sql/` directory relative to the repo root.
- Currently prints a plan (environment, `DATABASE_URL`, SQL root) and exits.
- Will be extended to:
  - Walk `sql/010_extensions/` → `sql/090_constraints_indexes/` in lexicographic order.
  - Apply each SQL file to the configured database.
  - Optionally support `--dry-run` and `--from`/`--to` folder filters.

### `baseball db-smoke`

- Reads configuration via `get_settings()`.
- Locates `tests/sql/`.
- Currently prints a plan (environment, `DATABASE_URL`, tests root) and exits.
- Will be extended to:
  - Connect to the configured database.
  - Execute smoke test SQL files under `tests/sql/`.
  - Report pass/fail status with `rich` tables.

## Future directions

The following Python-layer capabilities are planned to align with the existing SQL design:

1. **Async DB infrastructure**
   - Async SQLAlchemy engine + session factory.
   - Workspace-aware connection setup that sets `app.currentworkspace` and related settings for RLS.[cite:2]

2. **Ingestion workers**
   - Python wrappers around `meta.ingest_run`, `ops.sourceloaderspec`, `ops.jobqueue`, and `util.startingestrun` / `util.finishingestrun`.
   - CLI commands and/or workers that enqueue and process jobs for Retrosheet, Chadwick, Statcast, MLB StatsAPI, Lahman, and other sources.[cite:2]

3. **Model orchestration**
   - Helper functions and CLI commands to:
     - Register problems and featuresets.
     - Launch training runs (`ml.trainingrun`).
     - Launch prediction runs and store outputs (`ml.predictionrun`, `ml.predictionoutput`).[cite:2]

4. **Operations and monitoring**
   - Commands to inspect `ops.jobqueue`, `ops.jobdeadletter`, `ops.livegamepoller`, and materialized view refresh logs.[cite:2]

5. **Agent tool layer**
   - Controlled, workspace-aware operations that agents can invoke (e.g. “run this model,” “show latest predictions”), without granting full SQL access.

This document should be updated as the Python layer evolves.
