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

The `meta` schema acts as the ingestion control plane. It tracks source systems, endpoints, ingest runs, source files, payload registries, and ingest errors. If the question is “what happened during ingestion?” the answer should begin in `meta`.

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

## Current state

At the current phase of the project, the database architecture is ahead of the application architecture. That is acceptable, but it means the next implementation step should be defining the Python repository structure and runtime boundaries that map cleanly onto the schemas described here.

## Immediate next architectural tasks

The next architecture-adjacent tasks should be:

1. finalize the SQL folder inventory and migration order,
2. define the Python project structure,
3. map worker responsibilities to `ops` and `meta` contracts,
4. define the FastAPI service boundary against `api`, `auth`, and `mart`,
5. decide which operations are exposed to agents as tools rather than raw SQL access.