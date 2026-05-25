This is a comprehensive, production-grade refactoring blueprint designed to be passed directly into an advanced AI coding agent (such as **Aider**, **Cursor Agent**, **Kilo**, or **Claude Code**).

You can save this text as a file named `refactor_blueprint.md` or copy it directly into your agent's chat window to execute the cleanup and decoupling sequence automatically.

---

```markdown
# SYSTEM REFACTORING SPECIFICATION: BASEBALL DATA PLATFORM

## 1. OBJECTIVE & EXECUTIVE SCOPE
You are tasked with executing a surgical refactor of the PostgreSQL database schema and alignment files in this repository. The main goals are:
1. Eliminate schema duplication and redundant migration scripts.
2. Formally decouple the transactional event grain (`core.plate_appearances`) from granular physical telemetry arrays (`core.pitches`), ensuring support for both historical (Lahman, Retrosheet) and ultra-modern high-fidelity streams (Statcast, live MLB StatsAPI).
3. Enforce strict design invariants across staging, core, mapping bridges, and downstream analytics structures.

---

## 2. REPOSITORY SPECIFIC INVARIANTS & CONVENTIONS
When modifying files, adding logic, or altering data flows, you must strictly adhere to the following rules established in this repository:
- **Naming Convention:** All SQL scripts must respect the sequential three-digit numbering schema prefix (`###_description.sql`) already native to the path structure. Do not invent alternative filename schemas.
- **Append-Only Raw Schema:** The `raw` landing files and tables (`040_raw/`) must be treated as append-only. No raw source mutations are permitted.
- **Workspace Isolation:** All multi-tenant tables and analytical generation tasks must verify and support `workspace_id` safely.
- **Secret Management:** Never write, log, or output raw database credentials or connection strings (`DATABASE_URL`). Mask all output flags during execution frames.
- **Agent Resource Constraints:** For any tasks testing external boundaries or checking pipeline verification steps, verify that execution maps run via OpenRouter free model endpoints.

---

## 3. COMPREHENSIVE FILE DELETIONS & FILE CLEANUP
Locate and purge the following files from the file tree, as they represent legacy migration fragments or redundant structural variants:

### 🗑️ Files to Delete:
1. `sql/040_raw/003_raw_statcast_migration_v2.sql`
   - *Reason:* Redundant variant of `003_raw_statcast.sql`. Consolidate structural layouts directly into the primary raw definition file.
2. `sql/050_staging/002_game_bridge.sql`
   - *Reason:* Duplicate abstraction. Unified entity cross-referencing must happen solely inside `005_game_identity_bridge.sql`.
3. `sql/060_core/004_core_pitch_alter.sql`
   - *Reason:* Legacy scratch alteration script. Baseline structural targets must be cleanly compiled inside `002_core_gameplay.sql`.

---

## 4. SCHEMA COUPLING REMEDIATION & MAPPING ARCHITECTURE

### File Target 1: `sql/050_staging/005_game_identity_bridge.sql`
Refactor or replace the contents to ensure a single, authoritative mapping center for games. It must map disparate data sources (Retrosheet's alphanumeric 12-character strings vs. MLB StatsAPI's integer `gamePk` keys) to a single canonical UUID anchor.

```sql
BEGIN;

CREATE TABLE IF NOT EXISTS staging.game_identity_bridge (
    canonical_game_id UUID NOT NULL DEFAULT gen_random_uuid(),
    source_system     VARCHAR(30) NOT NULL, -- 'retrosheet', 'mlb_api', 'statcast'
    source_game_key   VARCHAR(50) NOT NULL, -- e.g., 'BOS202604010' or '747124'
    season            INT NOT NULL,
    game_date         DATE NOT NULL,
    home_team_code    CHAR(3) NOT NULL,
    away_team_code    CHAR(3) NOT NULL,
    created_at        TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT pk_game_identity_bridge PRIMARY KEY (source_system, source_game_key)
);

CREATE INDEX IF NOT EXISTS idx_stg_game_bridge_canonical 
ON staging.game_identity_bridge(canonical_game_id);

COMMIT;

```

### File Target 2: `sql/060_core/002_core_gameplay.sql`

Completely refactor this file. You must cleanly separate the **At-Bat/Plate Appearance** entity from the **Pitch Telemetry** entity. The layout must match the production specification below:

```sql
BEGIN;

-- 1. Canonical Game Matrix Table
CREATE TABLE IF NOT EXISTS core.games (
    game_id         UUID PRIMARY KEY,
    venue_id        UUID NOT NULL,
    home_team_id    UUID NOT NULL,
    away_team_id    UUID NOT NULL,
    game_date       DATE NOT NULL,
    season          INT NOT NULL,
    home_score      SMALLINT DEFAULT 0,
    away_score      SMALLINT DEFAULT 0,
    official_status VARCHAR(20) NOT NULL, -- 'preview', 'live', 'final'
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Decoupled Plate Appearance Event Layer (Dense Event Grain)
CREATE TABLE IF NOT EXISTS core.plate_appearances (
    plate_appearance_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id             UUID NOT NULL REFERENCES core.games(game_id) ON DELETE RESTRICT,
    batter_id           UUID NOT NULL, -- Resolved canonical player link
    pitcher_id          UUID NOT NULL, -- Resolved canonical player link
    inning              SMALLINT NOT NULL,
    half_inning         CHAR(1) NOT NULL CHECK (half_inning IN ('T', 'B')),
    outs_before         SMALLINT NOT NULL CHECK (outs_before BETWEEN 0 AND 2),
    pa_sequence_order   SMALLINT NOT NULL, -- Strict incremental game order sorting
    event_result_code   VARCHAR(30) NOT NULL, -- 'strikeout', 'walk', 'single', 'home_run', etc.
    data_source_lineage VARCHAR(30) NOT NULL, -- 'retrosheet', 'mlb_api'
    workspace_id        UUID NULL,             -- Supports enterprise RLS multi-tenancy
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Pitch Level/Telemetry Array (Granular Physical Sub-Layer)
-- For historical sources, this table stays sparse/unfilled. For modern sources (Statcast), it houses tracking telemetry.
CREATE TABLE IF NOT EXISTS core.pitches (
    pitch_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plate_appearance_id UUID NOT NULL REFERENCES core.plate_appearances(plate_appearance_id) ON DELETE CASCADE,
    pitch_sequence_num  SMALLINT NOT NULL, -- 1st pitch, 2nd pitch of the plate appearance
    balls_before        SMALLINT NOT NULL CHECK (balls_before BETWEEN 0 AND 3),
    strikes_before      SMALLINT NOT NULL CHECK (strikes_before BETWEEN 0 AND 2),
    pitch_type          CHAR(2),           -- 'FF', 'SL', 'CH', 'CU'
    pitch_call          CHAR(1),           -- 'S' (swinging strike), 'C' (called strike), 'B' (ball), 'X' (in play)
    -- Statcast physical tracking block (nullable to guarantee multi-era compatibility)
    release_velocity    NUMERIC(4,1),
    spin_rate           SMALLINT,
    induced_vertical_break NUMERIC(4,2),
    horizontal_break    NUMERIC(4,2),
    plate_x             NUMERIC(4,2),
    plate_z             NUMERIC(4,2),
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uniq_pitch_per_pa UNIQUE (plate_appearance_id, pitch_sequence_num)
);

COMMIT;

```

### File Target 3: `sql/060_core/005_serving_views.sql`

Update your unified analytical viewpoints to ensure that downstream feature stores or web platforms do not break when interfacing with multi-era profiles. Expose flat indicators showing whether rich pitch tracking arrays are present for any given frame.

```sql
BEGIN;

CREATE OR REPLACE VIEW core.v_unified_plate_appearances AS 
SELECT 
    pa.plate_appearance_id,
    pa.game_id,
    g.game_date,
    g.season,
    pa.batter_id,
    pa.pitcher_id,
    pa.inning,
    pa.half_inning,
    pa.event_result_code,
    pa.data_source_lineage,
    CASE 
        WHEN EXISTS (SELECT 1 FROM core.pitches p WHERE p.plate_appearance_id = pa.plate_appearance_id) 
        THEN TRUE 
        ELSE FALSE 
    END AS has_pitch_telemetry
FROM core.plate_appearances pa
JOIN core.games g ON pa.game_id = g.game_id;

COMMIT;

```

---

## 5. RECONCILIATION OF INGESTION RUNTIMES & FUNCTIONS

Review and modify the operational loading functions across the codebase to reflect the structural shift:

1. **`sql/080_functions/003_statcast_mlbapi_functions.sql` & `005_staging_functions.sql**`
* Update ingestion steps parsing live JSON packets or flat migration arrays.
* Ensure the execution blocks first write or resolve the game identifier anchor, push a single operational row into `core.plate_appearances`, capture the returned auto-generated UUID, and use it as the `plate_appearance_id` foreign key when appending tracking metrics to `core.pitches`.


2. **`sql/090_constraints_indexes/006_core_indexes.sql`**
* Verify index implementations focus cleanly on fields used for analytics queries: `core.plate_appearances(game_id, batter_id, pitcher_id)` and `core.pitches(plate_appearance_id)`.



---

## 6. EXECUTION & VALIDATION SEQUENCE

Once you finish refactoring the target directory trees:

1. Execute the system database bootstrap workflow using `./scripts/bootstrap_db.sh` or through the target CLI entry point to verify error-free creation of tables, views, and index components.
2. Run the platform verification tests via `pytest` to ensure structural code patterns do not violate active integration rules or breaking schemas.

```

```

## Implementation Plan – Refactor SQL Schema & Align Documentation  

### Overview
We will execute the refactoring blueprint outlined in refactor-blueprint.md. The goal is to clean up duplicated migration scripts, decouple the plate‑appearance grain from pitch telemetry, and enforce the repository‑wide invariants. After the schema changes we will update all related documentation (README, docs, AGENTS.md, etc.) and perform a full audit to ensure consistency.

---

### Requirements
1. **Schema Clean‑up**
   - Delete obsolete migration files.
   - Consolidate raw Statcast definition.
   - Replace duplicate game‑bridge script.
   - Remove legacy pitch‑alter script.
2. **New Core Tables**
   - Introduce `core.games`, `core.plate_appearances`, `core.pitches` as per the blueprint.
   - Ensure all tables are created with `IF NOT EXISTS` and wrapped in `BEGIN; … COMMIT;`.
   - Add appropriate comments, indexes, and triggers (`updated_at` where needed).
3. **Staging Adjustments**
   - Implement `staging.game_identity_bridge` (new authoritative mapping table).
   - Update any downstream staging scripts that reference the old bridge.
4. **Views & Functions**
   - Update `core.v_unified_plate_appearances` view.
   - Adjust ingestion functions in `sql/080_functions/*` to write to the new tables and use generated UUIDs.
   - Verify/adjust constraints and indexes in `sql/090_constraints_indexes/*`.
5. **Documentation**
   - Update all READMEs, docs markdown files, and AGENTS.md to reflect new table names, column definitions, and migration flow.
   - Add a “Schema Refactor” section to OBJECTIVES.md and ROADMAP.md.
   - Ensure the “Project Setup” and “Ingestion” docs reference the new scripts.
6. **Testing & Validation**
   - Run the bootstrap script (bootstrap_db.sh) against a fresh DB.
   - Execute the existing pytest suite; add new tests for the new tables and view.
   - Verify that all CI checks pass.
7. **Audit**
   - Perform a systematic audit of every markdown file for outdated schema references.
   - Generate a checklist of docs that were updated and any that still need manual review.

---

### Implementation Steps

| Step | Action | Files Affected | Notes |
|------|--------|----------------|-------|
| **1. Prepare Branch** | Create a feature branch `refactor/schema-cleanup` from `main`. | – | All work done here; PR will be opened against `main`. |
| **2. Delete Redundant Files** | Remove: <br>• 003_raw_statcast_migration_v2.sql <br>• 002_game_bridge.sql <br>• 004_core_pitch_alter.sql | `git rm` these three files. | Commit with message “Remove legacy migration scripts (DEC‑001)”. |
| **3. Consolidate Statcast Raw Definition** | Ensure 003_raw_statcast.sql contains the full 110‑column spec (already present). No further changes needed. | 003_raw_statcast.sql | Verify column list matches blueprint; add comments if missing. |
| **4. Add Game Identity Bridge** | Create/replace 005_game_identity_bridge.sql with the blueprint SQL (BEGIN…COMMIT). | New file 005_game_identity_bridge.sql | Use `CREATE TABLE IF NOT EXISTS` and the index definition. |
| **5. Refactor Core Gameplay** | Replace the entire content of 002_core_gameplay.sql with the three‑table definition (games, plate_appearances, pitches) from the blueprint. | 002_core_gameplay.sql | Keep existing `BEGIN; … COMMIT;`. Add `COMMENT ON TABLE` and `COMMENT ON COLUMN` for any non‑obvious fields. |
| **6. Update Serving Views** | Modify 005_serving_views.sql to include the new `core.v_unified_plate_appearances` view definition. | 005_serving_views.sql | Ensure view references the new tables. |
| **7. Adjust Ingestion Functions** | In 003_statcast_mlbapi_functions.sql and 005_staging_functions.sql: <br>• Insert logic to resolve/create a `canonical_game_id` via `staging.game_identity_bridge`. <br>• Insert a row into `core.plate_appearances` and capture its UUID. <br>• Use that UUID when inserting into `core.pitches`. | `sql/080_functions/*.sql` | Add necessary `RETURNING` clauses and error handling. |
| **8. Verify Constraints & Indexes** | Review 006_core_indexes.sql. Add/adjust indexes: <br>• `core.plate_appearances(game_id, batter_id, pitcher_id)` <br>• `core.pitches(plate_appearance_id)` <br>• Ensure FK constraints reference the new tables. | 006_core_indexes.sql | Use `IF NOT EXISTS` for each index. |
| **9. Update Documentation – Core** | • Update architecture.md to show new core tables and relationships. <br>• Revise data-dictionary.md with column definitions for `core.games`, `core.plate_appearances`, `core.pitches`. <br>• Add a “Schema Refactor” subsection in OBJECTIVES.md. | `docs/*.md`, OBJECTIVES.md | Keep existing diagrams up‑to‑date (Mermaid if used). |
| **10. Update README & Project Summary** | • Reflect new migration flow (raw → staging → core). <br>• Mention the new `game_identity_bridge` table. <br>• Update badge/status for “Schema Refactor – Completed”. | README.md, project-summary.md | Ensure links to the new SQL files are correct. |
| **11. Update AGENTS.md** | Add a note that agents must now read the updated blueprint and that the three files were removed. | AGENTS.md | Follow the “Read this file before making changes” pattern. |
| **12. Update Roadmap** | Add a milestone entry “Schema Refactor Completed – May 2026”. | ROADMAP.md | Mark as done. |
| **13. Run Bootstrap & Tests** | • Execute bootstrap_db.sh on a fresh PostgreSQL instance. <br>• Run `pytest` (including sql if present). <br>• Add new tests in sql to verify that the new tables are created and that the view returns correct `has_pitch_telemetry` flag. | – | Fix any failures before proceeding. |
| **14. Documentation Audit** | • Search the repo for old table names (`core.pitch`, `core.game_bridge`, etc.) using `grep`. <br>• Update any remaining references. <br>• Produce an audit checklist (file `docs/audit_checklist.md`) listing each doc scanned and status (updated / verified). | All markdown files | Use a script or manual grep; ensure no stale references remain. |
| **15. Final Review & PR** | • Run `git status` to ensure only intended files are changed. <br>• Commit with a detailed message (see “Commit Message Format” in AGENTS.md). <br>• Open a PR, request review from repo owner. | – | Include a summary of schema changes and doc updates in the PR description. |
| **16. Post‑Merge Tasks** | • Tag the repository with `vX.Y.Z-schema-refactor`. <br>• Update CI pipeline if any migration scripts are referenced. <br>• Notify the team (e.g., via Slack) that the schema refactor is live. | – | Ensure downstream services (if any) are aware of the new table names. |

---

### Testing

| Test | Description | Location |
|------|-------------|----------|
| **Schema Creation Test** | Verify that `bootstrap_db.sh` creates all new tables (`core.games`, `core.plate_appearances`, `core.pitches`, `staging.game_identity_bridge`) and that the old tables are not recreated. | `tests/sql/test_schema_creation.py` |
| **View Logic Test** | Insert a plate appearance with and without associated pitches; assert `core.v_unified_plate_appearances.has_pitch_telemetry` returns correct boolean. | `tests/sql/test_unified_view.py` |
| **Ingestion Function Test** | Mock a Statcast JSON payload; run the ingestion function and assert that a row appears in `core.plate_appearances` and related rows in `core.pitches`. | `tests/python/test_ingestion_functions.py` |
| **Index Presence Test** | Query `pg_indexes` to ensure required indexes exist and are unique where specified. | `tests/sql/test_indexes.py` |
| **Documentation Consistency Test** | Simple script that greps for old table names (`core.pitch`, `game_bridge`) across docs and fails if any are found. | `tests/python/test_doc_audit.py` |
| **Rollback Idempotency Test** | Run the bootstrap script twice on the same DB; ensure no errors and that tables are not duplicated. | `tests/sql/test_idempotent_bootstrap.py` |

All tests must pass locally before the PR is opened, and the CI pipeline must run the same suite on the PR.

---

**End of Plan**. Follow the steps sequentially, committing frequently, and keep the documentation audit checklist up‑to‑date. Once the PR is merged, the database schema will be clean, the ingestion pipeline aligned, and the project documentation fully synchronized.