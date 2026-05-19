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
5. **No orphaned files.** Modify original SQL files in-place. Do not create separate migration files unless explicitly told to. Keep the codebase clean.
6. **Idempotent DDL.** All CREATE statements use `CREATE TABLE IF NOT EXISTS`. All ALTER statements use `IF NOT EXISTS` for new columns.
7. **Always stay in a transaction.** Every SQL file must start with `BEGIN;` and end with `COMMIT;`.

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
| `sql/040_raw/001_raw_retrosheet.sql` | `raw_retrosheet` | Complete |
| `sql/040_raw/002_raw_chadwick.sql` | `raw_chadwick` | Partial — cwevent only has ~35 of 96 fields |
| `sql/040_raw/003_raw_statcast.sql` | `raw_statcast` | Complete as of 2026-05-19 |
| `sql/040_raw/004_raw_mlbapi.sql` | `raw_mlbapi` | Needs audit |
| `sql/040_raw/005_raw_lahman.sql` | `raw_lahman` | Partial — 5 of ~21 tables present |
| `sql/040_raw/006_raw_web_sources.sql` | `raw_fangraphs`, `raw_bref`, `raw_espn`, `raw_odds` | Partial — only request/payload blobs, no typed stat tables |

---

## Known Outstanding Work (see also Issue #9)

- [ ] **Step 2:** Add 16 missing Lahman tables to `005_raw_lahman.sql`
- [ ] **Step 3:** Add typed stat tables to `raw_fangraphs` and `raw_bref` in `006_raw_web_sources.sql`
- [ ] **Step 4:** Complete `raw_chadwick.cwevent` to full 96-field cwevent spec in `002_raw_chadwick.sql`
- [ ] **Step 6:** Audit and complete `stg.player_identity` — ensure all four key IDs present, add trigger for partial-record insert on new mlbam_id

---

## Conventions for AI Agents

### Before Any Work
1. Read this file.
2. Read [Issue #9](https://github.com/cbwinslow/mlb/issues/9) for current task status.
3. Fetch the actual current content of any file you plan to modify from the GitHub API — **never assume or guess** at current file state.
4. Check the SHA of the file before pushing an update (required by GitHub API for in-place updates).

### While Working
- Modify original files in-place. Do not create new files unless adding a net-new source.
- For new columns on existing tables, use:
  ```sql
  ALTER TABLE schema.table ADD COLUMN IF NOT EXISTS col_name TYPE;
  ```
- For new tables, use `CREATE TABLE IF NOT EXISTS`.
- Keep all DDL inside `BEGIN; ... COMMIT;`.
- Add a `COMMENT ON TABLE` for every new table.
- Add a `COMMENT ON COLUMN` for any column whose purpose is not obvious.

### After Work
- Post a timestamped update to [Issue #9](https://github.com/cbwinslow/mlb/issues/9) describing what was completed.
- Update the checkbox list in Issue #9.
- Update the **Status** column in the Raw Layer File Map table above.
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
| `key_mlbam` | MLB Stats API / Statcast `batter`/`pitcher` column |
| `key_retro` | Retrosheet `player_id` |
| `key_bbref` | Baseball Reference `bbref_id` |
| `key_fangraphs` | FanGraphs player ID |
| `key_lahman` | Lahman `player_id` |

When a new `mlbam_id` arrives with no existing identity record, a trigger inserts a partial record (mlbam_id + name, other keys NULL, flagged `needs_resolution = true`) for later resolution. Do not block inserts.

---

## Contact / Ownership

Repo owner: [@cbwinslow](https://github.com/cbwinslow)
