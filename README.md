# MLB Analytics Platform

A PostgreSQL-first database platform for baseball analytics, sabermetric research, prediction modeling, and live game workflows.

## Overview

This repository contains the database foundation and design documentation for an MLB analytics and prediction platform. The platform treats PostgreSQL as the central system of record — not a passive storage layer, but the durable home for baseball entities, ingestion history, model metadata, operational workflows, access boundaries, and service contracts.

The current repository is organized around two top-level working directories:

| Path | Role |
|------|------|
| `docs/` | Design and reference documents covering architecture, schema boundaries, security, ingestion, modeling, and operations |
| `sql/` | SQL implementation for schemas, tables, functions, constraints, indexes, and all other database objects |
## Schema Refactor (May 2026)

The database schema has been refactored to decouple plate appearances from pitch telemetry and introduce a canonical game identity bridge.
See `plans/refactor-blueprint.md` for details and the updated DDL in `sql/060_core/002_core_gameplay.sql`.
## What the platform supports

- Historical and live baseball data ingestion (Retrosheet, Chadwick, Lahman, MLB StatsAPI, Statcast, FanGraphs, Baseball Reference, ESPN, odds providers)
- Canonical baseball entity and event storage
- Sabermetric and prediction model workflows
- Durable operational control for loaders, workers, and live polling
- Multi-user, API, and agent-driven use cases (future)

## Where to start

| Goal | Starting point |
|------|---------------|
| Understand the overall system design | `docs/architecture.md` |
| Know what schemas and tables exist | `docs/data-dictionary.md` |
| Understand security and access control | `docs/security.md` |
| Understand how data is ingested | `docs/ingestion.md` |
| Understand modeling and prediction design | `docs/modeling.md` |
| Understand job scheduling and operations | `docs/operations.md` |
| Apply the SQL to a database | `sql/README.md` |

## Technology

- **Database:** PostgreSQL
- **Required extensions:** `pgcrypto`, `citext`, `btree_gist`
- **Optional extensions:** `pgaudit`, `pg_cron`, `pgvector`, TimescaleDB
- **Planned application layer:** Python, FastAPI, ingestion workers, agent tool layer

## Current phase

This project is in the foundational platform phase. The SQL schema design and documentation are ahead of the application layer. Completed work:

- ✅ Full SQL schema with 9 pipeline layers (`sql/010_` through `sql/090_`)
- ✅ Python ingestion framework with CLI (`baseball ingest *`, `baseball enrich`)
- ✅ All 7 source ingesters implemented (retrosheet, statcast, mlbapi, fangraphs, bref, espn, odds)
- ✅ Vector database foundation with Haystack/Qdrant/pgvector integration
- ✅ Test suite with 266 passing tests
- ✅ Configuration fixes: `pyproject.toml` dev dependencies, `.gitignore` cleanup

Immediate next steps are:

1. Create Alembic migrations for sql/010-090 directories (DEC-009)
2. Add tests for new ingestion modules
3. Implement Parquet/S3 export CLI for ML training workflows (DEC-012)
4. Add `mv_batter_spray_heatmap` and `mv_pitcher_zone_profile` materialized views