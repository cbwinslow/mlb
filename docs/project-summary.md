# MLB Prediction Analytics Platform: Project Documentation

## Overview

This document summarizes the PostgreSQL-first MLB prediction analytics platform designed so far, including directory structure, SQL batches, schemas, major tables, functions, and architectural rationale. The design currently covers raw ingestion, identity resolution, canonical baseball entities, and an extensible machine-learning and live-operations layer. PostgreSQL supports multiple users and concurrent connections natively, while extensions such as pgAudit, pg_cron, pgvector, and optionally TimescaleDB can improve auditability, scheduling, semantic search, and time-series workflows.[cite:202][cite:203][cite:199][cite:191][cite:194][cite:201]

The current architecture is compatible with both single-user and multi-user deployments, and it can evolve toward a centralized hosted system with API access, role-based controls, audit logging, and optional tenant isolation through Row Level Security if a multi-tenant product is pursued later.[cite:215][cite:210][cite:218][cite:220][cite:211][cite:212]

## Documentation timing

Project documentation can be started now without harming the SQL work, but it will be incomplete until the remaining batches are finalized. The best approach is to maintain a **living design document** now, then produce a polished implementation manual and deployment guide after the SQL files, ingestion code, API layer, and security choices are finished.[cite:212][cite:220]

That means documentation should not wait until the very end, because the project is already large enough that structure, naming, and intent benefit from being captured while decisions are fresh. At the same time, some sections below should be treated as version 0.1 and updated after future batches for security, marts, performance tuning, API design, and ingestion workers are added.

## Recommended repository layout

```text
project-root/
├── README.md
├── docs/
│   ├── architecture.md
│   ├── data-dictionary.md
│   ├── deployment.md
│   ├── security.md
│   ├── api.md
│   ├── ingestion.md
│   ├── modeling.md
│   └── operations.md
├── sql/
│   ├── 010_extensions/
│   ├── 020_schemas/
│   ├── 030_meta/
│   ├── 040_raw/
│   ├── 050_staging/
│   ├── 060_core/
│   ├── 070_ml_ops/
│   ├── 080_functions/
│   └── 090_constraints_indexes/
├── ingestion/
│   ├── retrosheet/
│   ├── chadwick/
│   ├── statcast/
│   ├── mlbapi/
│   ├── lahman/
│   ├── odds/
│   └── shared/
├── app/
│   ├── api/
│   ├── workers/
│   ├── agents/
│   ├── services/
│   └── ui/
├── models/
│   ├── training/
│   ├── scoring/
│   ├── backtests/
│   ├── simulations/
│   └── registry/
├── infra/
│   ├── docker/
│   ├── systemd/
│   ├── k8s/
│   └── terraform/
└── tests/
    ├── sql/
    ├── ingestion/
    ├── api/
    └── models/
```

This layout matches the current SQL layering and leaves room for ingestion workers, APIs, agents, UI, model code, and deployment assets. It also supports eventual redistribution in multiple environments, from homelab installs to hosted centralized deployments.[cite:211][cite:212][cite:220]

## SQL directory map

The SQL design is currently organized into nine numbered folders so execution order stays explicit and reproducible.

| Directory | Purpose |
|---|---|
| `sql/010_extensions/` | PostgreSQL extensions such as `pgcrypto`, `citext`, and `btree_gist`; future candidates include `pgAudit`, `pg_cron`, `pgvector`, and optionally TimescaleDB.[cite:125][cite:129][cite:199][cite:202][cite:203][cite:191] |
| `sql/020_schemas/` | Logical schema creation for `meta`, `ref`, raw source schemas, `stg`, `core`, `mart`, `util`, plus later `ml` and `ops`. |
| `sql/030_meta/` | Source registry, endpoint registry, ingest runs, source files, payload hash registry, and ingest errors. |
| `sql/040_raw/` | Raw source-faithful landing tables for Retrosheet, Chadwick, Lahman, Statcast, MLB StatsAPI, FanGraphs, Baseball Reference, ESPN, and odds feeds. |
| `sql/050_staging/` | Identity bridges and source conformance tables that map source-specific identifiers into cross-source entities. |
| `sql/060_core/` | Canonical baseball entities and gameplay facts such as players, teams, venues, games, rosters, plate appearances, and pitches. |
| `sql/070_ml_ops/` | Model registry, feature store, training runs, backtests, predictions, simulations, live polling, and scheduled job metadata. |
| `sql/080_functions/` | Utility, hashing, normalization, key-building, ingest helper, and trigger functions. |
| `sql/090_constraints_indexes/` | Indexes and supporting performance objects separated from table DDL for easier iteration and tuning. |

## Schemas and responsibilities

The current design uses schema separation to keep source fidelity, conformance, canonical modeling, and operational workloads distinct.

| Schema | Responsibility |
|---|---|
| `meta` | Source systems, endpoints, ingest runs, files, payload hashes, and ingest errors. |
| `ref` | Reserved for reference/lookup tables and canonical enumerations not yet fully designed. |
| `raw_retrosheet` | Source-order Retrosheet event file storage and parsed record families.[cite:70][cite:71] |
| `raw_chadwick` | Chadwick `cwevent`, `cwgame`, and `cwsub` structured extraction outputs.[cite:75][cite:81][cite:135] |
| `raw_lahman` | Raw Lahman relational tables, including `People`, `Batting`, `Pitching`, `Fielding`, and `Teams`.[cite:76][cite:145][cite:143] |
| `raw_statcast` | Baseball Savant / Statcast search metadata and pitch-level rows.[cite:88][cite:57] |
| `raw_mlbapi` | MLB StatsAPI requests, payloads, and expanded endpoint-family tables such as schedule and live feed.[cite:85][cite:138] |
| `raw_fangraphs` | Raw FanGraphs request/payload captures for leaderboards and splits.[cite:89][cite:149] |
| `raw_bref` | Raw Baseball Reference page captures. |
| `raw_espn` | Raw ESPN page/API captures. |
| `raw_odds` | Raw odds-provider request/payload storage for books and prediction markets. |
| `stg` | Cross-source identity bridges and conformance mappings. |
| `core` | Canonical warehouse entities and baseball event grains. |
| `mart` | Reserved for analytical marts and materialized views to be added later. |
| `util` | Utility functions and shared helpers. |
| `ml` | Model registry, feature store, training, backtests, predictions, and simulations. |
| `ops` | Live polling and scheduled job metadata. |

## Implemented SQL batches so far

### Batch 1: extensions, schemas, and metadata

**Files created:**
- `sql/010_extensions/001_extensions.sql`
- `sql/020_schemas/001_schemas.sql`
- `sql/030_meta/001_source_registry.sql`
- `sql/030_meta/002_ingest_audit.sql`
- `sql/080_functions/001_meta_functions.sql`

**Main purpose:** establish extension support, schema boundaries, source registries, ingest auditability, file tracking, payload deduplication, and base helper functions.

**Important tables:**
- `meta.source_system`
- `meta.source_endpoint`
- `meta.ingest_run`
- `meta.source_file`
- `meta.raw_payload_registry`
- `meta.ingest_error`

**Important functions:**
- `util.touch_updated_at()`
- `util.sha256_text()`
- `util.register_payload_hash()`
- `util.start_ingest_run()`
- `util.finish_ingest_run()`

These objects create the control plane for all subsequent ingestion. They are especially important because MLB StatsAPI exposes multiple endpoint families and Retrosheet/Chadwick workflows are file-oriented rather than purely API-oriented.[cite:85][cite:70][cite:75]

### Batch 2: Retrosheet and Chadwick raw layer

**Files created:**
- `sql/040_raw/001_raw_retrosheet.sql`
- `sql/040_raw/002_raw_chadwick.sql`
- `sql/090_constraints_indexes/002_retrosheet_chadwick_indexes.sql`
- `sql/080_functions/002_retrosheet_chadwick_functions.sql`

**Main purpose:** preserve source-faithful Retrosheet event records while also storing Chadwick’s structured extractions.

**Important tables:**
- `raw_retrosheet.event_file`
- `raw_retrosheet.game`
- `raw_retrosheet.record`
- `raw_retrosheet.info`
- `raw_retrosheet.start`
- `raw_retrosheet.sub`
- `raw_retrosheet.play`
- `raw_retrosheet.comment`
- `raw_retrosheet.data`
- `raw_retrosheet.adjustment`
- `raw_chadwick.cwevent_file`
- `raw_chadwick.cwevent`
- `raw_chadwick.cwgame_file`
- `raw_chadwick.cwgame`
- `raw_chadwick.cwsub_file`
- `raw_chadwick.cwsub`

**Important functions:**
- `util.is_valid_retrosheet_record_type()`
- `util.normalize_retrosheet_record_type()`
- `util.register_retrosheet_record_hash()`
- `util.validate_retrosheet_record_sequences()`

Retrosheet documents record families such as `id`, `info`, `start`, `play`, `sub`, `com`, and `data`, while Chadwick provides structured extraction tools like `cwevent`, `cwgame`, and `cwsub`, which justifies maintaining both raw and extracted layers.[cite:70][cite:71][cite:75][cite:81][cite:135]

### Batch 3: Statcast and MLB StatsAPI raw layer

**Files created:**
- `sql/040_raw/003_raw_statcast.sql`
- `sql/040_raw/004_raw_mlbapi.sql`
- `sql/090_constraints_indexes/003_statcast_mlbapi_indexes.sql`
- `sql/080_functions/003_statcast_mlbapi_functions.sql`

**Main purpose:** capture Statcast pitch-level data and MLB StatsAPI request/payload structures.

**Important tables:**
- `raw_statcast.search_file`
- `raw_statcast.pitch`
- `raw_statcast.lookup_observation`
- `raw_mlbapi.request`
- `raw_mlbapi.payload`
- `raw_mlbapi.schedule_date`
- `raw_mlbapi.schedule_game`
- `raw_mlbapi.live_play`
- `raw_mlbapi.live_pitch`
- `raw_mlbapi.person`
- `raw_mlbapi.team`
- `raw_mlbapi.meta_value`

**Important functions:**
- `util.register_statcast_row_hash()`
- `util.register_mlbapi_payload_hash()`
- `util.validate_statcast_pitch_business_key()`
- `util.validate_mlbapi_request_method()`

Baseball Savant’s CSV docs define Statcast columns directly, while MLB StatsAPI documentation centers around endpoint families such as schedule, game live feed, people, teams, stats, and meta, so the raw layer mirrors those source contracts closely.[cite:88][cite:85][cite:138][cite:140]

### Batch 4: Lahman and web/payload raw layer

**Files created:**
- `sql/040_raw/005_raw_lahman.sql`
- `sql/040_raw/006_raw_web_sources.sql`
- `sql/090_constraints_indexes/004_lahman_web_indexes.sql`
- `sql/080_functions/004_lahman_web_functions.sql`

**Main purpose:** store Lahman in familiar relational form and keep less-structured sources raw-first.

**Important tables:**
- `raw_lahman.people`
- `raw_lahman.batting`
- `raw_lahman.pitching`
- `raw_lahman.fielding`
- `raw_lahman.teams`
- `raw_fangraphs.request`
- `raw_fangraphs.payload`
- `raw_bref.request`
- `raw_bref.page`
- `raw_espn.request`
- `raw_espn.page`
- `raw_odds.provider_request`
- `raw_odds.provider_payload`

**Important functions:**
- `util.register_generic_payload_hash()`
- `util.normalize_lahman_player_id()`
- `util.normalize_web_natural_key()`
- `util.validate_lahman_year_id()`

Lahman is already relational and explicitly documents tables like `People` and `Teams`, while FanGraphs, Baseball Reference, ESPN, and odds providers are more safely handled as request/payload captures before later conformance.[cite:76][cite:145][cite:143][cite:89][cite:149][cite:148]

### Batch 5: staging identity and source conformance

**Files created:**
- `sql/050_staging/001_identity_bridge.sql`
- `sql/050_staging/004_game_identity_bridge.sql`
- `sql/050_staging/005_source_conformance.sql`
- `sql/090_constraints_indexes/005_staging_indexes.sql`
- `sql/080_functions/005_staging_functions.sql`

**Main purpose:** resolve identifiers across MLBAM, Retrosheet, Lahman, Baseball Reference, FanGraphs, and venue/team/game sources.

**Important tables:**
- `stg.player_identity`
- `stg.team_identity`
- `stg.venue_identity`
- `stg.player_identity_candidate`
- `stg.game_identity`
- `stg.game_source_link`
- `stg.game_identity_candidate`
- `stg.game_identity_bridge` (canonical game ID mapping)
- `stg.player_source_conformance`
- `stg.team_source_conformance`
- `stg.venue_source_conformance`

**Important functions:**
- `util.stg_touch_updated_at()`
- `util.normalize_team_code()`
- `util.normalize_player_code()`
- `util.build_retrosheet_game_id()`
- `util.identity_match_score()`

This layer is essential because Lahman includes bridge fields like `retroID` and `bbrefID`, while Retrosheet and MLB StatsAPI have different native identifiers and game representations.[cite:173][cite:174][cite:175][cite:119][cite:168]

### Batch 6: canonical core baseball layer

**Files created:**
- `sql/060_core/001_core_entities.sql`
- `sql/060_core/002_core_gameplay.sql`
- `sql/060_core/003_core_relationships.sql`
- `sql/060_core/005_serving_views.sql`
- `sql/090_constraints_indexes/006_core_indexes.sql`
- `sql/080_functions/006_core_functions.sql`

**Main purpose:** define canonical players, teams, venues, games, rosters, plate appearances, pitches, and source lineage maps.

**Important tables:**
- `core.player`
- `core.team`
- `core.venue`
- `core.games` (canonical game entity with UUID PK)
- `core.roster_assignment`
- `core.plate_appearances` (decoupled PA event grain)
- `core.pitches` (granular pitch telemetry)
- `core.player_team_season`
- `core.game_official`
- `core.game_source_map`
- `core.plate_appearance_source_map`
- `core.pitch_source_map`

**Important views:**
- `core.v_unified_plate_appearances` (includes `has_pitch_telemetry` flag)

**Important functions:**
- `util.core_touch_updated_at()`
- `util.normalize_inning_half()`
- `util.build_pa_key()`
- `util.build_pitch_key()`

This canonical layer matches the natural grain of baseball data, with plate appearances and pitches serving as the foundation for feature engineering, modeling, and later analytical marts.[cite:70][cite:80][cite:88]

### Batch 7: machine learning and operations layer

**Files created:**
- `sql/070_ml_ops/001_ml_registry.sql`
- `sql/070_ml_ops/002_feature_store.sql`
- `sql/070_ml_ops/003_predictions_backtests_liveops.sql`
- `sql/090_constraints_indexes/007_ml_ops_indexes.sql`
- `sql/080_functions/007_ml_ops_functions.sql`

**Main purpose:** support model registries, feature snapshots, dataset definitions, training runs, backtests, prediction runs, prediction evaluations, simulations, live pollers, and scheduled jobs.

**Important tables:**
- `ml.problem_definition`
- `ml.feature_set`
- `ml.feature_definition`
- `ml.model_family`
- `ml.model_definition`
- `ml.feature_snapshot`
- `ml.dataset_definition`
- `ml.dataset_split`
- `ml.training_run`
- `ml.backtest_run`
- `ml.prediction_run`
- `ml.prediction_output`
- `ml.prediction_evaluation`
- `ml.simulation_run`
- `ops.live_game_poller`
- `ops.scheduled_job`
- `ops.job_run`

**Important functions:**
- `util.ml_ops_touch_updated_at()`
- `util.should_stop_live_polling()`
- `util.build_feature_entity_key()`
- `util.safe_prediction_rank_score()`

This layer intentionally supports multiple modeling families, including logistic regression, random forest, gradient boosting, neural networks, Bayesian models, Markov/state-space methods, ensembles, and Monte Carlo-style simulation.[cite:183][cite:185][cite:186][cite:187][cite:190]

## Current table categories

The current design can be understood as six table categories:

1. **Control plane tables**: source systems, endpoints, ingest runs, jobs, model registry.
2. **Raw ingestion tables**: source-faithful event, API, CSV, and page payloads.
3. **Bridge tables**: player/team/venue/game identity and source conformance.
4. **Canonical baseball tables**: player, team, venue, game, roster, PA, pitch.
5. **Modeling tables**: feature sets, snapshots, datasets, training runs, predictions, backtests, simulations.
6. **Operational tables**: live pollers, job runs, scheduled jobs, and later audit/security tables.

This separation improves maintainability and helps preserve both lineage and performance tuning boundaries.[cite:220][cite:212]

## Function families

The project currently uses several distinct function families.

### 1. Audit and timestamp helpers

- `util.touch_updated_at()`
- `util.stg_touch_updated_at()`
- `util.core_touch_updated_at()`
- `util.ml_ops_touch_updated_at()`

These are generic trigger helpers for `updated_at` maintenance.

### 2. Hashing and deduplication

- `util.sha256_text()`
- `util.register_payload_hash()`
- `util.register_retrosheet_record_hash()`
- `util.register_statcast_row_hash()`
- `util.register_mlbapi_payload_hash()`
- `util.register_generic_payload_hash()`

These functions support payload deduplication, change detection, and source lineage by hashing raw content.[cite:202][cite:203]

### 3. Ingest lifecycle helpers

- `util.start_ingest_run()`
- `util.finish_ingest_run()`

These functions standardize ingestion bookkeeping so loaders and workers do not need to reimplement operational tracking logic.

### 4. Validation and normalization helpers

- `util.is_valid_retrosheet_record_type()`
- `util.normalize_retrosheet_record_type()`
- `util.validate_retrosheet_record_sequences()`
- `util.validate_statcast_pitch_business_key()`
- `util.validate_mlbapi_request_method()`
- `util.normalize_lahman_player_id()`
- `util.validate_lahman_year_id()`
- `util.normalize_team_code()`
- `util.normalize_player_code()`
- `util.normalize_inning_half()`

These functions help normalize source-specific identifiers and protect basic data quality constraints.

### 5. Key construction helpers

- `util.normalize_web_natural_key()`
- `util.build_retrosheet_game_id()`
- `util.build_pa_key()`
- `util.build_pitch_key()`
- `util.build_feature_entity_key()`

These functions create stable natural or composite keys used in lineage, identity resolution, and feature snapshots.

### 6. Modeling and live-ops helpers

- `util.identity_match_score()`
- `util.should_stop_live_polling()`
- `util.safe_prediction_rank_score()`

These functions support record matching, live poll termination checks, and simple result ranking for predictions.[cite:85][cite:138][cite:188]

## Multi-user and deployment posture

The design can absolutely be extended to multi-user use while still supporting single-user deployments. PostgreSQL already supports multiple concurrent users and connections, and later layers can introduce separate app roles, analyst roles, agent roles, worker/service accounts, and optional tenant isolation with Row Level Security if the project evolves into a centralized hosted platform.[cite:201][cite:204][cite:210][cite:215]

The current SQL batches are therefore compatible with both paths:
- **single-user or homelab mode**, where one person owns the entire stack,
- **shared team mode**, where multiple trusted users share the same system,
- **future hosted mode**, where an API layer and stronger isolation controls become mandatory.

## Performance and future optimizations

Several optimizations have been discussed but not yet fully implemented.

### Extensions to consider next

- **pgAudit** for statement/object audit logging.[cite:202][cite:203][cite:206]
- **pg_cron** for DB-native scheduling support.[cite:199]
- **pgvector** for agent-facing semantic search over experiments, notes, and model explanations.[cite:209]
- **TimescaleDB** as an optional enhancement if native Postgres partitioning proves insufficient for time-heavy workloads.[cite:189][cite:191][cite:194][cite:195]

### Performance techniques to add later

- table partitioning on time-heavy fact tables,
- materialized views for rolling feature windows,
- precomputed analytical marts,
- dedicated read APIs and cached endpoints,
- background workers for live polling and feature refresh,
- explicit query budgets and API rate limits.[cite:189][cite:214][cite:211]

## Security and API considerations

A secure API layer is recommended if this project is redistributed, shared, or turned into a hosted product. PostgREST can expose DB-centric APIs quickly, but FastAPI is likely the better long-term service layer for custom auth, model orchestration, bet logic, alerting, and agent workflows.[cite:211][cite:212][cite:222]

A professional deployment would eventually include:
- reverse proxy or API gateway,
- application/service identities,
- RBAC and restricted database roles,
- optional RLS for tenant/user isolation,
- audit logging,
- rate limiting and abuse protection.[cite:211][cite:215][cite:218][cite:220]

## Documentation set to produce later

The current document is a project overview. After the SQL design stabilizes, the documentation set should expand into separate files:

| Document | Purpose |
|---|---|
| `docs/architecture.md` | Overall architecture, data flow, and system boundaries. |
| `docs/data-dictionary.md` | Table-by-table and column-by-column reference. |
| `docs/ingestion.md` | Source-specific ingestion and scheduling workflows. |
| `docs/modeling.md` | Feature store, training, validation, backtesting, and simulation workflows. |
| `docs/security.md` | Roles, permissions, audit logging, API security, and tenant strategy. |
| `docs/api.md` | API design, endpoints, auth, and rate limits. |
| `docs/deployment.md` | Local, homelab, centralized, and hosted deployment options. |
| `docs/operations.md` | Pollers, scheduled jobs, monitoring, backups, and incident workflows. |

## Recommendation

Documentation should start now and continue alongside development rather than waiting until every SQL file is finished. A lightweight project overview like this helps preserve intent, while a more formal data dictionary and deployment/security guides should be written after the next batches settle performance, audit, API, and multi-user design choices.[cite:212][cite:220]

The next practical move is to continue the SQL work, but keep updating this document whenever a new batch is added. Once the remaining SQL and architectural decisions are complete, a second documentation pass should produce polished docs for implementation, deployment, and eventual redistribution.
