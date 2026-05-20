# AGENTS.md — MLB Database Project

> **Every AI agent working on this repo must read this file before making any changes.**
> Last updated: 2026-05-19

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

> **See also:** [OBJECTIVES.md](./OBJECTIVES.md) for the full rationale behind each principle, the layer contracts, naming conventions, decision log, and a list of things agents must NOT do.

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
| `sql/040_raw/002_raw_chadwick.sql` | `raw_chadwick` | 🟡 Partial — cwevent only has ~35 of 96 fields |
| `sql/040_raw/003_raw_statcast.sql` | `raw_statcast` | ✅ Complete (110 cols) — 2026-05-19 |
| `sql/040_raw/004_raw_mlbapi.sql` | `raw_mlbapi` | 🔴 Needs audit |
| `sql/040_raw/005_raw_lahman.sql` | `raw_lahman` | 🟡 Partial — ~5 of 21 tables present |
| `sql/040_raw/006_raw_web_sources.sql` | `raw_fangraphs`, `raw_bref`, `raw_espn`, `raw_odds` | 🟡 Partial — payload blobs only, no typed stat tables |

---

## Staging Layer File Map

| File | Purpose | Status |
|------|---------|--------|
| `sql/050_staging/001_identity_bridge.sql` | `stg.player_identity`, `stg.team_identity`, `stg.venue_identity`, `stg.player_identity_candidate` | ✅ Complete |
| `sql/050_staging/002_game_bridge.sql` | `stg.game_identity`, `stg.game_source_link`, `stg.game_identity_candidate` | ✅ Complete |
| `sql/050_staging/003_source_conformance.sql` | `stg.player/team/venue_source_conformance` | ✅ Complete |
| `sql/050_staging/004_identity_trigger_and_indexes.sql` | `updated_at` triggers, missing indexes, auto-resolution trigger, resolution audit log | ✅ Added 2026-05-19 |

---

## Core Layer File Map

| File | Purpose | Status |
|------|---------|--------|
| `sql/060_core/001_core_entities.sql` | `core.player`, `core.team`, `core.venue`, `core.game` | ✅ Complete |
| `sql/060_core/002_core_gameplay.sql` | `core.roster_assignment`, `core.plate_appearance`, `core.pitch` | ✅ Complete |
| `sql/060_core/003_core_relationships.sql` | `core.player_team_season`, `core.game_official`, source map tables | ✅ Complete |
| `sql/060_core/004_core_pitch_alter.sql` | 74 missing columns added to `core.pitch`; `updated_at` triggers on entity tables; new indexes | ✅ Added 2026-05-19 |
| `sql/060_core/005_serving_views.sql` | Serving views | ✅ Complete |

---

## Known Outstanding Work (see also [Issue #9](https://github.com/cbwinslow/mlb/issues/9))

### Completed ✅
- [x] **Step 1:** `raw_statcast.pitch` expanded to full 110-column spec (`003_raw_statcast.sql`)
- [x] **Step 2:** 16 missing Lahman tables added to `005_raw_lahman.sql`
- [x] **Step 3:** Typed stat tables added to `raw_fangraphs` and `raw_bref` in `006_raw_web_sources.sql`
- [x] **Step 4:** `raw_chadwick.cwevent` expanded to full 96-field spec in `002_raw_chadwick.sql`
- [x] **Step 5:** `raw_mlbapi` audit completed
- [x] **Step 6:** `stg.player_identity` — missing unique indexes added; `updated_at` triggers added to all 4 identity tables; auto-resolution trigger + resolution audit log added (`004_identity_trigger_and_indexes.sql`)
- [x] **Step 7:** `core.pitch` expanded to mirror full `raw_statcast.pitch` (74 columns added); `updated_at` triggers fixed on all 4 core entity tables; missing `bbref`/`fangraphs` unique indexes added to `core.player` (`004_core_pitch_alter.sql`)
- [x] **Step 8:** `OBJECTIVES.md` written; `AGENTS.md` updated

### Outstanding 🔲
- [ ] **Next:** Audit `070_ml_ops` — verify `mv_player_statcast_summary` exists and covers new `core.pitch` columns (bat tracking, arm angle, expected outcomes)
- [ ] **Next:** Audit `raw_mlbapi` typed tables against current MLB Stats API endpoint documentation
- [ ] **Next:** Expand `raw_fangraphs` and `raw_bref` from payload blobs to typed stat tables
- [ ] **Next:** Complete `raw_chadwick.cwgame` and `raw_chadwick.cwsub` tables (only cwevent has been addressed)
- [ ] **Next:** Alembic integration for schema versioning (see ROADMAP.md Milestone 2)

---

## Conventions for AI Agents

### Before Any Work
1. Read this file.
2. Read [OBJECTIVES.md](./OBJECTIVES.md) — especially Section 7 (What Agents Must NOT Do).
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
