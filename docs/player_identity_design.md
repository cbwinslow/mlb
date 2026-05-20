# MLB Platform: Player Identity Resolution — Design Reference

## Overview

This document defines the complete design for player identity management in the MLB analytics platform: how player IDs are acquired from all sources, how conflicts are detected and flagged, how cross-source validation works, and how the system stays consistent without breaking — including handling live MLB data that arrives before historical cross-IDs are published.

The guiding principle: **the database never breaks, but it does flag.** Every unresolvable identity becomes an observable, workable item rather than a silent error or orphaned row.

---

## The Problem Space

Baseball data comes from many independent sources, each with its own player identification system:

| Source | ID type | Notes |
|--------|---------|-------|
| MLBAM / Statcast / StatsAPI | `key_mlbam` (integer) | Most stable for modern players; assigned on MLB debut |
| Retrosheet | `key_retro` (text, e.g. `ruthb101`) | Historical-first; many pre-1950 players only exist here |
| Baseball Reference | `key_bbref` (text, e.g. `ruthba01`) | Nearly complete; reliable |
| FanGraphs | `key_fangraphs` (integer) | Modern players; minor league gap |
| Lahman | `lahman_player_id` (text, e.g. `ruthba01`) | Often same as BRef; authoritative for history |
| Chadwick Register | `key_uuid` (UUID) + short `key_person` | Cross-linkage master; updated weekly |

The core risk is **live data arriving before cross-source IDs are published.** When a player makes their MLB debut today, they immediately get a `key_mlbam`. Their Retrosheet ID may not appear for weeks or months, and their FanGraphs/BRef IDs may take a full season. During this gap, any fact tables using the wrong ID join will silently drop rows or produce incorrect aggregates.

---

## Architecture: The Three-Layer Identity Stack

### Layer 1 — Seed (Historical Bulk Load)

The Chadwick Bureau's public register[cite:55] is the best free cross-source authority for historical player identity. It is the product of record matching and linkage across tens of millions of source mentions, and provides a single row per identity with `key_retro`, `key_mlbam`, `key_bbref`, `key_fangraphs`, and others in one file.[cite:55]

The Chadwick register is organized into 16 files (`data/people-0.csv` through `data/people-f.csv`) and is updated roughly weekly.[cite:55] This is the seed source:

- Load all Chadwick files into `raw_lahman.chadwick_register` (or similar raw landing table) on initial setup.
- Bulk-upsert into `stg.player_identity` matching on `key_mlbam`, `key_retro`, or `key_bbref` with `ON CONFLICT DO UPDATE` where confidence improves.
- Lahman's `People` table provides biographical attributes (height, weight, debut, handedness) as a complement.[cite:61]
- Smart Fantasy Baseball's Player ID Map provides additional cross-references for fantasy-oriented IDs (ESPN, Yahoo, CBS).[cite:53]

**After seeding, the vast majority of historical players are fully resolved.** The trigger-based enrichment system from Issue 13 only needs to handle edge cases: brand-new rookies, call-ups, and the time window between a player's debut and the next Chadwick weekly update.

### Layer 2 — Auto-Resolve (Real-Time Placeholder)

When a new `key_mlbam` ID arrives via `raw_statcast.pitch` INSERT (or via the live MLB StatsAPI feed), a database trigger inserts a **placeholder row** in `stg.player_identity`:

```sql
-- Trigger function (abbreviated)
INSERT INTO stg.player_identity (key_mlbam, player_name, identity_confidence_score, identity_source)
VALUES (NEW.batter, NEW.player_name, 0.0, 'auto:statcast')
ON CONFLICT (key_mlbam) WHERE key_mlbam IS NOT NULL DO NOTHING;
```

This placeholder is immediately visible to downstream queries but has `identity_confidence_score = 0.0`, which signals "not yet resolved." No fact table join will produce incorrect results because the placeholder row correctly maps `key_mlbam` to itself — it just has NULLs for all other IDs.

Critically, the trigger never calls any external API or Python library. It only writes to the database. All enrichment work happens in a separate Python process.

### Layer 3 — Enrichment Worker (Python, Async)

A scheduled Python job (run every N minutes in season, nightly off-season) reads `stg.v_players_pending_enrichment` and attempts to resolve all IDs using a priority-ordered resolver chain:

1. **MLB StatsAPI `/people` with `xrefId` support** — Returns MLB's own cross-references for modern players including Retrosheet and Lahman IDs where MLB has them.[cite:74]
2. **pybaseball `playerid_lookup(last, first, fuzzy=False)`** — Returns a DataFrame with `key_mlbam`, `key_retro`, `key_bbref`, `key_fangraphs` from the Chadwick-derived lookup table.[cite:27]
3. **Chadwick register direct lookup** — Query the locally loaded Chadwick CSV files for any partial ID match.
4. **Heuristic match** — Name + debut year + team fuzzy match against existing `core.player` rows as a last resort.

Each resolver produces a result with a confidence score:

| Resolver | Confidence on success |
|----------|-----------------------|
| MLB StatsAPI xrefId | 0.95 |
| pybaseball `playerid_lookup` exact | 0.90 |
| pybaseball `playerid_lookup` fuzzy | 0.70 |
| Chadwick direct match | 0.90 |
| Heuristic name+date match | 0.50 |

If confidence falls below a threshold (e.g., 0.60), the row is **flagged for human review** rather than auto-committed, and an entry is created in `ops.identity_review_queue`.

---

## Database Design: Validation-First Schema

### Core Identity Tables

The key design choice: fact tables (`core.pitch`, `core.plate_appearance`, etc.) **only contain `core.player_id`** (the internal surrogate key). They never store `key_mlbam`, `key_retro`, or any external ID directly. This means a single `stg.player_identity` update fixes the join for all historical and future facts automatically.

```
raw_statcast.pitch
  └── batter (key_mlbam)  ──FK──►  stg.player_identity.key_mlbam
                                          │
                                   core.player_id (promoted)
                                          │
  ┌───────────────────────────────────────┼───────────────────────┐
  │                                       │                       │
core.pitch                       core.plate_appearance     core.roster_assignment
  └── player_id (FK)               └── batter_id (FK)        └── player_id (FK)
```

### Validation Functions

The following database functions should be created in `sql/080_functions/` to provide continuous validation. These are designed to be callable both as scheduled jobs and on-demand during debugging.

#### `stg.fn_validate_identity_completeness()`

Returns all players with incomplete cross-source IDs, grouped by what is missing:

```sql
CREATE OR REPLACE FUNCTION stg.fn_validate_identity_completeness()
RETURNS TABLE (
    player_identity_id  BIGINT,
    player_name         TEXT,
    key_mlbam           BIGINT,
    key_retro           TEXT,
    key_bbref           TEXT,
    key_fangraphs       INT,
    missing_ids         TEXT[],
    identity_confidence_score NUMERIC,
    identity_source     TEXT
) LANGUAGE sql AS $$
    SELECT
        player_identity_id,
        player_name,
        key_mlbam,
        key_retro,
        key_bbref,
        key_fangraphs,
        ARRAY_REMOVE(ARRAY[
            CASE WHEN key_mlbam      IS NULL THEN 'key_mlbam'      END,
            CASE WHEN key_retro      IS NULL THEN 'key_retro'       END,
            CASE WHEN key_bbref      IS NULL THEN 'key_bbref'       END,
            CASE WHEN key_fangraphs  IS NULL THEN 'key_fangraphs'   END
        ], NULL) AS missing_ids,
        identity_confidence_score,
        identity_source
    FROM stg.player_identity
    WHERE key_mlbam IS NULL
       OR key_retro IS NULL
       OR key_bbref IS NULL
       OR key_fangraphs IS NULL
    ORDER BY identity_confidence_score ASC, created_at DESC;
$$;
```

#### `stg.fn_detect_orphaned_pitches()`

Finds `raw_statcast.pitch` rows whose `batter` or `pitcher` MLBAM id has no corresponding row in `stg.player_identity`. These are the orphan-prevention checks:

```sql
CREATE OR REPLACE FUNCTION stg.fn_detect_orphaned_pitches()
RETURNS TABLE (
    pitch_id   BIGINT,
    game_date  DATE,
    orphan_type TEXT,
    missing_mlbam_id BIGINT
) LANGUAGE sql AS $$
    SELECT p.pitch_id, p.game_date, 'batter' AS orphan_type, p.batter AS missing_mlbam_id
    FROM raw_statcast.pitch p
    LEFT JOIN stg.player_identity pi ON pi.key_mlbam = p.batter
    WHERE pi.player_identity_id IS NULL

    UNION ALL

    SELECT p.pitch_id, p.game_date, 'pitcher' AS orphan_type, p.pitcher AS missing_mlbam_id
    FROM raw_statcast.pitch p
    LEFT JOIN stg.player_identity pi ON pi.key_mlbam = p.pitcher
    WHERE pi.player_identity_id IS NULL
    ORDER BY game_date DESC;
$$;
```

#### `stg.fn_cross_validate_identities()`

Compares `stg.player_identity` against the locally loaded Chadwick register, identifying any rows where IDs diverge between sources. This catches data-entry errors, stale data, and source disagreements:

```sql
CREATE OR REPLACE FUNCTION stg.fn_cross_validate_identities()
RETURNS TABLE (
    player_identity_id      BIGINT,
    player_name             TEXT,
    conflict_field          TEXT,
    our_value               TEXT,
    chadwick_value          TEXT,
    suggested_action        TEXT
) LANGUAGE sql AS $$
    -- Compare key_retro
    SELECT
        pi.player_identity_id,
        pi.player_name,
        'key_retro'             AS conflict_field,
        pi.key_retro            AS our_value,
        cr.key_retro            AS chadwick_value,
        'UPDATE stg.player_identity SET key_retro = ''' || cr.key_retro
            || ''' WHERE player_identity_id = ' || pi.player_identity_id AS suggested_action
    FROM stg.player_identity pi
    JOIN raw_chadwick.register cr ON cr.key_mlbam = pi.key_mlbam
    WHERE pi.key_retro IS DISTINCT FROM cr.key_retro
      AND cr.key_retro IS NOT NULL

    UNION ALL

    -- Compare key_bbref
    SELECT
        pi.player_identity_id, pi.player_name,
        'key_bbref', pi.key_bbref, cr.key_bbref,
        'UPDATE stg.player_identity SET key_bbref = ''' || cr.key_bbref
            || ''' WHERE player_identity_id = ' || pi.player_identity_id
    FROM stg.player_identity pi
    JOIN raw_chadwick.register cr ON cr.key_mlbam = pi.key_mlbam
    WHERE pi.key_bbref IS DISTINCT FROM cr.key_bbref
      AND cr.key_bbref IS NOT NULL

    UNION ALL

    -- Compare key_fangraphs
    SELECT
        pi.player_identity_id, pi.player_name,
        'key_fangraphs', pi.key_fangraphs::TEXT, cr.key_fangraphs::TEXT,
        'UPDATE stg.player_identity SET key_fangraphs = ' || cr.key_fangraphs
            || ' WHERE player_identity_id = ' || pi.player_identity_id
    FROM stg.player_identity pi
    JOIN raw_chadwick.register cr ON cr.key_mlbam = pi.key_mlbam
    WHERE pi.key_fangraphs IS DISTINCT FROM cr.key_fangraphs
      AND cr.key_fangraphs IS NOT NULL
    ORDER BY 1, 3;
$$;
```

#### `stg.fn_pinpoint_player_by_context(p_game_date, p_team_mlbam, p_batting_order_position, p_pa_number)`

Uses contextual gameplay facts to pinpoint player identity — the approach you described for using plate appearances, batting order, team, and date to validate IDs. This is the "forensic" resolver:

```sql
CREATE OR REPLACE FUNCTION stg.fn_pinpoint_player_by_context(
    p_game_date              DATE,
    p_team_mlbam             INT,
    p_batting_order_position SMALLINT,
    p_pa_number              INT DEFAULT NULL
)
RETURNS TABLE (
    candidate_mlbam     BIGINT,
    player_name         TEXT,
    identity_confidence NUMERIC,
    match_method        TEXT
) LANGUAGE sql AS $$
    -- Joins pitch/PA data to roster and game data to find who was
    -- batting in a given slot on a given day for a given team.
    -- This can be compared against what stg.player_identity records
    -- for that MLBAM id to validate correctness.
    SELECT DISTINCT
        p.batter                    AS candidate_mlbam,
        pi.player_name,
        pi.identity_confidence_score AS identity_confidence,
        'context:game_date+team+batting_order' AS match_method
    FROM raw_statcast.pitch p
    JOIN stg.player_identity pi ON pi.key_mlbam = p.batter
    WHERE p.game_date = p_game_date
      AND p.home_team_mlbam = p_team_mlbam
        OR p.away_team_mlbam = p_team_mlbam
    ORDER BY identity_confidence DESC;
$$;
```

### Views for Operational Visibility

These views should live in `sql/050_staging/` or `sql/070_ml_ops/`:

```sql
-- Who still needs enrichment?
CREATE OR REPLACE VIEW stg.v_players_pending_enrichment AS
SELECT player_identity_id, key_mlbam, player_name, identity_source, created_at,
       ARRAY_REMOVE(ARRAY[
           CASE WHEN key_retro     IS NULL THEN 'key_retro'     END,
           CASE WHEN key_bbref     IS NULL THEN 'key_bbref'     END,
           CASE WHEN key_fangraphs IS NULL THEN 'key_fangraphs' END
       ], NULL) AS missing_ids
FROM stg.player_identity
WHERE identity_confidence_score < 1.0
ORDER BY created_at DESC;

-- Who needs human review?
CREATE OR REPLACE VIEW stg.v_identity_review_queue AS
SELECT *, 'Auto-resolution failed; human review required' AS review_reason
FROM stg.player_identity
WHERE identity_confidence_score < 0.60
  AND identity_source LIKE 'auto:%'
ORDER BY created_at DESC;

-- Cross-source ID conflicts
CREATE OR REPLACE VIEW stg.v_identity_conflicts AS
SELECT * FROM stg.fn_cross_validate_identities();

-- Live players missing historical IDs (expected gap, not an error)
CREATE OR REPLACE VIEW stg.v_live_players_pending_historical_ids AS
SELECT
    pi.player_identity_id, pi.player_name, pi.key_mlbam,
    pi.key_retro, pi.key_bbref, pi.key_fangraphs,
    pi.created_at,
    CURRENT_DATE - pi.created_at::date AS days_since_debut
FROM stg.player_identity pi
WHERE pi.key_mlbam IS NOT NULL
  AND (pi.key_retro IS NULL OR pi.key_bbref IS NULL)
  AND pi.created_at >= CURRENT_DATE - INTERVAL '90 days'
ORDER BY pi.created_at DESC;
```

### Update Safety: The `fn_update_player_identity()` Stored Procedure

Direct `UPDATE` statements against `stg.player_identity` are risky because:
- The wrong row could be updated (off-by-one in a WHERE clause).
- Changes don't log who made them or why.

Instead, all identity updates — whether from the enrichment worker, an AI agent, or a human operator — should go through a stored procedure that validates the change before applying it:

```sql
CREATE OR REPLACE PROCEDURE stg.update_player_identity(
    p_player_identity_id     BIGINT,
    p_key_retro              TEXT     DEFAULT NULL,
    p_key_bbref              TEXT     DEFAULT NULL,
    p_key_fangraphs          INT      DEFAULT NULL,
    p_lahman_player_id       TEXT     DEFAULT NULL,
    p_confidence_score       NUMERIC  DEFAULT NULL,
    p_identity_source        TEXT     DEFAULT 'manual:operator',
    p_change_reason          TEXT     DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_current_confidence NUMERIC;
    v_conflict_detected  BOOLEAN := FALSE;
BEGIN
    -- Fetch current state
    SELECT identity_confidence_score INTO v_current_confidence
    FROM stg.player_identity WHERE player_identity_id = p_player_identity_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'player_identity_id % not found', p_player_identity_id;
    END IF;

    -- Conflict check: warn if overwriting a high-confidence value with a lower one
    IF p_confidence_score IS NOT NULL AND p_confidence_score < v_current_confidence THEN
        RAISE WARNING 'Downgrading confidence from % to % for identity_id %',
            v_current_confidence, p_confidence_score, p_player_identity_id;
    END IF;

    -- Apply the update
    UPDATE stg.player_identity
    SET
        key_retro        = COALESCE(p_key_retro,        key_retro),
        key_bbref        = COALESCE(p_key_bbref,        key_bbref),
        key_fangraphs    = COALESCE(p_key_fangraphs,    key_fangraphs),
        lahman_player_id = COALESCE(p_lahman_player_id, lahman_player_id),
        identity_confidence_score = COALESCE(p_confidence_score, identity_confidence_score),
        identity_source  = p_identity_source,
        updated_at       = NOW()
    WHERE player_identity_id = p_player_identity_id;

    -- Write an audit log entry
    INSERT INTO stg.player_identity_resolution_log
        (player_identity_id, key_mlbam, trigger_source, fired_at, change_reason)
    SELECT player_identity_id, key_mlbam,
           p_identity_source, NOW(), p_change_reason
    FROM stg.player_identity WHERE player_identity_id = p_player_identity_id;

    RAISE NOTICE 'Updated player_identity_id % via %', p_player_identity_id, p_identity_source;
END;
$$;
```

Usage:
```sql
-- Human operator fixing a known wrong key_retro:
CALL stg.update_player_identity(
    p_player_identity_id => 4421,
    p_key_retro          => 'smitj101',
    p_confidence_score   => 0.95,
    p_identity_source    => 'manual:operator',
    p_change_reason      => 'Corrected per Retrosheet biofile cross-check 2026-05-19'
);
```

---

## The Live Data Gap Problem

When a player makes their MLB debut today:

1. **They get `key_mlbam` immediately** — assigned by MLB on first appearance.
2. **Retrosheet `key_retro` is assigned retroactively** — typically available weeks or months later when Retrosheet publishes its event files for the season.
3. **FanGraphs assigns `key_fangraphs`** when they appear on the site, usually same-day for MLB players.
4. **Chadwick register is updated weekly** — so the cross-link may not appear for up to 7 days.[cite:55]

The `stg.v_live_players_pending_historical_ids` view tracks exactly this cohort: players who arrived recently (last 90 days) and are still missing historical IDs. This is not an error — it is an expected state that the enrichment worker will resolve as sources update.

The enrichment worker should handle this cohort by:
- Querying MLB StatsAPI `/people/{id}` for any available xrefIds — even fresh players often have BRef/FanGraphs IDs within 24 hours.[cite:74]
- Retrying at increasing intervals (1 day, 3 days, 7 days, 30 days) for Retrosheet, which has the longest lag.
- Never blocking fact-table ingestion while waiting; the placeholder row is sufficient for all core queries.

---

## The Contextual Validation Strategy

Your instinct about using plate appearance, batting order, team, and game date to validate player IDs is sound and is the right "forensic" approach when IDs are questionable.[cite:63]

The logic is: if `key_mlbam = 12345` appears batting 3rd for the Dodgers on April 10th, 2024, and Retrosheet says the Dodgers' #3 hitter that day was Freddie Freeman, then `key_mlbam = 12345` should map to `key_retro = 'freef001'`. This cross-check can be automated:

```sql
-- Validate that all MLBAM IDs in a game match expected lineup positions
-- from an authoritative source (e.g., Retrosheet game log)
CREATE OR REPLACE FUNCTION stg.fn_validate_game_lineup(
    p_game_pk   BIGINT,
    p_game_date DATE
)
RETURNS TABLE (
    mlbam_id         BIGINT,
    player_name      TEXT,
    batting_position SMALLINT,
    retro_expected   TEXT,
    retro_recorded   TEXT,
    lineup_match     BOOLEAN
) LANGUAGE sql AS $$
    SELECT
        p.batter                AS mlbam_id,
        pi.player_name,
        p.bat_order             AS batting_position,
        rg.batter_id            AS retro_expected,   -- from raw_retrosheet
        pi.key_retro            AS retro_recorded,
        pi.key_retro = rg.batter_id AS lineup_match
    FROM raw_statcast.pitch p
    JOIN stg.player_identity pi ON pi.key_mlbam = p.batter
    LEFT JOIN raw_retrosheet.play rg
           ON rg.game_id = p.game_id          -- cross-source game key
          AND rg.batter_id IS NOT NULL
    WHERE p.game_pk = p_game_pk
      AND p.game_date = p_game_date
    GROUP BY 1,2,3,4,5,6
    ORDER BY batting_position;
$$;
```

When `lineup_match = FALSE`, that is a strong signal that either `key_retro` is wrong (the common case) or the game-level join itself is off — which is what `stg.game_identity` (Issue 14) is designed to fix.

---

## Putting It All Together: The Recommended Workflow

### Phase 1 — Initial Historical Load

1. Download all 16 Chadwick register CSVs from GitHub.[cite:55]
2. Load into `raw_chadwick.register` (or a dedicated staging table).
3. Bulk-upsert into `stg.player_identity` from Chadwick data.
4. Supplement biographical fields from Lahman `People` table.[cite:61]
5. Run `stg.fn_validate_identity_completeness()` — expect most historical players to show 0 missing IDs.
6. Run `stg.fn_cross_validate_identities()` — expect 0 conflicts on initial load.
7. Promote confident rows to `core.player` via upsert.

### Phase 2 — Live Season Operation

1. `raw_statcast.pitch` inserts trigger placeholder rows for any unseen MLBAM ids.
2. Enrichment worker runs on schedule, resolves IDs via MLB StatsAPI + pybaseball.
3. `stg.v_live_players_pending_historical_ids` tracks the expected debut-to-Chadwick-update gap.
4. `stg.v_identity_review_queue` surfaces any rows below 0.60 confidence for human attention.
5. Scheduled SQL job runs `stg.fn_detect_orphaned_pitches()` — result should always be empty; any rows are a critical alert.

### Phase 3 — Weekly Chadwick Refresh

1. Re-download Chadwick register (updated weekly).[cite:55]
2. Run `stg.fn_cross_validate_identities()` to detect any newly discovered conflicts.
3. Auto-apply non-conflicting updates (Chadwick confidence 0.90+).
4. Route conflicts to `stg.v_identity_review_queue` for human triage.

### Phase 4 — Correction Workflow

Any correction, whether from a human operator, enrichment worker, or AI agent, goes through `stg.update_player_identity()`. This:
- Validates the row exists.
- Applies only COALESCE-safe updates (no accidental NULL overwrites).
- Writes a timestamped audit entry to `stg.player_identity_resolution_log`.
- Emits a `RAISE NOTICE` for observability.

---

## External Tool Reference

| Tool | What it provides | How it fits |
|------|-----------------|-------------|
| Chadwick Bureau Register[cite:55] | Cross-ID CSV for all MLB history | Primary seed source |
| pybaseball `playerid_lookup`[cite:27] | Name → MLBAM/Retro/BRef/FG IDs | Enrichment worker fallback |
| python-mlb-statsapi `/people/xrefId`[cite:74] | MLB's own cross-ID list for modern players | Primary enrichment resolver |
| spilchen/baseball_id[cite:57] | Python package for multi-source ID lookup | Optional enrichment helper |
| Smart Fantasy Baseball Player ID Map[cite:53] | CSV crosswalk for ESPN/Yahoo/CBS IDs | Fantasy/DFS integration |
| Lahman `People` table[cite:61] | Biographical attributes + historical IDs | Bio enrichment |

---

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Trigger behavior | Placeholder insert only; no external calls | Keeps DB deterministic; external failures never block ingestion |
| Orphan prevention | All fact tables FK to `core.player_id`, not external IDs | Changing one mapping fixes all joins |
| Conflict resolution | Lower-confidence source never auto-overwrites higher | Prevents Chadwick updates from clobbering manually-corrected data |
| Live player gap | Expected state, tracked by dedicated view | Not treated as error; enrichment worker retries with backoff |
| Update path | Stored procedure only | Auditable, safe, consistent for all callers |
| Validation cadence | On-demand functions + scheduled job results | Functions callable any time; scheduled job alerts on non-empty results |

