# AGENTS.md — MLB Database Project

> **Every AI agent working on this repo must read this file before making any changes.**
> Last updated: 2026-05-25 (Schema Refactor cleanup completed)

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
| `sql/040_raw/006_raw_web_sources.sql` | `raw_fangraphs`, `raw_bref`, `raw_espn`, `raw_odds` | 🟡 FG/BRef payload tables present; typed stat tables pending (DEC-007) |

---

## Staging Layer File Map

| File | Purpose | Status |
|------|---------|--------|
| `sql/050_staging/001_identity_bridge.sql` | `stg.player_identity`, `stg.team_identity`, `stg.venue_identity`, `stg.player_identity_candidate` | ✅ Complete |
| `sql/050_staging/002_identity_trigger_and_indexes.sql` | `updated_at` triggers, missing indexes, auto-resolution trigger, resolution audit log | ✅ Complete |
| `sql/050_staging/003_game_identity.sql` | `stg.game_identity` initial table | ✅ Complete |
| `sql/050_staging/005_game_identity_bridge.sql` | `stg.game_identity` enhancements (canonical game ID mapping, triggers, views) | ✅ Complete |
| `sql/050_staging/006_source_conformance.sql` | `stg.player/team/venue_source_conformance` | ✅ Complete |

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
    - Verified bootstrap and test suite pass (197/197 tests)

### Outstanding 🔲
- [ ] **Next:** Add fully typed stat tables to `raw_fangraphs` and `raw_bref` (DEC-007) — replace JSONB-only payload tables
- [ ] **Next:** Add typed extraction staging tables for `raw_mlbapi` JSONB blobs (DEC-010)
- [ ] **Next:** Alembic integration — manual DDL in `sql/` + Alembic version tracking only (DEC-009); see ROADMAP.md Milestone 2
- [ ] **Next:** Parquet/S3 export CLI (`baseball export-features`) for R/Python ML training workflows (DEC-011)
- [ ] **Next:** Add `mv_batter_spray_heatmap` and `mv_pitcher_zone_profile` MVs once FG/BRef typed tables are available for blended metrics

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

---

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
