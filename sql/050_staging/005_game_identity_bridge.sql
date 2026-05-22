-- =============================================================================
-- Step 7: Game identity bridge — missing ID columns, unique indexes,
--         MLBAM auto-resolution trigger, resolution audit log,
--         enrichment views, and safe update procedure
--
-- stg.game_identity was created in 002_game_bridge.sql with:
--   mlbam_game_pk, retrosheet_game_id, game_date, season, game_type_code,
--   doubleheader_sequence, home/away/venue team FKs, scheduled_start_time,
--   identity_confidence_score, identity_source, created_at, updated_at
--
-- This file adds the missing cross-source ID columns, indexes, trigger
-- infrastructure, enrichment views, and safe update procedure that mirror
-- the player identity pipeline (004_identity_trigger_and_indexes.sql).
--
-- Apply after 001–004 staging files.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- PART A: Add missing cross-source ID columns to stg.game_identity
--
-- 002_game_bridge.sql only has mlbam_game_pk and retrosheet_game_id.
-- bbref_game_id, espn_game_id, and odds_game_id are required by Issue #14
-- for joining Statcast, BRef game logs, ESPN boxscores, and betting lines.
-- statcast_game_pk is a readable alias for mlbam_game_pk (both are kept;
-- statcast_game_pk mirrors the column name used in raw_statcast.pitch).
-- ---------------------------------------------------------------------------
ALTER TABLE stg.game_identity
    ADD COLUMN IF NOT EXISTS bbref_game_id      TEXT,
    ADD COLUMN IF NOT EXISTS espn_game_id       BIGINT,
    ADD COLUMN IF NOT EXISTS odds_game_id       TEXT,
    ADD COLUMN IF NOT EXISTS statcast_game_pk   BIGINT
        GENERATED ALWAYS AS (mlbam_game_pk) STORED,
    ADD COLUMN IF NOT EXISTS ingest_source      TEXT DEFAULT 'auto:statcast';

COMMENT ON COLUMN stg.game_identity.bbref_game_id IS
    'Baseball Reference game_id string, e.g. LAA/LAA202304030. '
    'Used to join BRef game logs and box scores.';

COMMENT ON COLUMN stg.game_identity.espn_game_id IS
    'ESPN numeric game identifier. '
    'Used to join ESPN schedule, boxscore, and player news tables.';

COMMENT ON COLUMN stg.game_identity.odds_game_id IS
    'Odds provider game identifier (provider-specific string). '
    'Used to join raw_odds.game_line and raw_odds.line_movement.';

COMMENT ON COLUMN stg.game_identity.statcast_game_pk IS
    'Generated alias for mlbam_game_pk matching the column name used in raw_statcast.pitch. '
    'Simplifies joins: raw_statcast.pitch.game_pk = stg.game_identity.statcast_game_pk.';

COMMENT ON COLUMN stg.game_identity.ingest_source IS
    'How this row entered the bridge: auto:statcast | chadwick:seed | mlb_statsapi:schedule | manual.';


-- ---------------------------------------------------------------------------
-- PART B: Unique partial indexes on all game ID columns
--
-- Mirrors the player_identity index pattern: unique WHERE NOT NULL so we
-- can store NULLs for unresolved IDs without violating uniqueness.
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS stg_game_identity_mlbam_uidx
    ON stg.game_identity (mlbam_game_pk)
    WHERE mlbam_game_pk IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS stg_game_identity_retro_uidx
    ON stg.game_identity (retrosheet_game_id)
    WHERE retrosheet_game_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS stg_game_identity_bbref_uidx
    ON stg.game_identity (bbref_game_id)
    WHERE bbref_game_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS stg_game_identity_espn_uidx
    ON stg.game_identity (espn_game_id)
    WHERE espn_game_id IS NOT NULL;

-- Support date-range queries used by the enrichment job
CREATE INDEX IF NOT EXISTS stg_game_identity_game_date_idx
    ON stg.game_identity (game_date DESC);

CREATE INDEX IF NOT EXISTS stg_game_identity_season_idx
    ON stg.game_identity (season);


-- ---------------------------------------------------------------------------
-- PART C: updated_at trigger
--
-- stg.set_updated_at() was created in 004_identity_trigger_and_indexes.sql.
-- Attach it to game_identity here (002_game_bridge.sql did not do this).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_game_identity_updated_at_v2
    BEFORE UPDATE ON stg.game_identity
    FOR EACH ROW
    EXECUTE FUNCTION stg.set_updated_at();


-- ---------------------------------------------------------------------------
-- PART D: Game identity resolution audit log
--
-- Records every time the auto-resolution trigger fires on raw_statcast.pitch
-- for a game_pk. Mirrors stg.player_identity_resolution_log.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stg.game_identity_resolution_log (
    resolution_log_id   BIGSERIAL PRIMARY KEY,
    triggered_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    trigger_source      TEXT NOT NULL,          -- 'raw_statcast.pitch'
    mlbam_game_pk       BIGINT NOT NULL,
    game_date           DATE,
    action_taken        TEXT NOT NULL,          -- 'FOUND_EXISTING' | 'INSERTED_PENDING' | 'CONFLICT_SKIPPED'
    game_identity_id    BIGINT,                 -- the row found or inserted
    note                TEXT
);

CREATE INDEX IF NOT EXISTS stg_game_res_log_game_pk_idx
    ON stg.game_identity_resolution_log (mlbam_game_pk);

CREATE INDEX IF NOT EXISTS stg_game_res_log_triggered_at_idx
    ON stg.game_identity_resolution_log (triggered_at DESC);

CREATE INDEX IF NOT EXISTS stg_game_res_log_game_date_idx
    ON stg.game_identity_resolution_log (game_date DESC);

COMMENT ON TABLE stg.game_identity_resolution_log IS
    'Audit trail for every auto-resolution trigger firing on raw_statcast.pitch for game_pk. '
    'action_taken: FOUND_EXISTING | INSERTED_PENDING | CONFLICT_SKIPPED. '
    'INSERTED_PENDING rows drive the enrichment job to fill bbref_game_id, espn_game_id, etc.';


-- ---------------------------------------------------------------------------
-- PART E: Auto-resolution trigger function
--
-- DEC-003: raw capture must never fail due to bridge lag.
-- When a new pitch arrives with a game_pk not yet in stg.game_identity,
-- insert a confidence=0 placeholder immediately. The downstream enrichment
-- job (MLB StatsAPI schedule endpoint) fills in the cross-source IDs.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_auto_resolve_statcast_game()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_game_identity_id  BIGINT;
    v_action            TEXT;
BEGIN
    IF NEW.game_pk IS NULL THEN
        RETURN NULL;
    END IF;

    -- Check if this game_pk is already bridged
    SELECT game_identity_id
    INTO   v_game_identity_id
    FROM   stg.game_identity
    WHERE  mlbam_game_pk = NEW.game_pk
    LIMIT  1;

    IF FOUND THEN
        INSERT INTO stg.game_identity_resolution_log
            (trigger_source, mlbam_game_pk, game_date, action_taken, game_identity_id, note)
        VALUES
            ('raw_statcast.pitch', NEW.game_pk, NEW.game_date, 'FOUND_EXISTING', v_game_identity_id, NULL);
    ELSE
        BEGIN
            INSERT INTO stg.game_identity (
                mlbam_game_pk,
                game_date,
                season,
                identity_confidence_score,
                identity_source,
                ingest_source
            )
            VALUES (
                NEW.game_pk,
                NEW.game_date,
                EXTRACT(YEAR FROM NEW.game_date)::INT,
                0.0,
                'auto:statcast',
                'auto:statcast'
            )
            RETURNING game_identity_id INTO v_game_identity_id;

            v_action := 'INSERTED_PENDING';

        EXCEPTION
            WHEN unique_violation THEN
                -- Race condition: another session inserted it between our SELECT and INSERT
                v_action := 'CONFLICT_SKIPPED';
                v_game_identity_id := NULL;
        END;

        INSERT INTO stg.game_identity_resolution_log
            (trigger_source, mlbam_game_pk, game_date, action_taken, game_identity_id, note)
        VALUES
            ('raw_statcast.pitch', NEW.game_pk, NEW.game_date, v_action, v_game_identity_id,
             CASE WHEN v_action = 'INSERTED_PENDING'
                  THEN 'Pending enrichment: run MLB StatsAPI schedule lookup to fill retrosheet_game_id, bbref_game_id, espn_game_id'
                  ELSE 'Race condition — row inserted by concurrent session'
             END);
    END IF;

    RETURN NULL;  -- AFTER trigger; return value ignored
END;
$$;

COMMENT ON FUNCTION stg.fn_auto_resolve_statcast_game() IS
    'AFTER INSERT trigger on raw_statcast.pitch. '
    'For each new game_pk, checks stg.game_identity and inserts a confidence=0 placeholder if absent. '
    'Non-blocking: the Statcast row always commits regardless of bridge state (DEC-003). '
    'Downstream enrichment polls stg.v_games_pending_enrichment to fill cross-source IDs.';

-- Attach to raw_statcast.pitch — fires alongside trg_statcast_pitch_player_resolve
CREATE OR REPLACE TRIGGER trg_statcast_pitch_game_resolve
    AFTER INSERT ON raw_statcast.pitch
    FOR EACH ROW
    EXECUTE FUNCTION stg.fn_auto_resolve_statcast_game();

COMMENT ON TRIGGER trg_statcast_pitch_game_resolve ON raw_statcast.pitch IS
    'Fires after every Statcast pitch insert. Ensures game_pk is immediately visible '
    'in stg.game_identity as a pending placeholder, ready for downstream enrichment '
    'to add retrosheet_game_id, bbref_game_id, and espn_game_id.';


-- ---------------------------------------------------------------------------
-- PART F: Enrichment views (three work queues, mirroring player pipeline)
--
--   1. v_games_pending_enrichment         — confidence=0, never touched
--   2. v_games_needing_manual_review      — enrichment ran, confidence < 0.60
--   3. v_live_games_pending_historical_ids — has game_pk, missing retro/bbref
-- ---------------------------------------------------------------------------

-- Queue 1: auto-inserted placeholders awaiting first enrichment pass
CREATE OR REPLACE VIEW stg.v_games_pending_enrichment AS
SELECT
    gi.game_identity_id,
    gi.mlbam_game_pk,
    gi.game_date,
    gi.season,
    gi.ingest_source,
    gi.created_at                           AS first_seen_at,
    COUNT(DISTINCT l.resolution_log_id)     AS times_seen_in_statcast,
    MAX(l.triggered_at)                     AS last_seen_at
FROM stg.game_identity gi
LEFT JOIN stg.game_identity_resolution_log l
    ON  l.mlbam_game_pk = gi.mlbam_game_pk
    AND l.action_taken IN ('INSERTED_PENDING', 'FOUND_EXISTING')
WHERE gi.identity_confidence_score = 0
  AND gi.ingest_source LIKE 'auto:%'
GROUP BY
    gi.game_identity_id, gi.mlbam_game_pk, gi.game_date,
    gi.season, gi.ingest_source, gi.created_at
ORDER BY times_seen_in_statcast DESC, first_seen_at;

COMMENT ON VIEW stg.v_games_pending_enrichment IS
    'Auto-inserted game identity placeholders still needing cross-source ID enrichment. '
    'Feed to the MLB StatsAPI schedule enrichment job. '
    'SELECT mlbam_game_pk, game_date FROM stg.v_games_pending_enrichment;';


-- Queue 2: games where enrichment ran but confidence is still too low to trust
CREATE OR REPLACE VIEW stg.v_games_needing_manual_review AS
SELECT
    gi.game_identity_id,
    gi.mlbam_game_pk,
    gi.game_date,
    gi.season,
    gi.identity_confidence_score,
    gi.identity_source,
    gi.retrosheet_game_id,
    gi.bbref_game_id,
    gi.espn_game_id,
    gi.odds_game_id,
    (gi.retrosheet_game_id IS NULL)         AS missing_retro,
    (gi.bbref_game_id      IS NULL)         AS missing_bbref,
    (gi.espn_game_id       IS NULL)         AS missing_espn,
    (gi.odds_game_id       IS NULL)         AS missing_odds,
    gi.updated_at                           AS last_enrichment_attempt,
    gi.created_at
FROM stg.game_identity gi
WHERE gi.identity_confidence_score > 0
  AND gi.identity_confidence_score < 0.60
ORDER BY gi.identity_confidence_score ASC, gi.game_date DESC;

COMMENT ON VIEW stg.v_games_needing_manual_review IS
    'Games where automated enrichment ran but confidence score is below 0.60. '
    'Requires human verification against MLB StatsAPI, Retrosheet game logs, or BRef. '
    'Update via stg.update_game_identity() procedure to preserve audit trail.';


-- Queue 3: games with a good game_pk but still missing historical source IDs
--           Normal for games played before Retrosheet/BRef publish their data,
--           or very recent games. Re-runs after each Retrosheet data refresh.
CREATE OR REPLACE VIEW stg.v_live_games_pending_historical_ids AS
SELECT
    gi.game_identity_id,
    gi.mlbam_game_pk,
    gi.game_date,
    gi.season,
    gi.identity_confidence_score,
    (gi.retrosheet_game_id IS NULL)         AS awaiting_retro_id,
    (gi.bbref_game_id      IS NULL)         AS awaiting_bbref_id,
    gi.espn_game_id,
    gi.odds_game_id,
    gi.created_at                           AS first_seen_at,
    gi.updated_at                           AS last_updated_at
FROM stg.game_identity gi
WHERE gi.mlbam_game_pk IS NOT NULL
  AND gi.identity_confidence_score >= 0.60
  AND (
      gi.retrosheet_game_id IS NULL
   OR gi.bbref_game_id      IS NULL
  )
ORDER BY gi.game_date DESC;

COMMENT ON VIEW stg.v_live_games_pending_historical_ids IS
    'Games with a valid MLBAM game_pk still awaiting historical register IDs (retro/bbref). '
    'Normal for current-season games; Retrosheet typically publishes end-of-season. '
    'BRef game IDs are usually available within 24–48 hours of game completion. '
    'Re-run enrichment job after each Retrosheet or BRef data refresh.';


-- ---------------------------------------------------------------------------
-- PART G: update_game_identity (PROCEDURE)
--
-- Safe, audited update path for stg.game_identity.
-- All changes from enrichment workers, AI agents, or DBA corrections
-- MUST go through this procedure.
--   - COALESCE semantics: NULL params leave existing values unchanged
--   - Warns on confidence downgrades
--   - Logs every change to stg.game_identity_resolution_log
--
-- Example:
--   CALL stg.update_game_identity(
--       p_game_identity_id  := 101,
--       p_retro_id          := 'ANA202304030',
--       p_bbref_id          := 'LAA/LAA202304030',
--       p_espn_id           := 401234567,
--       p_confidence        := 0.95,
--       p_source            := 'mlb_statsapi:schedule'
--   );
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE stg.update_game_identity(
    p_game_identity_id  BIGINT,
    p_retro_id          TEXT    DEFAULT NULL,
    p_bbref_id          TEXT    DEFAULT NULL,
    p_espn_id           BIGINT  DEFAULT NULL,
    p_odds_id           TEXT    DEFAULT NULL,
    p_confidence        NUMERIC DEFAULT NULL,
    p_source            TEXT    DEFAULT 'manual'
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_old_confidence    NUMERIC;
    v_mlbam_game_pk     BIGINT;
    v_game_date         DATE;
    v_warn_downgrade    BOOLEAN := FALSE;
BEGIN
    SELECT identity_confidence_score, mlbam_game_pk, game_date
    INTO   v_old_confidence, v_mlbam_game_pk, v_game_date
    FROM   stg.game_identity
    WHERE  game_identity_id = p_game_identity_id
    FOR    UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'update_game_identity: game_identity_id % not found', p_game_identity_id;
    END IF;

    IF p_confidence IS NOT NULL AND p_confidence < v_old_confidence THEN
        v_warn_downgrade := TRUE;
        RAISE WARNING
            'update_game_identity: confidence downgrade on game_identity_id % (%.3f → %.3f). '
            'Set p_source clearly so this change is traceable.',
            p_game_identity_id, v_old_confidence, p_confidence;
    END IF;

    UPDATE stg.game_identity
    SET
        retrosheet_game_id        = COALESCE(p_retro_id,    retrosheet_game_id),
        bbref_game_id             = COALESCE(p_bbref_id,    bbref_game_id),
        espn_game_id              = COALESCE(p_espn_id,     espn_game_id),
        odds_game_id              = COALESCE(p_odds_id,     odds_game_id),
        identity_confidence_score = COALESCE(p_confidence,  identity_confidence_score),
        identity_source           = p_source,
        updated_at                = NOW()
    WHERE game_identity_id = p_game_identity_id;

    INSERT INTO stg.game_identity_resolution_log (
        trigger_source, mlbam_game_pk, game_date, action_taken, game_identity_id, note
    )
    VALUES (
        p_source,
        v_mlbam_game_pk,
        v_game_date,
        CASE WHEN v_warn_downgrade THEN 'UPDATED_CONFIDENCE_DOWNGRADE' ELSE 'UPDATED' END,
        p_game_identity_id,
        format(
            'retro=%s bbref=%s espn=%s odds=%s conf=%.3f',
            COALESCE(p_retro_id,         '(unchanged)'),
            COALESCE(p_bbref_id,         '(unchanged)'),
            COALESCE(p_espn_id::TEXT,    '(unchanged)'),
            COALESCE(p_odds_id,          '(unchanged)'),
            COALESCE(p_confidence,        v_old_confidence)
        )
    );
END;
$$;

COMMENT ON PROCEDURE stg.update_game_identity(
    BIGINT, TEXT, TEXT, BIGINT, TEXT, NUMERIC, TEXT
) IS
    'Safe, audited update for stg.game_identity. '
    'COALESCE semantics: NULL params leave existing values unchanged — never wipes good IDs. '
    'Warns on confidence downgrades. Writes every change to game_identity_resolution_log. '
    'All enrichment workers, AI agents, and DBA corrections must use this procedure. '
    'Never UPDATE stg.game_identity directly outside of this procedure.';


COMMIT;
