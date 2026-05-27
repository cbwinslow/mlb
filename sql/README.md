# SQL Directory Guide

This directory contains the PostgreSQL implementation for the MLB analytics platform. The SQL tree is already organized into numbered folders so apply order is explicit and reproducible, with extensions first, then schemas, then metadata, raw landing tables, staging, core, ML/ops, shared functions, and finally indexes and support objects.[1]

## Purpose

The SQL layer is the implementation surface for the database-first platform, not the place for broad architecture essays. Use `docs/` to understand why the system is shaped the way it is, and use `sql/` to inspect or apply the actual database objects.[1]

## Current tree

```text
sql/
├── 010_extensions/
│   ├── 001_extensions.sql
│   └── 002_optional_extensions.sql
├── 020_schemas/
│   ├── 001_schema.sql
│   ├── 002_auth_schema.sql
│   ├── 003_roles_and_grants.sql
│   └── 004_api_schema.sql
├── 030_meta/
│   ├── 001_source_registry.sql
│   └── 002_ingest_audit.sql
├── 040_raw/
│   ├── 001_raw_retrosheet.sql
│   ├── 002_raw_chadwick.sql
│   ├── 003_raw_statcast.sql
│   ├── 004_raw_mlbapi.sql
│   ├── 005_raw_lahman.sql
│   ├── 006_raw_web_sources.sql
│   ├── 006_raw_web_sources_migration_v2.sql
│   └── 007_raw_vector.sql
├── 050_staging/
│   ├── 001_identity_bridge.sql
│   ├── 002_identity_trigger_and_indexes.sql
│   ├── 003_game_identity.sql
│   ├── 005_game_identity_bridge.sql
│   └── 006_source_conformance.sql
├── 060_core/
│   ├── 001_core_entities.sql
│   ├── 002_core_gameplay.sql
│   ├── 003_core_relationships.sql
│   └── 005_serving_views.sql
├── 070_ml_ops/
│   ├── 001_ml_registry.sql
│   ├── 002_feature_store.sql
│   ├── 003_predictions_backtests_liveops.sql
│   ├── 004_workspace_security.sql
│   ├── 005_workspace_rls.sql
│   ├── 006_marts_materialized_views.sql
│   ├── 007_ingestion_orchestration.sql
│   ├── 008_api_service_contracts.sql
│   ├── 009_source_ingestion_specs.sql
│   └── 011_mart_views.sql
├── 080_functions/
│   ├── 001_meta_functions.sql
│   ├── 002_retrosheet_chadwick_functions.sql
│   ├── 003_statcast_mlbapi_functions.sql
│   ├── 004_lahman_web_functions.sql
│   ├── 005_staging_functions.sql
│   ├── 006_core_functions.sql
│   ├── 007_ml_ops_functions.sql
│   ├── 008_auth_security_functions.sql
│   ├── 009_mart_refresh_functions.sql
│   ├── 010_ingestion_ops_functions.sql
│   ├── 011_api_service_functions.sql
│   └── 012_source_ingestion_functions.sql
└── 090_constraints_indexes/
    ├── 002_retrosheet_chadwick_indexes.sql
    ├── 003_statcast_mlbapi_indexes.sql
    ├── 004_lahman_web_indexes.sql
    ├── 005_staging_indexes.sql
    ├── 006_core_indexes.sql
    ├── 007_ml_ops_indexes.sql
    ├── 008_auth_security_indexes.sql
    ├── 009_rls_support_indexes.sql
    ├── 010_mart_indexes.sql
    ├── 011_ingestion_ops_indexes.sql
    ├── 012_api_service_indexes.sql
    └── 013_source_ingestion_indexes.sql
```

## Apply order

Apply folders in numeric order.[1]

1. `010_extensions`
2. `020_schemas`
3. `030_meta`
4. `040_raw`
5. `050_staging`
6. `060_core`
7. `070_ml_ops`
8. `080_functions`
9. `090_constraints_indexes`

That order matches the documented dependency pattern: schemas before tables, tables before indexes, and shared functions before triggers or support logic that depend on them.[1]

## Folder roles

| Folder | Role |
|---|---|
| `010_extensions` | Installs required extensions `pgcrypto`, `citext`, and `btree_gist`, plus optional extension placeholders such as `pgaudit`, `pg_cron`, and `vector`.[1] |
| `020_schemas` | Creates the logical database shape, including `meta`, `ref`, raw source schemas, `stg`, `core`, `mart`, `util`, `auth`, and `api`, plus role/grant setup.[1] |
| `030_meta` | Creates the ingestion control plane, including `meta.source_system`, `meta.source_endpoint`, `meta.ingest_run`, `meta.source_file`, `meta.raw_payload_registry`, and `meta.ingest_error`.[1] |
| `040_raw` | Creates raw landing tables for Retrosheet, Chadwick, Statcast, MLB StatsAPI, Lahman, and web-oriented sources such as FanGraphs, Baseball Reference, ESPN, and odds payloads.[1] |
| `050_staging` | Creates cross-source identity and conformance structures such as player, team, venue, and game bridges.[1] |
| `060_core` | Creates the canonical warehouse entities and gameplay facts such as players, teams, venues, games, plate appearances, pitches, and serving views.[1] |
| `070_ml_ops` | Creates ML registry, feature store, predictions, backtests, simulations, workspace security, marts, ingestion orchestration, API contracts, and source-ingestion spec objects.[1] |
| `080_functions` | Creates shared helper functions for metadata, ingestion, normalization, key building, core logic, ML/ops, auth/security, mart refresh, API service, and source ingestion.[1] |
| `090_constraints_indexes` | Adds indexes and support objects for performance, RLS support, marts, ingestion operations, API service objects, and source-ingestion control tables.[1] |

## Baseline bootstrap

A new local database should enable required extensions first, then create schemas and roles, then continue through the folder order above.[1]

Example `psql` sequence:

```bash
createdb mlb
psql -d mlb -v ON_ERROR_STOP=1 -f sql/010_extensions/001_extensions.sql
psql -d mlb -v ON_ERROR_STOP=1 -f sql/010_extensions/002_optional_extensions.sql
psql -d mlb -v ON_ERROR_STOP=1 -f sql/020_schemas/001_schema.sql
psql -d mlb -v ON_ERROR_STOP=1 -f sql/020_schemas/002_auth_schema.sql
psql -d mlb -v ON_ERROR_STOP=1 -f sql/020_schemas/003_roles_and_grants.sql
psql -d mlb -v ON_ERROR_STOP=1 -f sql/020_schemas/004_api_schema.sql
```

After that, continue through `030_meta`, `040_raw`, `050_staging`, `060_core`, `070_ml_ops`, `080_functions`, and `090_constraints_indexes` in file order within each folder.[1]

## What is already implemented

The SQL inventory already includes concrete tables and functions for ingest auditability, raw-source storage, cross-source identity resolution, canonical baseball entities, prediction outputs, backtests, simulations, durable job queues, live polling, API contracts, and workspace-aware security support.[1]

That means the database layer is no longer just conceptual design; it already contains meaningful implementation for `meta`, raw schemas, `stg`, `core`, `ml`, `ops`, `auth`, `api`, and `mart` concerns.[1]

## Immediate improvements

- Add a small shell script or Make target that applies every SQL file in folder and filename order using `psql -v ON_ERROR_STOP=1`.[1]
- Add a smoke-test query file that verifies key schemas and representative tables exist after bootstrap, such as `meta.ingest_run`, `raw_retrosheet.record`, `core.games`, `ml.prediction_output`, and `ops.job_queue`.[1]
- Keep this README updated whenever a new numbered SQL file is added or execution order changes.[1]