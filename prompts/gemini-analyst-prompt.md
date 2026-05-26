# GEMINI DEEP RESEARCH PROMPT
## MLB Analytics Platform — Comprehensive Architecture Audit, Finalization, and Implementation Plan

***

## 0. PREFACE — WHO YOU ARE AND WHAT YOU MUST DO

You are acting as a **senior data platform architect and principal engineer** performing a deep, exhaustive technical audit and implementation planning session on a PostgreSQL-first MLB analytics and prediction platform. The repository is:

**GitHub:** https://github.com/cbwinslow/mlb

You must:
1. Pull and read every file in the repository before drawing conclusions.
2. Cross-reference all documentation (README, AGENTS.md, OBJECTIVES.md, ROADMAP.md, docs/*.md, sql/README.md, pyproject.toml, .github/workflows/*.yml).
3. Audit every SQL file in every `sql/` subdirectory.
4. Audit every Python file in the `baseball/` package and `scripts/`.
5. Review all open GitHub Issues (#2, #3, #10, #11, #12, #15, #16, #17, #29, #31) and PRs.
6. Produce a final, finalized, copy-paste-ready implementation plan with explicit file names, exact SQL, and exact Python code.
7. Follow every invariant listed in this prompt and every design decision listed in OBJECTIVES.md and AGENTS.md.

***

## 1. REPOSITORY CONTEXT AND CURRENT STATE (as of 2026-05-25)

### 1.1 Platform Purpose
A multi-source MLB analytics and prediction platform. The goals are:
- Ingest all major MLB data sources (Retrosheet, Statcast/Baseball Savant, MLB Stats API, Lahman, Chadwick Register, FanGraphs, Baseball Reference, ESPN, betting odds)
- Normalize into a canonical PostgreSQL warehouse
- Build ML-ready feature stores and prediction models for game outcomes and pitch-level events
- Support a live betting intelligence layer (DraftKings / Polymarket)
- Expose data via a FastAPI service and MCP tool layer for AI agents
- Eventually monetize as a multi-user hosted service

### 1.2 SQL Schema Layer Architecture
The database uses a numbered folder execution order. Scripts are applied via `bootstrap_db.sh` in numeric sort order:

```
sql/
  010_extensions/       -- pg extensions (uuid-ossp, pgcrypto, etc.)
  020_schemas/          -- CREATE SCHEMA statements
  030_meta/             -- meta.source_system, meta.ingest_run, etc.
  040_raw/              -- Raw landing tables per source
  050_staging/          -- stg.player_identity, stg.game_identity, etc.
  060_core/             -- core.games, core.plate_appearances, core.pitches, etc.
  070_ml_ops/           -- ml.*, ops.*, auth.*, api.*, mart.*
  080_functions/        -- All CREATE OR REPLACE FUNCTION / PROCEDURE
  090_constraints_indexes/ -- FK constraints, partial indexes, check constraints
```

### 1.3 Python Package Structure
```
baseball/
  __init__.py
  settings.py           -- Pydantic BaseSettings, DATABASE_URL, etc.
  cli.py                -- Click CLI: baseball db-init, db-smoke, ingest <source>
  ingestion/
    __init__.py
    orchestrator.py
    loaders.py
    engine.py
    enrich_player_identity.py  -- Player identity enrichment worker
  db/                   -- async SQLAlchemy connection management (planned)
  ml/                   -- ML helpers (planned)
  ops/                  -- Job queue helpers (planned)
  api/                  -- FastAPI app (planned)
scripts/
  enrich_player_identity.py   -- CLI-runnable identity enrichment worker
  bootstrap_db.sh
```

### 1.4 Key Architecture Decisions (from OBJECTIVES.md — MUST HONOR)
- **DEC-001:** All cross-source player identity resolution uses `stg.player_identity` as the single bridge.
- **DEC-002:** Retrosheet is the canonical historical play-by-play source. Statcast augments, not replaces.
- **DEC-003:** Raw ingest must NEVER fail due to identity bridge gaps. Trigger inserts zero-confidence placeholder.
- **DEC-004:** `core.pitches` is the pitch telemetry table; `core.plate_appearances` is the at-bat event table. They are decoupled.
- **DEC-005:** `updated_at` on mutable tables requires a BEFORE UPDATE trigger.
- **DEC-006:** All multi-tenant rows carry `workspace_id UUID NULL` for future hosted isolation.
- **DEC-007:** All raw tables must eventually be fully typed (no JSONB-only final state).
- **DEC-008:** Bootstrap must be fully idempotent (`CREATE IF NOT EXISTS`, `CREATE OR REPLACE`).
- **DEC-009:** All SQL function/procedure calls from Python go through `CALL` or `SELECT fn()` — no raw `UPDATE` on identity tables.
- **DEC-010:** MLB Stats API raw ingest is JSONB-first (Stage 1), typed tables are Stage 2.
- **DEC-011:** All ML artifacts (models, runs, features, predictions) are workspace-scoped.

### 1.5 Critical Open Issues (MUST RESOLVE)

**Issue #31 (CRITICAL — auto-review of PR #30):**
- `sql/030_meta/002_source_registry_fk.sql` references `auth` schema FK which doesn't exist yet at that layer → bootstrap failure
- `sql/050_staging/003_game_identity.sql` line 27 references `util.stg_touch_updated_at()` which is defined in `080_functions` layer → bootstrap failure
- `.refact/buddy/state.json` is a runtime state file that should NOT be in version control
- `sql/080_functions/005_staging_functions.sql` lines 303-326: `util.ingest_play_event` lacks `ON CONFLICT` handling → non-idempotent
- `.gitignore` line 159: `*.bak.refact/buddy/runtime_queue.jsonl` is a concatenation error (should be two lines)
- `pyproject.toml` lines 37-41: dev/test tools (`pytest`, `ruff`, `pylint`) are in main dependencies, not dev group

**Issue #29 (HIGH — auto-review of PR #28):**
- Type mismatches in ingestion functions: player identifiers are INTEGER in raw but UUID in core → FK failures
- Missing `ON DELETE` actions on several new table FKs
- Code duplication between `util.ingest_chadwick_play` and `util.ingest_play_event`

**Issue #17:** Implement `baseball/ingestion/enrich_player_identity.py` and `scripts/enrich_player_identity.py` (multi-mode CLI enrichment worker)

**Issue #16:** Implement `sql/080_functions/013_identity_validation_functions.sql` (8 functions/views/procedures)

**Issue #15:** Implement `sql/050_staging/004_identity_trigger_and_indexes.sql` (trigger, indexes, queue views)

**Issue #12:** Typed tables for `raw_espn` and `raw_odds` schemas

**Issue #11:** Typed tables for `raw_fangraphs` and `raw_bref` (splits, baserunning, plate discipline)

**Issue #10:** Typed extraction tables for `raw_mlbapi` (schedule, boxscore, player, venue, team)

**Issue #3:** Milestone 2 — full schema + Alembic + Docker Compose

**Issue #2:** Milestone 1 — remaining: merge PR #1, Docker Compose, GitHub Labels/Milestones configured

***

## 2. INDUSTRY STANDARDS AND INVARIANTS YOU MUST ENFORCE

### 2.1 SQL Standards
- Every DDL file must begin with `BEGIN;` and end with `COMMIT;`
- Every `CREATE TABLE` uses `CREATE TABLE IF NOT EXISTS`
- Every `CREATE INDEX` uses `CREATE INDEX IF NOT EXISTS`
- Every `CREATE FUNCTION/PROCEDURE` uses `CREATE OR REPLACE`
- Every `ALTER TABLE ADD COLUMN` uses `ADD COLUMN IF NOT EXISTS`
- Every table has `COMMENT ON TABLE '...'`
- Every non-obvious column has `COMMENT ON COLUMN`
- Triggers that reference functions from a later execution layer must be moved to that layer or the function must be promoted to an earlier utility layer
- No FK references to tables in schemas that don't exist yet in execution order
- All UUID primary keys use `gen_random_uuid()` (requires `pgcrypto`)
- `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()` + BEFORE UPDATE trigger on every mutable table
- Partial unique indexes on nullable unique columns (not plain UNIQUE — allows NULLs)
- All ingest functions use `ON CONFLICT ... DO UPDATE` or `ON CONFLICT ... DO NOTHING` (idempotent)

### 2.2 Python Standards
- Python ≥ 3.11, uv for package management
- All code passes `ruff check` and `ruff format` (no violations)
- All code passes `mypy --strict` (or `--ignore-missing-imports` for stubs)
- All async DB code uses `asyncpg` or `async SQLAlchemy` with `AsyncSession`
- Secrets are NEVER logged or stored in the repo — `DATABASE_URL` from env only
- Dev/test dependencies (`pytest`, `ruff`, `mypy`, `pylint`, `pytest-cov`, `factory-boy`, `freezegun`, `pytest-asyncio`) in `[tool.uv.dev-dependencies]` or `[project.optional-dependencies] dev`
- All CLI commands use `Click` (not argparse)
- All modules importable: `from baseball.ingestion.enrich_player_identity import ...`
- Logging uses `logging` module, not `print()`. Format: `%(asctime)s [%(levelname)s] %(name)s — %(message)s`

### 2.3 Git / GitHub Standards
- All work happens on feature branches named `feature/<issue-number>-<short-description>`
- PRs must reference the issue they close with `Closes #N`
- PR body includes: What changed, Why, How to test, Checklist
- All PRs must pass CI before merge (`ci.yml`, `python-ci.yml`, `sql-ci.yml`)
- `.gitignore` must include: `.env`, `*.bak`, `.refact/`, `__pycache__/`, `*.pyc`, `.pytest_cache/`, `htmlcov/`, `dist/`, `.mypy_cache/`, `*.egg-info/`
- Runtime state files (`.refact/buddy/state.json`, etc.) must never be committed
- Version tags follow semantic versioning: `v0.1.0`, `v0.2.0`, etc.

### 2.4 Testing Standards
- Target: 100% Python coverage (`pytest-cov`), all SQL files validate against a live PostgreSQL instance
- pgTAP for SQL unit tests in `tests/sql/`
- pytest + pytest-asyncio for Python async tests
- All external APIs (MLB StatsAPI, pybaseball, Chadwick URL) are mocked in unit tests (`pytest-mock`, `responses`)
- Integration tests use a real PostgreSQL container (testcontainers or pytest-postgresql)
- All new functions have at least: 1 happy path test, 1 error/edge test
- CI runs all tests on every push and PR

### 2.5 Documentation Standards
- Every new SQL file has a header comment block: purpose, schema(s) affected, dependencies, author, date
- Every Python module has a docstring
- Every public function/class has a docstring with Args/Returns/Raises
- `docs/` directory is always up to date — any schema change requires a docs update in the SAME commit/PR
- `AGENTS.md` is the file map for AI agents — must be updated when files are added/removed/renamed
- `ROADMAP.md` must reflect completed milestones
- `docs/audit_checklist.md` is maintained after every schema change

***

## 3. WHAT YOU MUST PRODUCE

You must produce the following, in this exact order, with complete, production-ready content:

***

### TASK 1: Fix All Bootstrap-Blocking Issues (Issue #31 Priority)

**1A. Fix execution order — trigger function bootstrap failure**
- Identify: `sql/050_staging/003_game_identity.sql` references `util.stg_touch_updated_at()` which lives in `080_functions`
- Fix: Move the `util.stg_touch_updated_at()` function to a new file `sql/010_extensions/002_utility_functions.sql` (or `sql/020_schemas/001_utility_functions.sql`) so it is available before staging layer
- Alternatively: rename it to `util.set_updated_at()` and define it in `sql/080_functions/` but MOVE all trigger attachments that use it to a new file `sql/080_functions/999_attach_updated_at_triggers.sql` that runs AFTER all function definitions
- Provide the complete, final, copy-paste-ready SQL for whichever approach you choose and explain why

**1B. Fix auth schema FK execution order (Issue #31)**
- `sql/030_meta/002_source_registry_fk.sql` adds FKs referencing `auth` schema tables
- `auth` schema is created in `070_ml_ops` layer, which runs AFTER `030_meta`
- Fix: Move all FK definitions that reference `auth`, `ops`, `api`, `ml`, or `mart` to `sql/090_constraints_indexes/` where they belong
- Provide the complete moved file content

**1C. Fix `util.ingest_play_event` idempotency (Issue #31)**
- `sql/080_functions/005_staging_functions.sql` lines 303-326
- Add `ON CONFLICT (plate_appearance_id, pitch_sequence_num) DO NOTHING` to `core.pitches` insert
- Add `ON CONFLICT (game_id, pa_sequence_order) DO UPDATE SET event_result_code = EXCLUDED.event_result_code, ...` to `core.plate_appearances` insert
- Verify no duplication with `util.ingest_statcast_play` and `util.ingest_chadwick_play` — consolidate if redundant
- Provide the complete corrected function

**1D. Fix pyproject.toml dev dependencies**
- Move `pytest`, `pytest-cov`, `pytest-asyncio`, `pytest-mock`, `ruff`, `pylint`, `mypy`, `factory-boy`, `freezegun`, `hypothesis`, `black` to `[tool.uv.dev-dependencies]` or `[project.optional-dependencies] dev`
- Provide complete corrected `pyproject.toml`

**1E. Fix .gitignore**
- Split `*.bak.refact/buddy/runtime_queue.jsonl` into two separate lines
- Add `.refact/` directory to .gitignore
- Provide corrected section of `.gitignore`

**1F. Remove runtime state file from git tracking**
- `.refact/buddy/state.json` must be removed from tracking
- Provide the exact git command: `git rm --cached .refact/buddy/state.json`
- Provide the `.gitignore` entry

***

### TASK 2: Fix Type Mismatches in Ingestion Functions (Issue #29)

**Read `sql/080_functions/` carefully.**

The problem: `core.plate_appearances.batter_id` and `core.plate_appearances.pitcher_id` are `UUID NOT NULL` (references to `core.player`), but `raw_statcast.pitch.batter` and `raw_statcast.pitch.pitcher` are `INTEGER` (MLBAM IDs).

The ingestion functions in `005_staging_functions.sql` apparently try to write integer MLBAM IDs directly into UUID FK columns — causing a type mismatch error.

**Fix design:**
The correct flow for identity-resolved writes is:
1. Look up `stg.player_identity` WHERE `key_mlbam = NEW.batter` → get `player_identity_id`
2. Check if `core.player` row exists for that player_identity_id → get `player_id UUID`
3. Write `player_id` into `core.plate_appearances.batter_id`
4. If no `core.player` row exists yet → insert a minimal placeholder (`INSERT INTO core.player ... ON CONFLICT DO NOTHING`)
5. Then write the plate appearance

**Produce:**
- Complete corrected `util.ingest_statcast_play()` function with proper UUID resolution
- Complete corrected `util.ingest_chadwick_play()` function with proper UUID resolution
- Consolidate with or explicitly deprecate `util.ingest_play_event()` to remove the duplication
- Add `ON DELETE` actions to all FK definitions that are missing them (document each decision: CASCADE, RESTRICT, SET NULL)

***

### TASK 3: Implement Issue #15 — Identity Trigger and Indexes

Produce complete, production-ready, idempotent SQL for:

**File: `sql/050_staging/004_identity_trigger_and_indexes.sql`**

Requirements (from Issue #15):
1. Ensure all required columns exist on `stg.player_identity` (with `ADD COLUMN IF NOT EXISTS`)
2. Create all 5 partial unique indexes (mlbam, retro, bbref, fangraphs, lahman)
3. Create `stg.player_identity_resolution_log` table
4. Create `stg.fn_auto_resolve_statcast_player()` trigger function — idempotent via `ON CONFLICT (key_mlbam) WHERE key_mlbam IS NOT NULL DO NOTHING`
5. Create AFTER INSERT trigger `trg_statcast_pitch_player_resolve` on `raw_statcast.pitch`
6. Create `stg.v_players_pending_enrichment` view
7. Create `stg.v_identity_review_queue` view (rows with confidence < 0.60 older than 24h)
8. Create `stg.set_updated_at()` function and BEFORE UPDATE trigger on `stg.player_identity`

Critical note: The `set_updated_at()` function MUST be defined BEFORE the trigger references it. If it cannot be in an earlier layer file, it must be in `080_functions` and the trigger must be attached in `080_functions/` not in `050_staging/`.

***

### TASK 4: Implement Issue #16 — Identity Validation Functions

Produce complete, production-ready SQL for:

**File: `sql/080_functions/013_identity_validation_functions.sql`**

Requirements (from Issue #16):
1. `stg.fn_validate_identity_completeness()` → summary table, one row
2. `stg.fn_detect_orphaned_pitches()` → pitch rows with no identity placeholder
3. `stg.fn_cross_validate_identities()` → compare against `stg.chadwick_register_import`
4. `stg.fn_pinpoint_player_by_context(date, team_abbr, batting_order_slot, key_mlbam DEFAULT NULL)`
5. `stg.fn_validate_game_lineup(game_date, game_pk)` → cross-check Statcast vs Retrosheet batting order
6. `stg.update_player_identity(...)` → safe update procedure with COALESCE null-safety and audit log write
7. `stg.v_identity_validation_dashboard` view
8. `stg.fn_reconcile_candidates()` → promote high-confidence (≥0.90) rows to `core.player`

Each function must have:
- `COMMENT ON FUNCTION/PROCEDURE/VIEW`
- Idempotent (`CREATE OR REPLACE`)
- Wrapped in `BEGIN; ... COMMIT;`
- Return types exactly as specified in Issue #16

***

### TASK 5: Implement Issue #17 — Python Enrichment Worker

Produce complete, production-ready Python for:

**File: `baseball/ingestion/enrich_player_identity.py`**

Requirements (from Issue #17 and docs/external-tools.md):

Modes (`--mode` flag):
- `seed-chadwick` — download Chadwick `people.csv`, bulk upsert into `stg.player_identity` via `CALL stg.update_player_identity(...)`
- `enrich` — poll `stg.v_players_pending_enrichment`, resolve via: (1) in-memory Chadwick cache, (2) MLB StatsAPI xrefIds, (3) pybaseball exact match, (4) pybaseball fuzzy match. Write via procedure.
- `cross-validate` — refresh Chadwick, call `stg.fn_cross_validate_identities()`, output CSV to `reports/identity_cross_validate_{date}.csv`
- `reconcile` — call `stg.fn_reconcile_candidates()`
- `health` — print JSON from `stg.fn_full_identity_health_report()`
- `status` — query `stg.v_identity_validation_dashboard`, exit code 1 if orphaned_pitches > 0

CLI flags: `--limit INT`, `--dry-run`, `--re-enrich-below FLOAT`, `--log-level STR`

Resolution priority and confidence scores:
1. Chadwick in-memory cache → 0.90
2. MLB StatsAPI `GET /api/v1/people/{key_mlbam}?hydrate=xrefIds` → 0.90 with retro/lahman, 0.75 MLBAM-only
3. pybaseball `playerid_lookup` exact match → 0.85
4. pybaseball `playerid_lookup` fuzzy match → 0.60
5. Below 0.60 → flag only, do not write IDs

All DB writes go through `CALL stg.update_player_identity(...)`.
External APIs are only called from this worker — never from SQL functions.

The file must also be importable as a module:
```python
from baseball.ingestion.enrich_player_identity import load_chadwick, resolve_via_mlb_api, run_enrichment
```

Add matching entry to `baseball/cli.py`:
```bash
baseball enrich [--mode seed-chadwick|enrich|cross-validate|reconcile|health|status] [options]
```

Also produce: **`scripts/enrich_player_identity.py`** — a thin wrapper that calls the module.

***

### TASK 6: Implement Issues #10, #11, #12 — Raw Layer Typed Tables

Produce complete, production-ready SQL for:

**File: `sql/040_raw/004_raw_mlbapi_migration_v2.sql`** (Issue #10)
Tables: `raw_mlbapi.schedule_game`, `raw_mlbapi.boxscore_batting_line`, `raw_mlbapi.boxscore_pitching_line`, `raw_mlbapi.player`, `raw_mlbapi.venue`, `raw_mlbapi.team`
All with: typed columns, `COMMENT ON TABLE`, FK to `meta.ingest_run(ingest_run_id)`, `CREATE TABLE IF NOT EXISTS`, `BEGIN/COMMIT`

**File: `sql/040_raw/006_raw_web_sources_migration_v2.sql`** (Issues #11 and #12)
Tables for raw_fangraphs: `batting_splits`, `pitching_splits`, `baserunning`, `plate_discipline`
Tables for raw_bref: `batting_splits`, `pitching_splits`, `baserunning`, `win_probability`
Tables for raw_espn: `schedule_game`, `boxscore_batting`, `boxscore_pitching`, `player_news`
Tables for raw_odds: `game_line`, `line_movement`
All with: typed columns, `captured_at TIMESTAMPTZ` on odds tables, FKs, `COMMENT ON TABLE`, idempotent

***

### TASK 7: Define the First ML Vertical Slice (Live Win Probability)

Produce a complete, ready-to-implement design for the first live prediction vertical slice:

**The slice:** "Given current game state at any point during a live MLB game, produce a win probability estimate for each team."

**Inputs:**
- `core.games` (current game record)
- `core.plate_appearances` (current PA count, score, inning, out state)
- `core.pitches` (recent pitch telemetry for current pitcher)
- `ml.mv_game_score_context` (materialized view — already exists in `070_ml_ops/010_mv_statcast_player_summary.sql`)
- `mart.live_game_state` (new view to create)

**Model:**
- Feature engineering SQL: produce `CREATE MATERIALIZED VIEW ml.mv_live_wp_features AS ...` with one row per plate appearance, including: score_diff, inning, half_inning, outs_before, base_state, home_team_win_pct_ytd, pitcher_era_l30, batter_woba_l30
- Python: a `baseball/ml/win_probability.py` module with `train_model(season: int)`, `predict_live(game_id: UUID)`, `save_model(run_id: UUID)` using scikit-learn `GradientBoostingClassifier`
- Output table: `core.live_predictions` (game_id, plate_appearance_id, home_win_prob NUMERIC(5,4), created_at)
- SQL for `core.live_predictions` table DDL

**Produce:**
- Complete SQL DDL for `ml.mv_live_wp_features` and `core.live_predictions`
- Complete Python skeleton for `baseball/ml/win_probability.py`
- CLI command: `baseball model train win-probability --season 2024`
- CLI command: `baseball model predict live --game-id <uuid>`

***

### TASK 8: Python Package Subpackage Structure

Produce complete, ready-to-commit file skeletons for ALL planned subpackages:

**`baseball/db/__init__.py`** — async SQLAlchemy engine factory, `get_session()` context manager, workspace-aware `set_workspace_context()` helper for RLS

**`baseball/ingestion/__init__.py`** — exports: `Orchestrator`, `run_ingest`

**`baseball/ml/__init__.py`** — exports: `train_model`, `predict`

**`baseball/ops/__init__.py`** — exports: `enqueue_job`, `poll_jobs`, `get_job_status`

**`baseball/api/__init__.py`** — FastAPI `app` instance with `/health` endpoint

For each file, include:
- Module docstring
- Correct imports
- Type annotations
- At least one concrete function (not just `pass`)

***

### TASK 9: Test Infrastructure

Produce a complete, ready-to-run test scaffold:

**`tests/conftest.py`** — pytest fixtures: `db_url`, `async_engine`, `async_session`, `test_db` (creates schema from SQL files), `chadwick_mock`, `mlb_api_mock`

**`tests/python/test_enrich_player_identity.py`** — minimum 20 tests covering:
- `PendingPlayer` dataclass creation
- `resolve_via_statsapi()` success and not-found cases
- `resolve_via_chadwick_cache()` cache hit and miss
- `resolve_via_pybaseball()` exact and fuzzy match
- `run_enrichment()` dry run mode
- `run_enrichment()` exit code 1 on orphaned pitches
- `seed_chadwick_csv()` bulk upsert

**`tests/sql/test_identity_trigger.sql`** — pgTAP tests:
- `stg.fn_auto_resolve_statcast_player()` creates placeholder on INSERT
- `ON CONFLICT` prevents duplicate placeholder
- `stg.v_players_pending_enrichment` shows new rows
- `stg.update_player_identity()` writes audit log
- `stg.fn_detect_orphaned_pitches()` returns 0 in healthy state

**`tests/sql/test_schema_validation.sql`** — pgTAP tests:
- All required schemas exist
- All required tables exist
- All required columns exist on key tables
- All required indexes exist

***

### TASK 10: Documentation Updates

Produce exact content for all documentation files that must be updated:

**`AGENTS.md`** — Updated file maps for:
- `sql/050_staging/004_identity_trigger_and_indexes.sql` (new)
- `sql/080_functions/013_identity_validation_functions.sql` (new)
- `sql/040_raw/004_raw_mlbapi_migration_v2.sql` (new)
- `sql/040_raw/006_raw_web_sources_migration_v2.sql` (new)
- `baseball/ingestion/enrich_player_identity.py` (new/updated)
- `baseball/db/__init__.py` (new)
- `baseball/ml/win_probability.py` (new)
- `core.live_predictions` table (new)

**`ROADMAP.md`** — Mark completed items, add:
- Milestone 1.5 (schema refactor) — COMPLETED 2026-05-25
- Milestone 2 tasks with updated status based on current state

**`docs/testing.md`** — Updated test structure tree and instructions for running all test layers

**`docs/data_ingestion.md`** — Updated with identity resolution worker documentation: modes, scheduling, confidence thresholds

**`docs/audit_checklist.md`** — Updated checklist reflecting all changes in this session

***

## 4. FINALIZATION DECISIONS — MAKE THESE NOW

Before producing any code, you must make and document the following final architecture decisions. State each decision explicitly in a "DECISION LOG" section at the top of your response.

**Decision A:** Where does `util.set_updated_at()` (the `updated_at` maintenance trigger function) live, and how do we ensure it is available before any `050_staging` trigger references it?

**Decision B:** Should `util.ingest_play_event()` be deprecated in favor of `util.ingest_statcast_play()` and `util.ingest_chadwick_play()`, or should all three be refactored into a single generalized function? State which approach and why.

**Decision C:** For `stg.fn_reconcile_candidates()`, which condition gates promotion to `core.player`: (a) `identity_confidence_score >= 0.90` AND all 4 cross-source IDs non-NULL, or (b) `identity_confidence_score >= 0.90` with at least `key_retro` and `key_bbref` non-NULL (allowing Fangraphs to be missing)? State which and why.

**Decision D:** For the live win probability model, should the initial model be: (a) a pre-trained batch model stored in `ml.model_definition` and served via `core.live_predictions`, or (b) a real-time online model updated each inning? State which and why.

**Decision E:** For `raw_mlbapi` typed tables (Issue #10) — should they use `game_pk INTEGER` as the primary key (matching MLB's native integer key) or `game_id UUID REFERENCES core.games(game_id)` (canonical FK)? State which approach and the rationale.

***

## 5. GITHUB WORKFLOW — EXACT EXECUTION PLAN

After all code is produced, provide an exact, step-by-step GitHub workflow for implementing these changes:

```
Step 1: Create branch feature/31-fix-bootstrap-order from main
Step 2: Apply Task 1A, 1B, 1C, 1D, 1E, 1F changes
Step 3: Run bootstrap_db.sh against fresh PostgreSQL 16 — verify 0 errors
Step 4: Run pytest tests/ — verify all existing tests pass
Step 5: Commit: "fix: resolve bootstrap order failures from Issue #31 (auth FK, trigger function dependency)"
Step 6: Open PR targeting main, closes #31, #29
...
```

Provide the COMPLETE step sequence for all tasks above, grouped into logical PRs. Each PR should:
- Close specific issues (list them)
- Be independently mergeable (no cross-PR dependencies unless documented)
- Have all CI checks pass before merge

***

## 6. COMPLETION CRITERIA

The implementation is DONE when ALL of the following are true:

**Bootstrap:**
- [ ] `./scripts/bootstrap_db.sh` runs against a fresh PostgreSQL 16 instance with zero errors
- [ ] All 197+ existing pgTAP tests still pass
- [ ] New SQL tests in Task 9 all pass
- [ ] No "relation does not exist", "function does not exist", or "schema does not exist" errors at any layer

**Python:**
- [ ] `ruff check baseball/ tests/ scripts/` — zero violations
- [ ] `mypy baseball/ --ignore-missing-imports` — zero errors
- [ ] `pytest tests/python/ --cov=baseball --cov-report=term-missing` — coverage ≥ 90%
- [ ] `baseball enrich --mode status` runs successfully against local DB
- [ ] `baseball enrich --mode seed-chadwick --dry-run` completes without errors
- [ ] `baseball enrich --mode enrich --limit=10 --dry-run` logs 10 resolution attempts

**SQL / Schema:**
- [ ] `SELECT * FROM stg.v_identity_validation_dashboard` returns one row with sensible values
- [ ] `SELECT * FROM stg.fn_detect_orphaned_pitches()` returns zero rows in a healthy system
- [ ] `CALL stg.update_player_identity(1, p_key_retro := 'ruthba101', p_updated_by := 'test')` succeeds and writes audit log
- [ ] `SELECT * FROM ml.mv_live_wp_features LIMIT 1` succeeds after bootstrap
- [ ] INSERT into `raw_statcast.pitch` automatically creates `stg.player_identity` placeholder rows

**GitHub:**
- [ ] All issues listed in Section 1.5 are closed with PRs
- [ ] All PRs pass CI (`ci.yml`, `python-ci.yml`, `sql-ci.yml`)
- [ ] AGENTS.md, ROADMAP.md, docs/testing.md, docs/audit_checklist.md are all up to date
- [ ] `.refact/buddy/state.json` is removed from git tracking
- [ ] `pyproject.toml` has dev deps in the correct group

**Documentation:**
- [ ] Every new SQL file has a header comment with: purpose, schema(s), dependencies, date
- [ ] Every new Python module has a module docstring
- [ ] `docs/audit_checklist.md` updated with this session's changes
- [ ] `ROADMAP.md` reflects Milestone 1.5 completed, Milestone 2 in progress

***

## 7. ADDITIONAL CONTEXT

### 7.1 Environment
- **OS:** Ubuntu Server 24.04
- **Database:** PostgreSQL 16 (self-hosted, Docker Compose)
- **Python:** 3.11+, managed with `uv`
- **GPU:** Available (RTX 3060 + K40/K80) for ML training if needed
- **CI:** GitHub Actions with self-hosted runner (`cbwdellr720` server)
- **Repo URL:** https://github.com/cbwinslow/mlb

### 7.2 Key External Libraries
- `pybaseball` — Statcast pull, playerid_lookup
- `python-mlb-statsapi` — MLB Stats API wrapper
- `asyncpg` — async PostgreSQL driver
- `sqlalchemy[asyncio]` — async ORM
- `fastapi` + `uvicorn` — API server
- `pydantic-settings` — settings/config
- `click` — CLI
- `pandas` — data manipulation in ingestion workers
- `scikit-learn` — baseline ML models
- `pytest` + `pytest-asyncio` + `pytest-cov` + `pytest-mock` — testing
- `ruff` + `mypy` — linting and type checking
- `factory-boy` + `freezegun` + `hypothesis` — test utilities

### 7.3 MCP Tool Layer Note
The repo has a planned `mcp/` directory (Milestone 4). The agent tool layer will expose safe query tools against the `mart` and `api` schemas — NOT direct SQL access. This means: if an AI agent wants player stats, it calls `get_player_stats(player_id)` tool, not `SELECT * FROM core.player`. This is important context for how the `baseball/api/` subpackage should be designed.

### 7.4 Betting / Live Intelligence Note
The betting layer (DraftKings / Polymarket integration) depends on `core.live_predictions` being populated with sub-second latency relative to pitch landing. The design should assume: pitch lands in `raw_statcast.pitch` → trigger fires → identity resolved → PA written to `core.plate_appearances` → ML feature view refreshes → prediction written to `core.live_predictions`. This is the target event chain. The first implementation can be polling-based (refresh every 30s); streaming is a later milestone.

***

## 8. FORMAT REQUIREMENTS FOR YOUR RESPONSE

1. **Start with a DECISION LOG section** — numbered decisions A through E, each with a clear rationale.

2. **For each Task (1–10):** Provide the complete, copy-paste-ready code. Do not summarize or truncate. All SQL must be valid PostgreSQL 16 syntax. All Python must be valid Python 3.11+ syntax.

3. **File headers:** Every SQL file must start with a comment block:
   ```sql
   -- =============================================================================
   -- File: sql/xxx_yyy/NNN_description.sql
   -- Purpose: ...
   -- Schemas: ...
   -- Dependencies: ...
   -- Author: cbwinslow
   -- Date: 2026-05-25
   -- =============================================================================
   ```

4. **Every Python file must start with:**
   ```python
   """
   Module: baseball/xxx/yyy.py
   Purpose: ...
   Usage: ...
   """
   ```

5. **GitHub workflow section:** Numbered steps, exact branch names, exact commit messages, exact PR titles, exact issue references.

6. **Completion checklist:** At the end, reproduce the full checklist from Section 6 with [x] or [ ] next to each item based on whether your output satisfies it.

7. **Do not truncate any code.** If a file is long, include it in full. This prompt is being given to Gemini Deep Research which has a large context window — use it.

***

*End of prompt. Begin your analysis by reading the full repository at https://github.com/cbwinslow/mlb, then produce your response in the order specified above.*