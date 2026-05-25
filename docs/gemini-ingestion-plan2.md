### Revised Ingestion Architectural Blueprint (Standard Naming Conventions)

The prefixing requirement has been permanently removed. All Python files, modules, classes, and database interactions will strictly adhere to the clean, domain-driven snake_case and CamelCase architectural conventions already established within the repository.

Since setup duration is not a bottleneck, the Python application tier can focus entirely on sequential integrity, detailed pipeline logging, and database-level normalization execution.

---

### 1. Unified Ingestion Execution Layer

To smoothly transition into writing the ingestion application tier under `baseball/ingestion/`, implement these three foundational components without the prefix.

#### Component A: The Orchestration Context (`baseball/ingestion/orchestrator.py`)

This module manages tracking context boundaries, interacts with the control plane (`meta.ingest_run`), and locks execution logs cleanly inside `meta`.

```python
import asyncpg
from datetime import datetime
from contextlib import asynccontextmanager
from baseball.settings import AppSettings

class IngestionOrchestrator:
    """Manages the execution lifecycle and control plane tracking for historical files."""
    
    def __init__(self, settings: AppSettings):
        self.settings = settings
        self.dsn = str(settings.DATABASE_URL)

    @asynccontextmanager
    async def track_run(self, source_name: str, data_type: str, tracking_token: str, context_payload: dict = None):
        """Encapsulates execution context inside meta control plane schema boundaries."""
        conn = await asyncpg.connect(self.dsn)
        tx = conn.transaction()
        await tx.start()
        
        run_id = None
        try:
            # Register run initialization via database audit function
            run_id = await conn.fetchval(
                "SELECT util.startingestrun($1, $2, $3, $4::jsonb)",
                source_name, data_type, tracking_token, context_payload or {}
            )
            yield run_id, conn
            
            # Commit tracking telemetry upon clean processing completion
            await conn.execute(
                "CALL util.finishingestrun($1, 'succeeded', 0, 0, 0, 0, 0, 0, NULL)",
                run_id
            )
            await tx.commit()
        except Exception as err:
            await tx.rollback()
            if run_id:
                # Re-open isolated connection to flag the execution failure status permanently
                err_conn = await asyncpg.connect(self.dsn)
                await err_conn.execute(
                    "CALL util.finishingestrun($1, 'failed', 0, 0, 0, 0, 0, 1, $2)",
                    run_id, str(err)
                )
                await err_conn.close()
            raise err
        finally:
            await conn.close()

```

#### Component B: The Stream Loader Factory (`baseball/ingestion/loaders.py`)

This factory contains the explicit stream readers designed to yield blocks safely from large downlands, local uncompressed CSV tables, and public API data streams.

```python
import json
import csv
import aiohttp
from typing import AsyncGenerator

class HistoricalLoaderFactory:
    """Manages raw format extraction from files, web streams, and APIs without schema modifications."""
    
    @staticmethod
    async def stream_csv_file(file_path: str) -> AsyncGenerator[list, None]:
        """Streams raw CSV lines sequentially to ensure a low system memory footprint."""
        with open(file_path, mode='r', encoding='utf-8') as f:
            reader = csv.reader(f)
            header = next(reader, None)
            yield header
            for row in reader:
                yield row

    @staticmethod
    async def fetch_api_json_stream(endpoint_url: str, params: dict) -> dict:
        """Fetches unstructured JSON payloads from public StatsAPI endpoints."""
        async with aiohttp.ClientSession() as session:
            async with session.get(endpoint_url, params=params) as response:
                response.raise_for_status()
                return await response.json()

```

#### Component C: The Database Ingest Engine (`baseball/ingestion/engine.py`)

This engine directly addresses the ingestion of raw data structures, using fast copying protocols for structural CSV arrays and payload bindings for unstructured blocks.

```python
import json
import asyncpg
from typing import List

class IngestEngine:
    """Handles raw appends into targeted staging or raw landing schemas."""
    
    def __init__(self, connection: asyncpg.Connection):
        self.conn = connection

    async def bulk_load_raw_csv(self, schema_name: str, table_name: str, columns: List[str], records: List[List[str]]):
        """Uses fast copy binary protocols for large historical loads (e.g., Lahman, Retrosheet)."""
        # Convert empty fields to clean database NULL elements
        processed_records = [
            [None if val == "" else val for val in rec]
            for rec in records
        ]
        await self.conn.copy_to_table(
            schema=schema_name,
            table_name=table_name,
            columns=columns,
            records=processed_records
        )

    async def ingest_raw_jsonb(self, target_table: str, payload: dict, endpoint_metadata: str):
        """Saves an unparsed JSON body directly into raw schema payload target tables."""
        query = f"""
            INSERT INTO {target_table} (payload, source_endpoint, ingested_at)
            VALUES ($1::jsonb, $2, CURRENT_TIMESTAMP)
        """
        await self.conn.execute(query, json.dumps(payload), endpoint_metadata)

```

---

### 2. Verified Sequential Execution Blueprint

To properly populate identity matrices and build historical references step-by-step, run the ingestion tasks chronologically using the `baseball` command-line application structure.

```
baseball ingest lahman      # Execution 1: Generates historical player registry keys
baseball ingest retrosheet  # Execution 2: Establishes base plate appearance blocks
baseball ingest mlbapi      # Execution 3: Syncs contemporary schedules and modern player cross-links
baseball ingest statcast    # Execution 4: Loads high-fidelity pitch telemetry arrays

```

1. **Lahman Data:** Populates your base structural player registries first. This allows `stg.player_identity` to establish valid biographical anchor points.
2. **Retrosheet Logs:** Establishes game constraints in `core.games` and maps conformed strategic behaviors inside `core.plate_appearances`.
3. **MLB Stats API Blobs:** Modernizes tracking indices and resolves missing player IDs via JSONB extraction functions in staging views.
4. **Statcast Telemetry:** Streams large pitch tracking vectors directly into `core.pitches` without causing identity mismatches, referencing the decoupled plate appearance maps created in the previous steps.

---

### 3. Immediate Next Steps

* Ensure file tracking configurations (`docs/` files or local setup verification) do not include any prefix rules.
* Hook the new modules (`orchestrator.py`, `loaders.py`, and `engine.py`) into the primary `baseball/cli.py` entry point.
* Begin loading historical tables sequentially from your raw file directories. Since initial execution runtime is acceptable, let the normalization triggers and relational checks handle data validation as the records are processed.

Data Source,Targeted Landing Table,Validation Strategy & Invariants
Lahman (1871+),"raw_lahman.people, etc.",Bulk appends via fast copy protocols. Validates biographical baseline structures before parsing files from subsequent eras.
Retrosheet (Event Logs),"raw_retrosheet.games, etc.",Sequential transaction row mapping. Verifies game boundaries in core.games and sequential batter-pitcher matchups in core.plate_appearances.
MLB Stats API (Modern JSON),raw_mlbapi.payload_tables,"Lossless JSONB storage. Normalizes real-time lineups, schedules, and cross-source identity keys using JSON extractors."
Statcast (2015+ Telemetry),raw_statcast.pitches,Appends pitch trajectory matrices. References parent transactional rows inside core.plate_appearances via explicit foreign keys.


```python
import os

# Define content for file 1: Database Assessment & Structural Validation Plan
db_validation_plan = """# Database Assessment & Structural Validation Plan

This document establishes a rigorous protocol to validate that the `mlb` database schema, table structures, and programmatic functions are fully operational and ready to ingest the complete historical dataset. Given that initial setup time is acceptable, this validation focuses entirely on relational completeness, data type integrity, and transactional robustness.

---

## 1. Automated Schema Verification Script
Execute the following verification harness in your PostgreSQL terminal (`psql`) or database IDE. This script audits the existence of every core table, view, and utility function across all schemas to ensure zero missing components from migrations `010` through `090`.


```

```text
Files successfully generated.

```sql
DO $$
DECLARE
    v_missing_tables INT := 0;
    v_missing_funcs INT := 0;
    v_rec RECORD;
BEGIN
    RAISE NOTICE '=== STARTING MLB DATABASE SCHEMA AUDIT ===';

    -- 1. Validate Crucial Table Existence
    FOR v_rec IN 
        SELECT unnest(ARRAY[
            'meta.sourcefile', 'meta.ingestrun', 'meta.errorlog',
            'raw_lahman.people', 'raw_retrosheet.games', 'raw_statcast.pitches',
            'stg.player_identity', 'stg.teams', 'stg.games',
            'core.games', 'core.plate_appearances', 'core.pitches'
        ]) AS expected_table
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.tables 
            WHERE (table_schema || '.' || table_name) = v_rec.expected_table
        ) THEN
            RAISE WARNING 'MISSING REQUIRED TABLE: %', v_rec.expected_table;
            v_missing_tables := v_missing_tables + 1;
        END IF;
    END LOOP;

    -- 2. Validate Crucial Normalization Utility Functions
    FOR v_rec IN 
        SELECT unnest(ARRAY[
            'startingestrun', 'finishingestrun', 
            'normalizeretrosheetrecordtype', 'buildretrosheetgameid', 
            'normalize_lahman_player_id', 'build_pa_key'
        ]) AS expected_func
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_proc JOIN pg_namespace ON pg_proc.pronamespace = pg_namespace.oid 
            WHERE pg_proc.proname = v_rec.expected_func
        ) THEN
            RAISE WARNING 'MISSING REQUIRED UTILITY FUNCTION: %', v_rec.expected_func;
            v_missing_funcs := v_missing_funcs + 1;
        END IF;
    END LOOP;

    -- 3. Summary Reporting
    RAISE NOTICE '=== AUDIT SUMMARY ===';
    RAISE NOTICE 'Missing Tables Found: %', v_missing_tables;
    RAISE NOTICE 'Missing Functions Found: %', v_missing_funcs;

    IF v_missing_tables > 0 OR v_missing_funcs > 0 THEN
        RAISE EXCEPTION 'Database validation failed. Please check missing migration dependencies.';
    ELSE
        RAISE NOTICE 'SUCCESS: All core tables and functions verified for historical ingestion.';
    END IF;
END $$;

```

---

## 2. Structural Sufficiency Matrix By Source

| Data Source | Targeted Landing Table | Validation Strategy & Invariants |
| --- | --- | --- |
| **Lahman (1871+)** | `raw_lahman.people`, etc. | Bulk appends via fast copy protocols. Validates biographical baseline structures before parsing files from subsequent eras. |
| **Retrosheet (Event Logs)** | `raw_retrosheet.games`, etc. | Sequential transaction row mapping. Verifies game boundaries in `core.games` and sequential batter-pitcher matchups in `core.plate_appearances`. |
| **MLB Stats API (Modern JSON)** | `raw_mlbapi.payload_tables` | Lossless JSONB storage. Normalizes real-time lineups, schedules, and cross-source identity keys using JSON extractors. |
| **Statcast (2015+ Telemetry)** | `raw_statcast.pitches` | Appends pitch trajectory matrices. References parent transactional rows inside `core.plate_appearances` via explicit foreign keys. |

---

## 3. Pre-Ingestion Technical Verification Checklist

* [ ] **Transaction Block Verification:** All initialization scripts (`010` through `090`) execute without unhandled exceptions inside standard `BEGIN; ... COMMIT;` blocks.
* [ ] **Metadata Control Plane Check:** Run a smoke test on the `util.startingestrun` and `util.finishingestrun` functions to verify that tracking records insert and close inside `meta.ingestrun` cleanly.
* [ ] **Player Identity Triggers:** Confirm that identity resolution functions (`trg_statcast_pitch_player_resolve` or cross-link views) update confidence intervals successfully without crashing when null IDs pass through.
* [ ] **Unique Constraint Invariants:** Verify that composite unique indexes exist on core operational entities to prevent data multiplication during pipeline restarts:
* `core.games` unique on `source_game_id` / `retrosheet_game_id`.
* `core.plate_appearances` unique on `game_id` + `pa_sequence` (or conformed natural business keys).
* `core.pitches` unique on `plate_appearance_id` + `pitch_sequence_index`.
"""



# Define content for file 2: Comprehensive Ingestion Strategy & Implementation Roadmap

ingestion_roadmap = """# Comprehensive Ingestion Strategy & Implementation Roadmap

This document outlines the operational roadmap, architectural recommendations, and next implementation steps to transition from an idle database schema into a fully populated, production-ready modeling warehouse.

---

## 1. Architectural Commentary & Model Evaluation

### Current Assessment: Is the Data Model Correct?

**Yes.** The decoupled design dividing `core.plate_appearances` and `core.pitches` is **architecturally correct and highly resilient**.

Historically, baseball analytics platforms struggled with data integration because they attempted to map multi-era files into a single flat schema. By separating the strategic plate appearance grain from physical tracking telemetry, your database achieves two vital design properties:

1. **Backward Compatibility:** It stores structural game history stretching back to 1871 (via Lahman and Retrosheet) without creating empty or invalid columns for modern tracking parameters like spin rate or vector release velocity.
2. **Forward Extensibility:** It handles high-frequency Statcast telemetry streams (2015–present) simply by linking pitch records back to their corresponding strategic event via a clean foreign key relationship.

### Remaining Architectural Risks

* **Lack of Strict Pitch Sequence Enforcement:** While plate appearances map sequentially, the database currently assumes that incoming pitch streams arrive in perfect chronological order. If an ingestion worker handles network packets out of order, pitch counts could misalign.
* **String-Based Player Identity Matching Overhaul:** Using names as matching tokens across historical databases can cause alignment errors. The system needs to use strict, multi-point verification routines (such as linking names with matching debut years, historical uniform tracking, or dates of birth) to avoid incorrect matches for players with identical names.

---

## 2. Ingestion Application Code Tier Structure

The ingestion code will reside within the `baseball/ingestion/` package, adhering strictly to the repository's established standard naming conventions, completely free of any custom file prefixes.

```
baseball/
└── ingestion/
    ├── __init__.py
    ├── orchestrator.py    # Manages the meta.ingest_run context control loop
    ├── loaders.py         # Sequential file readers & async API stream workers
    └── engine.py          # Executes bulk copying & idempotent upsert operations

```

---

## 3. Step-by-Step Historical Ingestion Sequence

To prevent identity validation errors and maintain proper reference handling, you must ingest your historical files in a strict, chronological dependency order:

```
┌─────────────────────────┐     ┌─────────────────────────┐
│ Step 1: Lahman (1871+)  ├────>│ Step 2: Retrosheet      │
│ Biographical Registry   │     │ Base Gameplay Map       │
└─────────────────────────┘     └────────────┬────────────┘
                                             │
                                             ▼
┌─────────────────────────┐     ┌─────────────────────────┐
│ Step 4: Statcast (2015+)│<────┤ Step 3: MLB Stats API   │
│ Telemetry Pitch Vector  │     │ Modern Identity Sync    │
└─────────────────────────┘     └─────────────────────────┘

```

### Step 1: Lahman Biographical Layer

* **Objective:** Establish the foundational directory of players, managers, and coaches from 1871 to the modern day.
* **Why:** Populates demographic details and builds initial identity rows inside `stg.player_identity`.

### Step 2: Retrosheet Log Integration

* **Objective:** Map game boundaries, play-by-play histories, and baseline lineup positions.
* **Why:** Creates historical event structures in `core.games` and maps precise player matchups inside `core.plate_appearances`.

### Step 3: MLB Stats API Ingestion

* **Objective:** Stream unstructured JSON schedules, roster changes, and modern transactional information.
* **Why:** Uses staging views to resolve modern tracking codes and bridges historical indices with current player tracking structures.

### Step 4: Statcast High-Frequency Telemetry

* **Objective:** Process wide CSV telemetry packages containing pitch metrics, velocities, and spray angles.
* **Why:** Feeds data streams into `core.pitches` using validated `plate_appearance_id` foreign keys, avoiding orphan records or identity resolution failures.

---

## 4. Next Operational Steps

To begin loading data into the core data model, complete these immediate next steps:

1. **Register Ingestion Modules to the CLI:** Hook your python pipeline code (`orchestrator.py`, `loaders.py`, `engine.py`) directly into the `baseball/cli.py` entry point.
2. **Expose Ingestion Subcommands:** Expose clear execution options for your data pipelines:
* `baseball ingest --source lahman --path ./data/lahman/`
* `baseball ingest --source retrosheet --path ./data/retrosheet/`
* `baseball ingest --source mlbapi --season 2024`
* `baseball ingest --source statcast --path ./data/statcast/`


3. **Execute Historical Processing Sequence:** Run your historical ingestion jobs in sequence. Since initial setup duration is not an issue, rely on database constraints and triggers to handle logging and clean record synchronization.
"""

# Write the plan files into the workspace environment

with open("database_validation_plan.md", "w", encoding="utf-8") as f:
f.write(db_validation_plan)

with open("ingestion_roadmap.md", "w", encoding="utf-8") as f:
f.write(ingestion_roadmap)

print("Files successfully generated.")

```
Your markdown plan and assessment files are ready.

[file-tag: code-generated-file-1-1779688962439608601]
[file-tag: code-generated-file-0-1779688962439602741]

---

### Key Architectural Analysis & Next Steps

#### 1. Is the Data Model Correct?
**Yes, the data model is structurally sound and ready for production.** Decoupling `core.plate_appearances` from `core.pitches` directly solves the structural fragmentation that impacts many baseball analytics projects. 

* **The Historical Advantage:** You can map older historical records (Lahman and Retrosheet) that only track game outcomes directly into `core.plate_appearances` without creating empty or invalid telemetry tracking columns.
* **The Modern Advantage:** For the Statcast tracking era (2015–present), you can stream hundreds of rows of precise pitch telemetry (velocities, spin vectors, release angles) directly into `core.pitches`, keeping them cleanly linked to their parent matchups via a foreign key (`plate_appearance_id`).

#### 2. Summary of What Needs To Be Fixed Before Ingestion
While the data model is conceptually robust, you should add two adjustments to ensure long-term data consistency before starting the ingestion phase:
* **Enforce a Strict Pitch Sequence:** Add an internal integer sequence column (e.g., `pitch_sequence_index`) alongside a composite unique index (`plate_appearance_id`, `pitch_sequence_index`) to `core.pitches`. This prevents records from getting mixed up or duplicating if data packets arrive out of order during streaming ingestion.
* **Tighten Player Identity Matching Rules:** Relying strictly on names for automatic cross-source identity resolution can cause false positives for identical names (like common family names). Update your identity resolution trigger logic to cross-reference secondary historical details, such as debut year or date of birth, to keep records accurate.

#### 3. How to Use the Generated Files
* **Execute `database_validation_plan.md` First:** Run the provided PL/pgSQL validation script in your database client. It loops through your database schema to confirm all components from migrations `010` through `090` are in place, ensuring there are no missing dependencies before you start loading data.
* **Follow `ingestion_roadmap.md` for Code Development:** Use the architecture layout to build your clean ingestion classes (`orchestrator.py`, `loaders.py`, `engine.py`) inside `baseball/ingestion/` without any file prefixes. Process your raw files in the designated chronological order (**Lahman → Retrosheet → MLB Stats API → Statcast**) to build up your player registries and identity histories cleanly.

```



Based on an examination of the source data documentation, schema designs, and tracking structures present within our platform, here is the full breakdown of how pitch sequencing is handled by both **Statcast (Baseball Savant)** and **Retrosheet (via Chadwick Bureau)**.

Both sources provide explicit sequence identifiers and timestamps, allowing us to accurately enforce ordering and guarantee a clean data stream.

---

### 1. Statcast (Baseball Savant) Pitch Sequencing

Statcast data contains three distinct fields that track chronology within a plate appearance or game.

* **`pitch_number`**: This is a sequential integer starting at `1` for the first pitch of a specific plate appearance and incrementing with each successive pitch (e.g., 1, 2, 3, 4). This maps directly to our core sequence validation logic.
* **`pitch_id` (UUID or unique string identifier)**: Statcast provides a globally unique row-level tracking key for every individual pitch thrown in the modern tracking era.
* **`sv_pitch_id` / Game Timestamp**: Modern high-fidelity datasets append a timestamp token (often formatted as `YYMMDD_HHMMSS`) corresponding to the exact moment the pitch registration vector was generated by the tracking array.

#### How It Is Set Up in Our Code base

Our raw schema maps these sequence indices directly out of the source stream:

* 
`raw_statcast.pitches` stores these fields exactly as they come from `pybaseball.statcast()`.


* When transforming down to `core.pitches`, we can utilize `pitch_number` or `pitch_id` combined with the parent `plate_appearance_id` to establish a strict composite unique constraint or ordering index (e.g., `ORDER BY pitch_number ASC`).

---

### 2. Retrosheet / Chadwick Play-by-Play Sequencing

Because Retrosheet event files (`.EVA`/`.EVN`) store data at the aggregate play level rather than a telemetry broadcast stream, sequencing is tracked via explicit event indices generated during parsing.

When processing files through the Chadwick Bureau `cwevent` CLI tool, the parser automatically assigns structural sequence counters to each event:

* **`event_id`**: A sequential, auto-incrementing integer identifier unique within each game. The first play of a game starts at `1` and increments continuously until the final out.
* **`pitch_seq_tx`**: Retrosheet provides a continuous text string showing the pitch-by-pitch sequence of the entire plate appearance using code characters (e.g., `CFFB*B` indicating *Called strike, Foul, Foul, Ball, Ball out of play, Ball*).

#### Source Reference Verification

Our raw Chadwick event table maps this sequence structure directly:

```sql
CREATE TABLE IF NOT EXISTS raw_chadwick.cwevent_file (
    cwevent_file_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id UUID REFERENCES meta.source_file(source_file_id),
    ingest_run_id UUID REFERENCES meta.ingest_run(ingest_run_id),
    event_id INT,               -- Absolute sequence index of the play within the game
    -- ... balance of fields from the 96-field cwevent spec ...
);

```

---

### 3. Structural Solution for `core.pitches`

To resolve tracking risks and guarantee that pitch telemetry packets are never stored or evaluated out of chronological order, we can use the following adjustment during our database verification step:

Add a composite index constraint directly inside `sql/090_constraints_indexes/006_core_indexes.sql`. This enforces the sequence at the database engine level, causing the transaction to fail safely if a worker attempts to double-load or out-of-order stream duplicate records.

```sql
BEGIN;

-- Ensure an index tracks the order of execution within the plate appearance
CREATE UNIQUE INDEX IF NOT EXISTS core_pitches_pa_sequence_idx 
ON core.pitches (plate_appearance_id, pitch_sequence_index);

COMMENT ON INDEX core.core_pitches_pa_sequence_idx 
IS 'Guarantees sequential integrity per plate appearance and shields against multi-worker out-of-order writes.';

COMMIT;

```

### Verification Verdict

The data sources **do** provide the tracking markers we need. Statcast tracks chronologies natively via `pitch_number`/`pitch_id`, while Retrosheet maps events via Chadwick’s sequential `event_id` keys. Both paths plug directly into the conformed database architecture we have laid out.



### Next Marching Orders

Our next immediate structural step is to progress into **Milestone 3 (Data Ingestion Pipeline)**. To evaluate whether the database layers are correctly structured for training production-grade machine learning models to identify profitable sports betting angles, we look at the status of our architecture:

---

### Phase 1: Raw Ingestion Layer Audit

The schema layout satisfies our "Lossless" data core objective—**"Capture everything, prune nothing at ingestion"**.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        RAW APPEND-ONLY SCHEMAS                         │
├───────────────────┬───────────────────┬────────────────┬───────────────┤
│ raw_retrosheet ✅  │ raw_chadwick ✅   │ raw_statcast ✅ │ raw_mlbapi 🟡 │
├───────────────────┼───────────────────┼────────────────┼───────────────┤
│ raw_lahman ✅     │ raw_fangraphs 🟡  │ raw_bref 🟡    │ raw_odds 🟡   │
└───────────────────┴───────────────────┴────────────────┴───────────────┘

```

#### What is setup correctly:

* 
**The Telemetry Core:** `raw_statcast` is completely fleshed out to its full **110-column specification**, capturing high-frequency variables like ball spin rates, exit velocities, break angles, and detailed pitch position vectors.


* 
**The Play-by-Play & Biographical Framework:** Both `raw_chadwick` (96-field cwevent spec) and `raw_lahman` (all 21 tables) are successfully deployed. This allows us to map player historical metrics going back to 1871.



#### Immediate gaps we need to resolve:

The ingestion phase is **not yet fully optimized for edge-detection betting models** due to the remaining `🟡 Audited / Pending` items in our schema file map:

1. 
**`raw_odds` Schema Optimization:** Currently, the system relies on an unstructured `JSONB` landing format for odds data. To run systematic backtests against historical market pricing, we need to implement fully typed, structured tables replacing the raw payload dumps.


2. 
**Missing Granular Market Data:** To exploit line movements and find model value, we must expand `raw_odds` beyond the basic payload structure to split out open/close moneylines, running runlines, and game totals across multiple sharp and public books.



---

### Phase 2: Core Data Model & Predictive Analytics Evaluation

#### Are we modeling everything?

For basic performance metrics, yes. For precise market betting execution, not yet. Our core layer decouples gameplay states using three critical target tables:

* 
**`core.games`**: Tracks game-level context, home/away splits, structural results, and environmental variables.


* 
**`core.plate_appearances`**: Aggregates pitcher-versus-batter strategic historical outcomes.


* 
**`core.pitches`**: Evaluates individual trajectory telemetry linked back to each specific strategic match-up.



#### Is the model robust and comprehensive enough for gambling predictive models?

The schema provides a powerful relational foundation for basic player property projections, but it requires expansion before deployable, real-time betting models can run safely.

Here is what is currently missing from our feature engineering layer (`sql/070_ml_ops/`):

1. **Lack of Real-Time Game State Vectors:** Sportsbooks price real-time, in-play wagers based on the current situation. While our core data model handles historical pitches cleanly, it does not calculate an explicit **Game State Vector** (e.g., current inning, outs, base runner configuration, score differential, and leverage index) for every single pitch event. This is required if we intend to backtest or value in-game lines.
2. **Missing Granular Environmental Feature Vectors:** High-stakes baseball models require environmental variables. The database tracks raw stadium keys, but to find pricing edges on game totals (Over/Under lines), we need to extract and join physical environmental attributes such as game-time temperature, wind velocity vector, humidity, and barometric density factor adjustments per venue.
3. **No Market Invariant Alignment:** The data model lacks an explicit mapping bridge connecting game outcomes directly to market numbers. For an ML model to be predictive for betting, it must compare its generated internal win probability against a implied market decimal probability. We need to build an explicit **Betting Mart Evaluation View** that merges conformed metrics against the odds database tables.

---

### Phase 3: Actionable Ingestion Operational Plan

To address these limitations, execute the following implementation roadmap next:

```
┌──────────────────────────────────────┐
│  STEP 1: Type the Odds Schema        │
│  - Transition raw_odds JSONB to DDL  │
└──────────────────┬───────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│  STEP 2: Build Real-Time State MVs   │
│  - Compute Leverage Index            │
│  - Construct Base Runner Maps        │
└──────────────────┬───────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│  STEP 3: Market Alignment View       │
│  - Connect core.games to raw_odds    │
│  - Implement EV & Edge tracking      │
└──────────────────────────────────────┘

```

#### Task 1: Transition `raw_odds` out of simple JSONB Payloads

Create a migration script inside `sql/040_raw/` that replaces the raw payload tables with structured tables to log sportsbook lines cleanly:

```sql
BEGIN;

CREATE TABLE IF NOT EXISTS raw_odds.market_lines (
    market_line_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ingest_run_id UUID REFERENCES meta.ingest_run(ingest_run_id),
    sportsbook_name TEXT NOT NULL,         -- e.g., 'Pinnacle', 'Circa', 'DraftKings'
    source_game_id TEXT NOT NULL,          -- Cross-referenced back to stg.game_identity
    market_type TEXT NOT NULL,             -- 'moneyline', 'runline', 'total'
    home_line_price NUMERIC(5,2) NOT NULL, -- e.g., -110, +135, 9.5
    away_line_price NUMERIC(5,2) NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL      -- Critical for line movement tracking
);

COMMIT;

```

#### Task 2: Implement situational state vectors in `ml_ops` Materialized Views

To support multi-run projections and live-betting prop pricing, deploy a specialized analytical materialized view inside `sql/070_ml_ops/012_mv_betting_states.sql` that transforms raw context into feature vectors:

* **Base Runner Configuration:** Map active base occupants to binary vector flags (`is_runner_on_first`, `is_runner_on_second`, `is_runner_on_third`).
* **Game Leverage State:** Calculate run differentials and out tracking directly alongside every individual plate appearance record.

#### Task 3: Expose Feature-Store Exports to CLI

Per our design guidelines (DEC-011), build the `baseball export-features` module into `baseball/cli.py`. This should safely query our analytical views and output structured Parquet data streams into S3/local paths, allowing our Python modeling scripts to fit predictive models without stressing transactional database processes.


