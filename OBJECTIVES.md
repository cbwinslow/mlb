# MLB Analytics Platform — Objectives & Design Principles

> **Purpose:** This document defines the guiding objectives and design principles for the `cbwinslow/mlb` project. It is the canonical reference for *why* decisions are made — the companion to `AGENTS.md` (which defines *what* to do) and `ARCHITECTURE.md` (which defines *how* it is structured).
>
> Every contributor — human or AI — should read this before making any architectural decision.

Last updated: 2026-05-19

---

## 1. North Star

Build a **complete, lossless, multi-source baseball data warehouse** that:

- Captures every field offered by every public baseball data source
- Resolves player, team, game, and venue identities across all sources into a single coherent bridge
- Is queryable by AI agents via MCP with zero pre-processing required
- Supports ML feature engineering directly from the conformed `core` and `ml_ops` layers
- Covers **1871 to present** — historical completeness is not optional

---

## 2. Core Principles

### P1 — Capture Everything, Prune Nothing at Ingestion

Every field offered by every source goes into the raw tables. No filtering, no pruning, no "we probably won't need that" decisions at ingest time.

**Why:** The cost of storing an extra column in PostgreSQL is near-zero (NULL bitmap for sparse columns). The cost of discovering a missing column six months later — after millions of rows are already loaded — is a full re-ingest. Always err toward over-capture.

**Corollary:** Raw tables will have many NULL columns for older seasons. This is correct and expected. Do not add sentinel values (`-999`, `'N/A'`, `0` for missing) — use `NULL`.

### P2 — Group Raw Tables Strictly by Source

Each data source has exactly one schema in the raw layer:

| Schema | Source |
|--------|--------|
| `raw_statcast` | Baseball Savant / Statcast (pybaseball) |
| `raw_lahman` | Lahman Database CSV release |
| `raw_retrosheet` | Retrosheet event files |
| `raw_chadwick` | Chadwick Bureau cwevent/cwgame/cwsub output |
| `raw_mlbapi` | MLB Stats API JSON |
| `raw_fangraphs` | FanGraphs (pybaseball) |
| `raw_bref` | Baseball Reference |
| `raw_espn` | ESPN |
| `raw_odds` | Betting odds providers |

Do not create cross-source raw tables. Do not merge a FanGraphs column into a Statcast table because it "goes with" that data conceptually. Mixing sources in raw violates lineage traceability and makes re-ingestion from a single source impossible.

### P3 — Raw Layer is Append-Only and Sacred

Raw tables are the forensic record of what each source said at ingest time. They must never be modified post-load. Cleaning, normalization, deduplication, and type coercion belong in the staging layer (`050_staging`) or core layer (`060_core`).

**What this means in practice:**
- No `UPDATE` statements on raw tables after initial load
- No `DELETE` except for retraction of a full ingest run (via `ingest_run_id`)
- Raw tables carry `row_hash` and `raw_payload JSONB` where applicable so the exact source byte-stream is recoverable
- `created_at` on raw rows reflects ingest time, not game time

### P4 — Identity Resolution is Central, Not Optional

The hardest problem in baseball data is that every source uses different player, team, and game identifiers. The staging layer's identity bridge (`stg.player_identity`, `stg.team_identity`, `stg.game_identity`) is the backbone of the entire platform.

**Rules:**
- Every new MLBAM ID arriving in `raw_statcast.pitch` is immediately inserted as a pending placeholder in `stg.player_identity` (via the `trg_statcast_pitch_player_resolve` trigger)
- Pending placeholders have `identity_confidence_score = 0` and `identity_source = 'auto:statcast'`
- A downstream enrichment job (pybaseball `playerid_lookup()` or Chadwick register) resolves the remaining cross-source IDs and bumps `confidence_score` to `1.0`
- The `stg.player_identity_resolution_log` table audits every trigger firing
- Use `stg.v_players_pending_enrichment` to drive the enrichment job queue
- **Never block a raw insert waiting for identity resolution.** Raw capture must never fail due to bridge lag.

### P5 — Core Layer Mirrors Raw, Fully

The `core` layer (conformed facts and dimensions) must hold every column that exists in the corresponding raw table — not a curated subset. The purpose of `core` is to:

1. Resolve natural keys to surrogate FK keys (e.g. `batter` MLBAM ID → `batter_id` FK to `core.player`)
2. Apply consistent naming and type conventions
3. Provide a single join-free fact table for analysis

If a column exists in `raw_statcast.pitch` it must exist in `core.pitch`. There is no "we'll add that later" — later never comes and analysts get incorrect results from missing columns.

**Mechanism:** Any time a raw table gains a new column (e.g. `bat_speed` added in 2024), the corresponding core table gets an `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` in the same migration file or a dedicated `*_alter.sql` migration.

### P6 — Idempotent DDL Throughout

Every DDL statement must be safely re-runnable:
- `CREATE TABLE IF NOT EXISTS`
- `ALTER TABLE ... ADD COLUMN IF NOT EXISTS col TYPE`
- `CREATE INDEX IF NOT EXISTS`
- `CREATE OR REPLACE TRIGGER` / `CREATE OR REPLACE FUNCTION`
- `CREATE OR REPLACE VIEW`

This ensures the full `sql/` directory can be applied against an empty database from scratch, or applied again against an existing database with no errors and no data loss.

### P7 — Every SQL File is a Transaction

Every `.sql` file in the `sql/` directory must begin with `BEGIN;` and end with `COMMIT;`. No exceptions. This ensures any failure rolls back the entire file atomically and the database is never left in a partial state.

### P8 — NULLs Are Correct; Sentinels Are Wrong

PostgreSQL stores NULLs in a 1-bit null bitmap per row, not as per-column storage. A table with 100 columns that are NULL for 90% of rows does not waste meaningful space. Using `-999`, `0`, `'N/A'`, `'UNKNOWN'`, or any other sentinel to represent "not available" is wrong because:
- It contaminates aggregates (`AVG`, `SUM`, `MAX` silently include sentinels)
- It requires callers to know the sentinel convention
- It makes `IS NULL` checks impossible
- It obscures the difference between "zero" and "not measured"

**Use NULL. Always.**

### P9 — Every Table Has a Comment; Non-Obvious Columns Have Comments

Every `CREATE TABLE` must be followed by a `COMMENT ON TABLE`. Every column whose purpose is not immediately obvious from its name must have a `COMMENT ON COLUMN`. This is not optional documentation — it is queryable metadata that AI agents and analysts use to understand the schema without reading source code.

### P10 — Migrations Are Additive; Never Destructive

Once a column or table exists in `main` branch, it must not be dropped without a documented reason in a dedicated migration file with a `-- BREAKING CHANGE:` comment and a corresponding issue. The database schema is a contract. Downstream code, ML pipelines, and MCP tools depend on column stability.

---

## 3. Layer Contracts

Each pipeline layer has a strict contract defining what it may and may not do.

### 040 — Raw Layer

| May | May Not |
|-----|---------|
| Append new rows from source | Update or delete existing rows |
| Store any column the source offers | Filter or drop source columns |
| Carry `NULL` for fields not in this source version | Use sentinel values for missing data |
| Retain deprecated/legacy columns for history | Rename columns from their source name |
| Carry `row_hash` and `raw_payload` | Perform joins or cross-source logic |

### 050 — Staging Layer

| May | May Not |
|-----|---------|
| Resolve identities across sources | Modify raw tables |
| Deduplicate candidate matches | Drop unresolved candidates |
| Insert pending placeholders for new IDs | Block raw inserts |
| Maintain confidence scores | Fabricate cross-source links without evidence |
| Audit all resolution actions | Silently discard conflicts |

### 060 — Core Layer

| May | May Not |
|-----|---------|
| Replace natural keys with surrogate FKs | Drop columns that exist in raw |
| Apply consistent naming conventions | Perform source-specific transformations |
| Denormalize for query performance | Filter rows by business rules |
| Hold all raw columns plus bridged FKs | Contradict raw data |

### 070 — ML Ops Layer

| May | May Not |
|-----|---------|
| Aggregate, pivot, and derive features | Modify core or raw tables |
| Create materialized views | Delete from mart tables |
| Build rolling window features | Introduce data leakage (future data in features) |
| Partition by season or game type | Mix train/test split logic into schema |

---

## 4. Naming Conventions

### Tables
- Snake case, singular noun: `player`, `pitch`, `plate_appearance`
- Prefixed with layer in raw: `raw_statcast.pitch`, `raw_lahman.batting`
- Bridge/junction tables: `player_identity`, `game_identity`, `player_team_season`
- Candidate/staging tables: `player_identity_candidate`, `game_identity_candidate`
- Audit/log tables: `player_identity_resolution_log`, `ingest_run`

### Columns
- Snake case throughout
- Surrogate PKs: `{table_name}_id BIGSERIAL`
- FKs to same-schema tables: `{referenced_table}_id BIGINT`
- Raw source natural keys preserved verbatim from source (e.g. `game_pk`, `batter`, `pitcher`)
- Cross-source ID columns: `mlbam_player_id`, `retrosheet_player_id`, `lahman_player_id`, `bbref_player_id`, `fangraphs_player_id`
- Timestamps: `created_at TIMESTAMPTZ`, `updated_at TIMESTAMPTZ` (maintained by trigger)
- Boolean flags: `{meaning}_flag BOOLEAN` or `is_{meaning} BOOLEAN` (be consistent within a table)
- Deprecated columns: suffix `_deprecated` (e.g. `spin_rate_deprecated`)

### Indexes
- Pattern: `{schema_abbrev}_{table}_{column(s)}_{type}` where type is `idx` (btree), `uidx` (unique), `gin` (GIN)
- Partial indexes use `WHERE` clause and document the condition in the name when brief: `stg_player_identity_mlbam_uidx`
- Never create an index without a documented access pattern justifying it

### Triggers
- Pattern: `trg_{table}_{purpose}` (e.g. `trg_player_identity_updated_at`, `trg_statcast_pitch_player_resolve`)
- Trigger functions in `stg` schema if bridging-related, `core` schema if core-related, or dedicated `sql/080_functions/` file

---

## 5. Source Coverage Targets

The following defines the completeness target for each raw source. "Complete" means every column documented in the source's official schema/spec is present in the raw table.

| Source | Raw Table(s) | Coverage Target | Current Status (2026-05-19) |
|--------|-------------|-----------------|-----------------------------|
| Statcast (Baseball Savant) | `raw_statcast.pitch` | 100% of all documented columns | ✅ Complete (110 cols) |
| Lahman | `raw_lahman.*` | All ~21 CSV tables, 100% of columns | 🟡 ~5 of 21 tables present |
| Retrosheet | `raw_retrosheet.*` | Event, game, sub, roster files | 🟡 Partial |
| Chadwick | `raw_chadwick.*` | Full cwevent 96-field spec + cwgame + cwsub | 🟡 ~35 of 96 cwevent fields |
| MLB Stats API | `raw_mlbapi.*` | All endpoint response fields | 🔴 Needs audit |
| FanGraphs | `raw_fangraphs.*` | Typed stat tables per category | 🔴 Payload-only (no typed tables) |
| Baseball Reference | `raw_bref.*` | Typed stat tables per category | 🔴 Payload-only (no typed tables) |
| ESPN | `raw_espn.*` | Schedule, scores, odds | 🔴 Payload-only |
| Odds | `raw_odds.*` | Pre-game and live odds | 🔴 Payload-only |

---

## 6. Decision Log

This section records significant design decisions and their rationale. New decisions should be appended here with a date.

---

### DEC-001 — NULLs Over Sentinels (2026-05-19)
**Decision:** Use `NULL` for all missing/inapplicable values. No sentinel values.
**Rationale:** See Principle P8. Confirmed in session with repo owner.
**Applies to:** All layers, all sources.

---

### DEC-002 — ALTER TABLE Preferred Over Full Rewrites (2026-05-19)
**Decision:** When adding columns to existing tables, use `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` in a new `*_alter.sql` file rather than rewriting the original `CREATE TABLE`.
**Rationale:** Preserves history of when columns were added, is safe to apply against a database that already has the table populated, and avoids full table rewrites that could lock large tables.
**Exception:** If a table needs structural changes (column type changes, constraint changes, PK changes) a documented breaking-change migration is required.

---

### DEC-003 — Auto-Resolution Trigger Strategy: Partial Insert, Non-Blocking (2026-05-19)
**Decision:** When a new MLBAM player ID arrives in `raw_statcast.pitch`, the trigger inserts a pending placeholder row into `stg.player_identity` (Option A — pragmatic partial insert). The Statcast row commits regardless of bridge state.
**Rationale:** Raw capture must never fail due to bridge lag. A pending placeholder with `confidence_score=0` is immediately useful for downstream enrichment and does not block analysis — it simply means the cross-source IDs are not yet resolved. This is preferable to Option B (block insert until resolved) which would make bulk historical loads fragile.
**Mechanism:** `stg.fn_auto_resolve_statcast_player()` + `trg_statcast_pitch_player_resolve`.

---

### DEC-004 — Core Layer Must Mirror Raw, Fully (2026-05-19)
**Decision:** `core.pitch` must contain every column present in `raw_statcast.pitch`. No selective promotion of "useful" columns.
**Rationale:** The core layer is the single source of truth for analysis. If analysts must join back to raw to get a column, the core layer has failed its purpose. The 74-column gap found in Step 7 was a concrete demonstration of this failure — bat tracking, spray coordinates, defensive alignment, and score context were all missing from core.
**Implementation:** `sql/060_core/004_core_pitch_alter.sql` adds all 74 missing columns.

---

### DEC-005 — updated_at Requires a Trigger, Not Just a Column (2026-05-19)
**Decision:** Any table with an `updated_at TIMESTAMPTZ` column must have a `BEFORE UPDATE` trigger attached. The column alone does nothing.
**Rationale:** Found in both staging and core layers — 8 tables total had `updated_at` columns that were never actually updated. The shared `stg.set_updated_at()` function handles this for all identity and entity tables.
**Fixed in:** `sql/050_staging/004_identity_trigger_and_indexes.sql` (staging), `sql/060_core/004_core_pitch_alter.sql` (core).

---

### DEC-006 — Unique Partial Indexes on All Five Cross-Source ID Columns (2026-05-19)
**Decision:** All five cross-source player ID columns (`mlbam_player_id`, `retrosheet_player_id`, `lahman_player_id`, `bbref_player_id`, `fangraphs_player_id`) must have `CREATE UNIQUE INDEX ... WHERE col IS NOT NULL` on both `stg.player_identity` and `core.player`.
**Rationale:** Without these, two bridge rows for the same player can coexist under different source IDs, and lookups by bbref or fangraphs ID perform full sequential scans. Found that only mlbam, retrosheet, and lahman were indexed — bbref and fangraphs were missing on both tables.
**Fixed in:** `sql/050_staging/004_identity_trigger_and_indexes.sql`, `sql/060_core/004_core_pitch_alter.sql`.

---

### DEC-007 — FanGraphs and BRef Raw Tables: Fully Typed (2026-05-19)
**Decision:** `raw_fangraphs` and `raw_bref` will have fully typed stat tables with one column per stat field. The current JSONB payload-only approach in `006_raw_web_sources.sql` is a temporary scaffold and must be replaced.
**Rationale:** JSONB blobs cannot be joined or aggregated without runtime JSON extraction (`->>`), which is slow, unindexable without GIN, and opaque to query planners. Fully typed tables allow standard SQL aggregation, FK relationships, and column-level statistics used by the query planner. The owner confirmed: typed tables are the target, even if more work.
**Strategy:** Ingest to JSONB payload tables first if needed for a quick initial load, then run a one-time migration to populate the typed tables. Once typed tables are populated, the payload blobs become optional audit artifacts.
**Access method:** pybaseball `batting_stats()`, `pitching_stats()`, `fielding_stats()`, `team_batting()`, `team_pitching()`, and Statcast leaderboard functions for FanGraphs; direct HTML scrape or pybaseball for BRef.

---

### DEC-008 — raw_retrosheet and raw_chadwick: Keep Separate (2026-05-19)
**Decision:** `raw_retrosheet` and `raw_chadwick` remain separate schemas.
**Rationale:** After reviewing both files, the schemas are fundamentally different tools producing different output shapes:
- `raw_retrosheet` stores the **raw event file records** exactly as they appear in Retrosheet `.EVA`/`.EVN` files: line-by-line records (`record_type` IN `id/version/info/start/sub/play/com/data/badj/...`), with `raw_line TEXT` and `raw_fields TEXT[]` preserving the source exactly. It is a faithful byte-level transcript of the source files.
- `raw_chadwick` stores the **parsed and computed output** of the Chadwick Bureau CLI tools (`cwevent`, `cwgame`, `cwsub`): 96 typed, named columns per play event, with fielder IDs, base destinations, assist/error credits, linescore accumulators, and PA state. This is a derived, structured interpretation of the same source.
They are related (cwevent_file FK references raw_retrosheet.event_file) but serve different purposes: retrosheet = raw file archive, chadwick = parsed play-by-play. Merging them would lose this distinction and make it impossible to diagnose parsing differences or re-parse from raw.

---

### DEC-009 — Alembic Strategy: Manual DDL + Alembic for Version Tracking Only (2026-05-19)
**Decision:** DDL is managed manually in `sql/` files as the authoritative source of truth. Alembic is used exclusively for version tracking and migration execution ordering — not for auto-generation from SQLAlchemy models.
**Rationale:** This is the industry-standard approach for data warehouses and analytics platforms where DDL complexity (partitioning, custom types, GIN indexes, materialized views, triggers, RLS) far exceeds what Alembic auto-generate can handle correctly. Auto-generated migrations from ORM models routinely produce incorrect DDL for PostgreSQL-specific features. The pattern used by projects like dbt, Apache Airflow, and Metabase is: write DDL by hand, use the migration tool only to track what has been applied and in what order. Alembic's `op.execute()` can run raw SQL from the `sql/` files directly.
**Workflow:** Each new `sql/` file gets a corresponding Alembic version file that calls `op.execute(open('sql/path/to/file.sql').read())`. The Alembic history provides the audit trail; the `sql/` files provide the readable, reviewable DDL.

---

### DEC-010 — MLB Stats API: JSONB Staging Then Typed Tables (2026-05-19)
**Decision:** MLB Stats API responses are first ingested as JSONB blobs into endpoint-specific raw tables (one table per major endpoint family, e.g. `raw_mlbapi.schedule`, `raw_mlbapi.boxscore`, `raw_mlbapi.player`). A subsequent staging step extracts typed columns into normalized tables.
**Rationale:** The MLB Stats API has 100+ endpoints with deeply nested JSON and fields that change between API versions. Ingesting the full response payload first provides a complete audit record and allows re-extraction without re-calling the API. The two-step approach (raw JSONB → staged typed) is the correct operational pattern: fast, reliable ingest that never loses data, with typed extraction decoupled from the HTTP call. This mirrors how production data pipelines at MLB.com, Fangraphs, and similar organizations handle the Stats API internally.
**Grain:** One row per API response object (one row per game for `/schedule`, one row per batter appearance for `/boxscore` batting lines, etc.). Endpoint families group related endpoints into one table rather than one table per endpoint.

---

### DEC-011 — ML Ops Export: PostgreSQL Materialized Views Primary; Parquet/S3 as Optional Export (2026-05-19)
**Decision:** PostgreSQL materialized views are the primary ML feature serving layer. A Parquet/S3 export capability will be added as an optional export path, not a replacement.
**Rationale:** Materialized views in PostgreSQL provide immediate queryability, are refreshable on demand (`REFRESH MATERIALIZED VIEW CONCURRENTLY`), support `CONCURRENTLY` so reads are never blocked during refresh, and integrate directly with the existing SQLAlchemy/FastAPI/MCP stack without any additional infrastructure. They are the correct primary choice.
Parquet/S3 export is valuable for: (a) training large ML models in Python (pandas/sklearn/PyTorch) where reading from Postgres over many epochs is slow, (b) sharing feature datasets with R users (R natively reads Parquet via `arrow` package), (c) reproducibility — a frozen Parquet snapshot of training data cannot be accidentally changed by a `REFRESH`. A future `baseball export-features --format parquet --dest s3://...` CLI command will cover this use case. R users specifically benefit from Parquet because `arrow::read_parquet()` is dramatically faster than `RPostgres` for large feature tables.
**Implementation order:** Materialized views first (in `070_ml_ops`). Parquet export CLI added in Milestone 3 ingestion work.

---

## 7. What Future Agents Should NOT Do

This section exists because well-intentioned agents have made these mistakes before.

- ❌ **Do not create a new SQL file when modifying an existing table.** Use `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` in-place or in a dedicated `*_alter.sql` migration. Do not duplicate `CREATE TABLE` statements.
- ❌ **Do not drop or rename columns** without a documented breaking-change migration and an issue.
- ❌ **Do not add a `NOT NULL` constraint to a new column** on an existing table — it will fail if any rows exist. New columns must be nullable or have a `DEFAULT`.
- ❌ **Do not use sentinel values** (`-999`, `0`, `'N/A'`, `'UNKNOWN'`) for missing data. Use `NULL`.
- ❌ **Do not mix sources in a single raw table.** Each source gets its own schema and its own tables.
- ❌ **Do not assume file contents** — always fetch the current file from the GitHub API before modifying it. The file may have changed since your context was built.
- ❌ **Do not block raw inserts** waiting for identity resolution. The trigger must be `AFTER INSERT` and non-blocking.
- ❌ **Do not create an `updated_at` column without attaching the `stg.set_updated_at()` trigger** (or an equivalent) to it.
- ❌ **Do not add an index without a documented access pattern.** Indexes are not free — they slow writes and consume disk space.
- ❌ **Do not commit without posting a timestamped update to Issue #9** describing what was done.
- ❌ **Do not auto-generate Alembic migrations from SQLAlchemy models.** DDL is hand-written in `sql/`. Alembic calls `op.execute()` on those files. See DEC-009.
- ❌ **Do not introduce data leakage in ML feature views.** Features must only use data that was knowable at the time the prediction would be made. Rolling window features must use `ROWS BETWEEN N PRECEDING AND 1 PRECEDING` — never `CURRENT ROW` for target-adjacent features.

---

## 8. Open Questions

All open questions from the initial session have been resolved. See Decision Log entries DEC-007 through DEC-011.

| # | Question | Status | Decision |
|---|----------|--------|----------|
| OQ-1 | FanGraphs/BRef: typed tables vs JSONB? | ✅ Resolved | DEC-007: Fully typed |
| OQ-2 | raw_retrosheet + raw_chadwick: merge or separate? | ✅ Resolved | DEC-008: Keep separate |
| OQ-3 | Alembic strategy? | ✅ Resolved | DEC-009: Manual DDL + Alembic version tracking only |
| OQ-4 | MLB Stats API grain? | ✅ Resolved | DEC-010: JSONB ingest → typed staging |
| OQ-5 | ML Ops: materialized views vs Parquet/S3? | ✅ Resolved | DEC-011: MVs primary + Parquet export optional |
