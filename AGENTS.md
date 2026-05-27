# AGENTS.md — MLB Database Project

> **Every AI agent working on this repo must read this file before making any changes.**
> Last updated: 2026-05-26 (player identity resolution, Issue #36 completed)

---

## Project Purpose

A comprehensive PostgreSQL baseball analytics database that ingests, stores, and conforms data from every major baseball data source. The goal is a fully normalized, ML-ready data warehouse covering pitch-level, game-level, season-level, and biographical data from 1871 to present.

---

## Core Objectives

1. **Capture everything.** Every field offered by every source goes into the raw tables. Nothing is filtered or pruned at ingestion. If a source offers it, we store it.
2. **Group by source.** Each data source has its own schema (e.g. `raw_statcast`, `raw_lahman`, `raw_fangraphs`, `raw_bref`, `raw_retrosheet`, `raw_chadwick`, `raw_mlbapi`, `raw_espn`, `raw_odds`). Do not mix sources into shared tables.
3. **Raw layer is sacred.** Raw tables are append-only representations of source data. Never transform or clean in raw — that is staging's job.
4. **NULLs are fine for historical gaps.** PostgreSQL uses a null bitmap — sparse NULLs do not waste storage. Do not use sentinel values like -999 or 'N/A'.
5. **No orphaned files.** Modify original SQL files in-place where possible. For new columns on existing tables, use `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` in a dedicated `*_alter.sql` file. Keep the codebase clean.
6. **Idempotent DDL.** All CREATE statements use `CREATE TABLE IF NOT EXISTS`. All ALTER statements use `IF NOT EXISTS` for new columns.
7. **Always stay in a transaction.** Every SQL file must start with `BEGIN;` and end with `COMMIT;`.

> **See also:** [OBJECTIVES.md](./OBJECTIVES.md) for the full rationale behind each principle, the layer contracts, naming conventions, decision log (DEC-001–011), and a list of things agents must NOT do.

---

## Pipeline Layer Reference

| Step | Directory | Purpose |
|------|-----------|----------|
| 010 | `sql/010_extensions` | PostgreSQL extensions (uuid-ossp, pg_trgm, etc.) |
| 020 | `sql/020_schemas` | Schema creation (`CREATE SCHEMA IF NOT EXISTS`) |
| 030 | `sql/030_meta` | Metadata tables: `meta.source_file`, `meta.ingest_run`, `meta.source_endpoint` |
| 040 | `sql/040_raw` | **Raw ingestion tables — one file per source** |
| 050 | `sql/050_staging` | Identity bridging, dedup, light normalization |
| 060 | `sql/060_core` | Conformed facts and dimensions |
| 070 | `sql/070_ml_ops` | ML feature marts, materialized views |
| 080 | `sql/080_functions` | PL/pgSQL functions and triggers |
| 090 | `sql/090_constraints_indexes` | Indexes and FK constraints applied after data load |

---

## Active Data Sources

| Schema | Source | Format | Access Method |
|--------|--------|--------|---------------|
| `raw_statcast` | Baseball Savant / Statcast | CSV / API | pybaseball `statcast()` |
| `raw_lahman` | Lahman Database | CSV | Direct download / pybaseball |
| `raw_retrosheet` | Retrosheet | Event files (.EVA/.EVN) | Direct download |
| `raw_chadwick` | Chadwick Bureau | CSV (cwevent/cwgame/cwsub output) | cwevent CLI tool |
| `raw_mlbapi` | MLB Stats API | JSON | Direct HTTP / pybaseball |
| `raw_fangraphs` | FanGraphs | HTML/JSON | pybaseball `batting_stats()` etc. |
| `raw_bref` | Baseball Reference | HTML tables | pybaseball / direct scrape |
| `raw_espn` | ESPN | HTML/JSON | Direct HTTP |
| `raw_odds` | Odds providers | JSON | Direct HTTP (The Odds API, etc.) |

---

## Raw Layer File Map

| File | Schema(s) | Status |
|------|-----------|--------|
| `sql/040_raw/001_raw_retrosheet.sql` | `raw_retrosheet` | ✅ Complete |
| `sql/040_raw/002_raw_chadwick.sql` | `raw_chadwick` | ✅ Complete (96-field cwevent + cwgame + cwsub) — 2026-05-19 |
| `sql/040_raw/003_raw_statcast.sql` | `raw_statcast` | ✅ Complete (110 cols) — 2026-05-19 |
| `sql/040_raw/004_raw_mlbapi.sql` | `raw_mlbapi` | 🟡 Audited — JSONB ingest tables present; typed staging tables pending |
| `sql/040_raw/005_raw_lahman.sql` | `raw_lahman` | ✅ Complete (all 21 tables) — 2026-05-19 |
| `sql/040_raw/006_raw_web_sources.sql` | `raw_fangraphs`, `raw_bref`, `raw_espn`, `raw_odds` | ✅ Complete |
| `sql/040_raw/006_raw_web_sources_migration_v2.sql` | Additional typed tables for all web sources | ✅ Added 2026-05-25 (batter/pitcher splits, baserunning, plate_discipline, schedule, scores, market_lines) |

---

## Staging Layer File Map

| File | Purpose | Status |
|------|---------|--------|
| `sql/050_staging/001_identity_bridge.sql` | `stg.player_identity`, `stg.team_identity`, `stg.venue_identity`, `stg.player_identity_candidate` | ✅ Complete |
| `sql/050_staging/002_identity_trigger_and_indexes.sql` | `updated_at` triggers, missing indexes, auto-resolution trigger, resolution audit log | ✅ Complete |
| `sql/050_staging/003_game_identity.sql` | `stg.game_identity` initial table | ✅ Complete |
| `sql/050_staging/005_game_identity_bridge.sql` | `stg.game_identity` enhancements (canonical game ID mapping, triggers, views) | ✅ Complete |
| `sql/050_staging/006_source_conformance.sql` | `stg.player/team/venue_source_conformance` | ✅ Complete |
| `sql/050_staging/007_mlbapi_extraction.sql` | `stg.mlbapi_game`, `stg.mlbapi_person`, `stg.mlbapi_team` (typed extraction from JSONB) | ✅ Complete |

---

## Functions Layer File Map

| File | Purpose | Status |
|------|---------|--------|
| `sql/080_functions/001_meta_functions.sql` | Metadata utility functions | ✅ Complete |
| `sql/080_functions/002_retrosheet_chadwick_functions.sql` | Retrosheet/Chadwick ingestion functions | ✅ Complete |
| `sql/080_functions/003a_ingestion_identity_resolution.sql` | `util.resolve_player_id()`, `util.resolve_team_id()` for MLBAM ID bridge | ✅ Added 2026-05-26 |
| `sql/080_functions/003_statcast_mlbapi_functions.sql` | Statcast/MLB API ingestion functions | ✅ Complete |
| `sql/080_functions/004_lahman_web_functions.sql` | Lahman web ingestion functions | ✅ Complete |
| `sql/080_functions/005_staging_functions.sql` | `ingest_chadwick_play()`, `ingest_play_event()` with identity resolution | ✅ Updated 2026-05-26 |
| `sql/080_functions/006_core_functions.sql` | Core entity utility functions | ✅ Complete |
| `sql/080_functions/007_ml_ops_functions.sql` | ML operations functions | ✅ Complete |
| `sql/080_functions/008_auth_security_functions.sql` | Authentication and security functions | ✅ Complete |
| `sql/080_functions/009_mart_refresh_functions.sql` | Materialized view refresh functions | ✅ Complete |
| `sql/080_functions/010_ingestion_ops_functions.sql` | Ingestion orchestration functions | ✅ Complete |
| `sql/080_functions/011_api_service_functions.sql` | API service contract functions | ✅ Complete |
| `sql/080_functions/012_source_ingestion_functions.sql` | Source-specific ingestion functions | ✅ Complete |
| `sql/080_functions/013_identity_validation_functions.sql` | Identity validation functions | ✅ Complete |
| `sql/080_functions/014_identity_reconciliation_functions.sql` | Identity reconciliation functions | ✅ Complete |

---

## Core Layer File Map

| File | Purpose | Status |
|------|---------|--------|
| `sql/060_core/001_core_entities.sql` | `core.player`, `core.team`, `core.venue` | ✅ Complete |
| `sql/060_core/002_core_gameplay.sql` | `core.games`, `core.plate_appearances`, `core.pitches` (decoupled gameplay tables) | ✅ Complete |
| `sql/060_core/003_core_relationships.sql` | `core.player_team_season`, `core.game_official`, source map tables | ✅ Complete |
| `sql/060_core/005_serving_views.sql` | Serving views (including `core.v_unified_plate_appearances`) | ✅ Complete |

---

## ML Ops Layer File Map

| File | Purpose | Status |
|------|---------|--------|
| `sql/070_ml_ops/001_ml_registry.sql` | ML model registry tables (`ml.model_family`, `ml.problem_definition`, `ml.model_definition`) | ✅ Complete |
| `sql/070_ml_ops/002_feature_store.sql` | Feature store tables | ✅ Complete |
| `sql/070_ml_ops/003_predictions_backtests_liveops.sql` | Prediction outputs, backtest runs, live ops tables | ✅ Complete |
| `sql/070_ml_ops/004_workspace_security.sql` | Workspace roles and security | ✅ Complete |
| `sql/070_ml_ops/005_workspace_rls.sql` | Row-level security policies | ✅ Complete |
| `sql/070_ml_ops/006_marts_materialized_views.sql` | ML model management MVs (`mv_workspace_model_summary` etc.) | ✅ Complete |
| `sql/070_ml_ops/007_ingestion_orchestration.sql` | Ingestion scheduling and orchestration tables | ✅ Complete |
| `sql/070_ml_ops/008_api_service_contracts.sql` | API service contract tables | ✅ Complete |
| `sql/070_ml_ops/009_source_ingestion_specs.sql` | Source ingestion spec tables | ✅ Complete |
| `sql/070_ml_ops/010_mv_statcast_player_summary.sql` | **Baseball analytics MVs**: `mv_player_statcast_summary`, `mv_pitch_arsenal_by_season`, `mv_game_score_context` | ✅ Added 2026-05-19 |
| `sql/070_ml_ops/011_mart_views.sql` | Mart views (`mart.v_workspace_model_catalog`) | ✅ Added 2026-05-24 |

---

## Known Outstanding Work (see also [Issue #9](https://github.com/cbwinslow/mlb/issues/9))

### Completed ✅
- [x] **Step 1:** `raw_statcast.pitch` expanded to full 110-column spec (`003_raw_statcast.sql`)
- [x] **Step 2:** All 21 Lahman tables added to `005_raw_lahman.sql`
- [x] **Step 3:** FanGraphs/BRef payload tables added to `006_raw_web_sources.sql` (typed tables pending — DEC-007)
- [x] **Step 4:** `raw_chadwick.cwevent` expanded to full 96-field spec; `cwgame` and `cwsub` complete (`002_raw_chadwick.sql`)
- [x] **Step 5:** `raw_mlbapi` audit complete; JSONB ingest tables present
- [x] **Step 6:** `stg.player_identity` — missing unique indexes added; `updated_at` triggers added; auto-resolution trigger + audit log added
- [x] **Step 7:** `core.pitch` expanded to mirror full `raw_statcast.pitch` (74 columns added); triggers and indexes fixed
- [x] **Step 8:** `OBJECTIVES.md` written; `AGENTS.md` updated
- [x] **Step 9:** All 5 open questions resolved as DEC-007–011; `010_mv_statcast_player_summary.sql` added with 3 baseball analytics MVs
- [x] **Step 10:** Schema refactor completed per refactor-blueprint.md:
    - Deleted redundant files: `003_raw_statcast_migration_v2.sql`, `002_game_bridge.sql`, `004_core_pitch_alter.sql`
    - Added game identity bridge: `005_game_identity_bridge.sql`
    - Refactored core gameplay: `002_core_gameplay.sql` now contains `core.games`, `core.plate_appearances`, `core.pitches`
    - Updated serving views: `005_serving_views.sql` includes `core.v_unified_plate_appearances`
    - Updated ML ops: Added `011_mart_views.sql` for `mart.v_workspace_model_catalog`
    - Fixed foreign key type mismatches in ML ops tables
    - Verified bootstrap and test suite pass (266 tests)

### Completed ✅
- [x] **Step 11:** Add typed tables to `raw_fangraphs` and `raw_bref`
    - File: `sql/040_raw/006_raw_web_sources_migration_v2.sql`
    - Tables: batter_splits, pitcher_splits, baserunning, plate_discipline
    - Source: DEC-007
- [x] **Step 12:** Complete `raw_espn` and `raw_odds` typed tables
    - File: `sql/040_raw/006_raw_web_sources_migration_v2.sql`
    - Tables: raw_espn.schedule, raw_espn.scores, raw_odds.market_lines
- [x] **Step 13:** Audit `stg.player_identity` for all 5 cross-source keys
    - Added unique partial indexes for bbref_player_id and fangraphs_player_id
    - File: `sql/090_constraints_indexes/005_staging_indexes.sql`
- [x] **Issue #17:** Create ingestion Python components
    - Files: `baseball/ingestion/orchestrator.py`, `baseball/ingestion/loaders.py`, `baseball/ingestion/engine.py`
    - Added ingest commands to CLI: `baseball ingest lahman`, `baseball ingest retrosheet`, etc.
- [x] **Configuration fixes:** Fix `pyproject.toml` dev dependencies, `.gitignore` cleanup, Python linting issues
    - Moved dev dependencies to `[project.optional-dependencies] dev` in `pyproject.toml`
    - Removed redundant `.refact/buddy/` entries from `.gitignore`
    - Fixed Python linting issues in `engine.py`, `loaders.py`, `orchestrator.py`, `enrich_player_identity.py`, `cli.py`, `settings.py`
    - All 197 tests passing
- [x] **Alembic infrastructure:** Add Alembic for schema version tracking (DEC-009)
    - Created `alembic/` directory with env.py, ini, script template
    - Added initial migration `001_initial_schema.py`
    - Added `baseball migrate` CLI commands
    - Added alembic to dev dependencies
    - Generated migrations for sql/010-090 directories
- [x] **Bootstrap command:** Implement `baseball db-init` with SQL file execution
    - Added `baseball/db.py` with `run_bootstrap()` function
    - Updated `db-init` command to apply SQL files via psql
    - Added `--dry-run` and `--recreate` options

    - Created `alembic/` directory with env.py, ini, script template
    - Added initial migration `001_initial_schema.py`
    - Added `baseball migrate` CLI commands
    - Added alembic to dev dependencies
- [x] **Fix .env injection:** Fixed pydantic-settings nested model .env loading
    - Added `env_file` config to `DatabaseSettings`, `WorkspaceSettings`, `OpsSettings` classes
    - Added `python.envFile` setting to `.vscode/settings.json` for VS Code integration
    - Updated `init_nested_settings` validator to rely on nested classes' own env_file config

### Outstanding 🔲
- [ ] **Next:** Parquet/S3 export CLI (`baseball export-features`) for R/Python ML training workflows (DEC-012)
- [ ] **Next:** Add `mv_batter_spray_heatmap` and `mv_pitcher_zone_profile` MVs once FG/BRef typed tables are available for blended metrics

### Completed ✅
- [x] **Issue #36:** Fix type mismatches in ingestion functions (INTEGER vs UUID)
    - Added `util.resolve_player_id()` and `util.resolve_team_id()` functions
    - Updated `util.ingest_chadwick_play()` and `util.ingest_play_event()` to resolve MLBAM IDs
    - Fixed async/await patterns in orchestrator.py
    - All 266 tests pass

### Documentation Audit ✅ Completed
- [x] Updated `AGENTS.md` file maps (removed `002_game_bridge.sql`, `004_core_pitch_alter.sql` references)
- [x] Updated `ROADMAP.md` with Milestone 1.5 (Schema Refactor)
- [x] Updated `OBJECTIVES.md` with correct table names (`core.pitches`)
- [x] Updated `sql/README.md` file tree
- [x] Updated `docs/project-summary.md` table names
- [x] Updated `docs/testing-strategy.md` test table names
- [x] Updated `docs/player_identity_design.md` diagram
- [x] Updated `docs/github-workflow.md` issue title example
- [x] Created `docs/audit_checklist.md` with audit verification
- [x] Updated `AGENTS.md` with new typed tables and Python components
- [x] Updated `README.md` project status section with completed work

---

## Rules
    1. do not ever use a postgresql docker container for production operations. we can create one to publish with the release of the software but as far as operations we never ever use the container for production operations.
    

## Conventions for AI Agents

### Before Any Work
1. Read this file.
2. Read [OBJECTIVES.md](./OBJECTIVES.md) — especially Sections 6 (Decision Log) and 7 (What Agents Must NOT Do).
3. Read [Issue #9](https://github.com/cbwinslow/mlb/issues/9) for current task status.
4. Fetch the actual current content of any file you plan to modify from the GitHub API — **never assume or guess** at current file state.
5. Check the SHA of the file before pushing an update (required by GitHub API for in-place updates).

### While Working
- For new columns on existing tables, use `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` in a dedicated `*_alter.sql` migration file.
- For new tables, use `CREATE TABLE IF NOT EXISTS`.
- Keep all DDL inside `BEGIN; ... COMMIT;`.
- Add a `COMMENT ON TABLE` for every new table.
- Add a `COMMENT ON COLUMN` for any column whose purpose is not obvious.
- When adding an `updated_at` column, **always attach the `stg.set_updated_at()` trigger** (or create an equivalent).
- Do not add `NOT NULL` constraints to new columns on populated tables.
- Do not auto-generate Alembic migrations from SQLAlchemy models (see DEC-009).

### After Work
- Post a timestamped update to [Issue #9](https://github.com/cbwinslow/mlb/issues/9) describing what was completed.
- Update the checkbox list in the Outstanding Work section above.
- Update the **Status** column in the relevant File Map table above.
- Update the "Last updated" date at the top of this file.

### Commit Message Format
```
<Short summary of change>

Issue #9 - Step N COMPLETED

- Bullet list of specific changes made
```

---

## Identity Bridge Key

The `stg.player_identity` table links player IDs across all sources:

| Column | Source |
|--------|--------|
| `mlbam_player_id` | MLB Stats API / Statcast `batter`/`pitcher` column |
| `retrosheet_player_id` | Retrosheet `player_id` |
| `bbref_player_id` | Baseball Reference `bbref_id` |
| `fangraphs_player_id` | FanGraphs player ID |
| `lahman_player_id` | Lahman `player_id` |

When a new `mlbam_id` arrives with no existing identity record, the `trg_statcast_pitch_player_resolve` trigger inserts a partial record (`mlbam_player_id` + `full_name`, other keys NULL, `identity_confidence_score = 0`, `identity_source = 'auto:statcast'`) for later resolution via the enrichment job. **Raw inserts are never blocked.**

Use `stg.v_players_pending_enrichment` to find all players awaiting cross-source ID resolution.

---

## Contact / Ownership

Repo owner: [@cbwinslow](https://github.com/cbwinslow)
