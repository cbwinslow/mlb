# MLB Analytics Platform Architecture

## Purpose

This document defines the current architecture of the MLB analytics platform as it exists in the SQL-first design phase. The goal of the platform is to support historical baseball research, sabermetric analysis, prediction modeling, live game monitoring, agent-assisted workflows, and future multi-user application serving from one coherent data platform.

The architecture is intentionally built around PostgreSQL as the central system of record. Instead of treating the database as a passive storage layer, the design uses it as the durable home for baseball entities, ingestion history, model metadata, operational workflows, access boundaries, and service contracts.

## Core principles

The current architecture follows these principles:

- Preserve source fidelity before normalization.
- Separate raw ingestion from canonical baseball truth.
- Treat modeling as a registry-driven platform, not a one-model script.
- Store operational state explicitly instead of hiding it in worker memory or cron logs.
- Support both single-user homelab deployment and future shared multi-user deployment.
- Keep the database design compatible with a future API, GUI, and agent tool layer.

## Top-level architecture

The platform is organized into a set of logical layers:

1. **Source ingestion layer**: collects data from external systems such as Retrosheet, Chadwick, Lahman, MLB StatsAPI, Statcast, FanGraphs, Baseball Reference, ESPN, and odds providers.
2. **Raw storage layer**: stores source-faithful payloads and extracted records in dedicated `raw_*` schemas.
3. **Conformance layer**: reconciles player, team, venue, and game identities across source systems.
4. **Canonical warehouse layer**: stores normalized baseball entities and gameplay facts in the `core` schema.
5. **Modeling layer**: stores feature definitions, datasets, training runs, backtests, predictions, and simulations in the `ml` schema.
6. **Operations layer**: manages job scheduling, queueing, retries, live polling, and refresh tracking in the `ops` schema.
7. **Security and ownership layer**: stores users, workspaces, service accounts, entitlements, and source controls in the `auth` schema.
8. **Service layer**: stores API plans, request logs, idempotency records, webhook endpoints, and usage rollups in the `api` schema.
9. **Serving layer**: exposes optimized views and materialized summaries in the `mart` schema.

This layered model is meant to stop responsibilities from bleeding together. A raw payload should not be mistaken for canonical truth, and a prediction output should not be mistaken for a source fact.

## Schema architecture

### `meta`

The `meta` schema acts as the ingestion control plane. It tracks source systems, endpoints, ingest runs, source files, payload registries, and ingest errors. If the question is "what happened during ingestion?" the answer should begin in `meta`.

### `ref`

The `ref` schema stores low-volatility lookup data and standard enumerations used across the rest of the system.

### `raw_retrosheet`

This schema stores Retrosheet event-file content in source-faithful form. It is designed for record families like `info`, `start`, `play`, `sub`, `comment`, and related event file structures.

### `raw_chadwick`

This schema stores structured extract outputs derived through Chadwick tooling such as `cwevent`, `cwgame`, and `cwsub`.

### `raw_lahman`

This schema stores Lahman tables in a mostly direct relational form and is useful both for historical baseball coverage and identity support.

### `raw_mlbapi`

This schema stores MLB StatsAPI request/payload history and expanded API-driven baseball data including schedule, game, and live structures.

### `raw_statcast`

This schema stores Statcast search and pitch-level export data, typically ingested through chunked pulls.

### `raw_fangraphs`, `raw_bref`, `raw_espn`, `raw_odds`

These schemas store raw source captures from web, scraping, or odds workflows.

### `stg`

The `stg` schema handles reconciliation. This is where source-specific identities are mapped into stable canonical entities for players, teams, venues, and games.

### `core`

The `core` schema is the canonical baseball warehouse. It is expected to contain the long-lived normalized truth model for players, teams, venues, games, roster assignments, plate appearances, pitches, and lineage maps.

### `ml`

The `ml` schema is the modeling and experimentation layer. It stores problem definitions, feature sets, feature snapshots, dataset definitions, model families, model definitions, training runs, prediction runs, backtests, evaluations, and simulations.

### `ops`

The `ops` schema is the operational ledger for the platform. It stores schedules, queue items, dead letters, loader specs, live polling state, and materialized view refresh tracking.

### `auth`

The `auth` schema stores user, organization, and workspace boundaries plus service identities, API keys, entitlements, and source controls.

### `api`

The `api` schema stores service-facing contracts that the future FastAPI or application layer will use for plans, quotas, idempotency, request logging, and webhooks.

### `mart`

The `mart` schema is the read-optimized serving layer. It contains views and materialized views intended for dashboards, APIs, model browsers, recent prediction surfaces, and other performance-sensitive reads.

### `util`

The `util` schema stores helper functions, triggers, and shared utility functions used across operational and service workflows.

## Data flow

The intended high-level data flow is:

1. A source is registered in `meta.source_system` and optionally `meta.source_endpoint`.
2. An ingest run is created and associated with a loader profile or source-specific spec.
3. Raw payloads or files land in a `raw_*` schema.
4. Conformance logic in `stg` reconciles identities and source mismatches.
5. Canonical entities and gameplay facts are built in `core`.
6. Features, datasets, and model artifacts are generated in `ml`.
7. Jobs, pollers, and refreshes are coordinated in `ops`.
8. Users, workspaces, service accounts, and source permissions are enforced through `auth`.
9. APIs and future applications interact through `api` and read optimized objects in `mart`.

This separation is important because it keeps ingestion rerunnable and keeps modeling and app features from depending directly on fragile raw-source assumptions.

## Ownership model

The platform uses a hybrid ownership model:

- baseball truth data is globally shared,
- workflow objects are workspace-owned,
- platform administration remains centrally managed.

This means canonical players, teams, venues, and games do not need to be duplicated per user, while models, backtests, simulations, jobs, API artifacts, and other user-created assets can belong to a workspace.

That structure supports both a single-user homelab install and a future multi-user deployment without needing separate databases per user.

## Security architecture

Security is layered into the architecture rather than bolted on later. The design includes:

- PostgreSQL role/group-role separation,
- workspace-aware row ownership,
- Row Level Security on selected shared tables,
- source-level legal and quality controls,
- service accounts and API keys for app access,
- future audit support through pgAudit and targeted table-level history if needed.

The goal is to make the shared-database model safe enough for future hosted or team-based use without overcomplicating the current homelab deployment.

## Operational architecture

Operational control lives in the database. The job system is designed to represent:

- scheduled jobs,
- queue items,
- retries with backoff,
- dead-letter movement,
- live game pollers,
- refresh logs,
- source loader specs,
- endpoint strategies.

This is a deliberate choice. Workers, APIs, and agents should all be able to inspect and act on the same durable operational state instead of each maintaining their own private view of job status.

## Future application architecture

The current SQL design expects a future Python implementation with at least these components:

- **Ingestion workers** for source pulls, file processing, parsing, and landing raw data.
- **Operational workers** for queue consumption, retries, refreshes, polling, and background workflows.
- **FastAPI service** for authenticated application/API access.
- **Agent tool layer** for ForgeCode, OpenCode, Gemini, Agno, or other agent frameworks to call controlled tools instead of improvising direct DB behavior.
- **Optional web UI** for browsing predictions, models, jobs, and sabermetric research surfaces.

## Testing architecture

Testing is a first-class concern across all three layers of the platform: SQL, Python, and CI/CD.

### SQL testing strategy

SQL tests use **pgTAP**, a PostgreSQL unit testing framework that runs assertions inside the database as plain SQL. Tests are organized under `tests/sql/` and are grouped into:

- `tests/sql/bootstrap/` — smoke tests that verify the schema bootstraps without error.
- `tests/sql/constraints/` — meta-level checks verifying that required schemas, tables, columns, and indexes exist.
- `tests/sql/unit/` — pgTAP unit tests for functions, triggers, and stored procedures.
- `tests/sql/integration/` — integration tests that insert fixture data and assert that multi-step workflows produce correct results.

The most critical SQL test areas are:
- The player identity trigger fires correctly and inserts placeholders for new MLBAM IDs.
- Orphaned pitch records are detected by `stg.fn_detect_orphaned_pitches()`.
- Cross-validation functions correctly flag ID divergence against Chadwick.
- Partial unique indexes on `stg.player_identity` enforce key uniqueness while allowing NULLs.

### Python testing strategy

Python tests use **pytest** with these plugins:
- `pytest-asyncio` for async SQLAlchemy and asyncpg code paths.
- `pytest-cov` for line and branch coverage reporting.
- `factory-boy` for fixture generation.
- `freezegun` for deterministic datetime behavior in enrichment worker tests.

Tests are organized under `tests/python/` and cover:
- Unit tests for settings, configuration, and CLI commands.
- Unit tests for the player identity enrichment worker (with mocked external API calls).
- Integration tests for the full ingest-trigger-enrich cycle against a real test database.

See `docs/testing.md` for the full test guide, fixture patterns, and coverage targets.

### Linting and type checking

All Python code is linted with **Ruff** and type-checked with **Mypy**. Configuration lives in `pyproject.toml` under `[tool.ruff]`, `[tool.ruff.lint]`, and `[tool.mypy]`. Both are enforced in CI.

SQL files are linted with **sqlfluff** using the `postgres` dialect. Configuration lives in `.sqlfluff` at the repo root.

## CI/CD and self-hosted runner architecture

### GitHub Actions workflows

The CI/CD system is built on GitHub Actions. Relevant workflows:

| Workflow | Trigger | Purpose |
|---|---|---|
| `ci.yml` | push/PR | Combined Python + SQL fast gate |
| `python-ci.yml` | push/PR | Python lint, type check, pytest |
| `sql-ci.yml` | SQL/docs changes | DB bootstrap, pgTAP SQL tests |
| `aider_ci_autofix.yml` | Issue label | Aider AI autofix on labeled issues |
| `gemini_autofix.yml` | Issue/PR | Gemini AI autofix |
| `gemini_pr_review.yml` | PR | Gemini code review |
| `openrouter_review.yml` | PR | OpenRouter AI review |
| `issue_triage.yml` | Issue created | Auto-label and triage |

### Self-hosted runner

The platform has a **self-hosted GitHub Actions runner** registered to this repository. This runner is used for:
- Heavy SQL test jobs that require a live PostgreSQL instance without the 6-hour GitHub-hosted limit.
- Integration tests that need access to local data files or the homelab Postgres instance.
- Jobs that benefit from faster local I/O (e.g. bulk Chadwick or Lahman fixture loading).

To use the self-hosted runner in a workflow job, set:

```yaml
runs-on: [self-hosted, linux]
```

For jobs that should run on both GitHub-hosted and self-hosted environments, use a matrix:

```yaml
strategy:
  matrix:
    runner: [ubuntu-latest, [self-hosted, linux]]
runs-on: ${{ matrix.runner }}
```

See `docs/local-runner.md` for setup instructions for the self-hosted runner.

## Current state

At the current phase of the project, the database architecture is ahead of the application architecture. That is acceptable, but it means the next implementation step should be defining the Python repository structure and runtime boundaries that map cleanly onto the schemas described here.

## Immediate next architectural tasks

The next architecture-adjacent tasks should be:

1. finalize the SQL folder inventory and migration order,
2. define the Python project structure,
3. map worker responsibilities to `ops` and `meta` contracts,
4. define the FastAPI service boundary against `api`, `auth`, and `mart`,
5. decide which operations are exposed to agents as tools rather than raw SQL access,
6. complete the test infrastructure setup (see Issues #14, #15, #16).
