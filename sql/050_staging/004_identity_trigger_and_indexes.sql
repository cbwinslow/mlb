-- =============================================================================
-- Step 6: Identity bridge — updated_at triggers, missing indexes,
--         MLBAM auto-resolution trigger, and resolution audit log
--
-- Apply after 001_identity_bridge.sql, 002_game_bridge.sql,
-- 003_source_conformance.sql, and 005_staging_indexes.sql.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- PART A: Shared trigger function for updated_at maintenance
--
-- Anomaly: all four identity tables have an updated_at column but NO trigger
-- to maintain it. Every row perpetually shows its original created_at value.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION stg.set_updated_at() IS
    'Generic BEFORE UPDATE trigger function that stamps updated_at = NOW(). '
    'Attached to all stg identity tables that carry an updated_at column.';

-- player_identity
CREATE OR REPLACE TRIGGER trg_player_identity_updated_at
    BEFORE UPDATE ON stg.player_identity
    FOR EACH ROW
    EXECUTE FUNCTION stg.set_updated_at();

-- team_identity
CREATE OR REPLACE TRIGGER trg_team_identity_updated_at
    BEFORE UPDATE ON stg.team_identity
    FOR EACH ROW
    EXECUTE FUNCTION stg.set_updated_at();

-- venue_identity
CREATE OR REPLACE TRIGGER trg_venue_identity_updated_at
    BEFORE UPDATE ON stg.venue_identity
    FOR EACH ROW
    EXECUTE FUNCTION stg.set_updated_at();

-- game_identity
CREATE OR REPLACE TRIGGER trg_game_identity_updated_at
    BEFORE UPDATE ON stg.game_identity
    FOR EACH ROW
    EXECUTE FUNCTION stg.set_updated_at();


-- ---------------------------------------------------------------------------
-- PART B: Missing unique partial indexes on player_identity
--
-- Anomaly: indexes exist for mlbam, retrosheet, lahman but NOT bbref or
-- fangraphs. Lookups joining on bbref_player_id or fangraphs_player_id
-- perform full sequential scans. Also no uniqueness enforcement on those
-- two columns, allowing duplicate bridge rows.
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS stg_player_identity_bbref_uidx
    ON stg.player_identity (bbref_player_id)
    WHERE bbref_player_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS stg_player_identity_fangraphs_uidx
    ON stg.player_identity (fangraphs_player_id)
    WHERE fangraphs_player_id IS NOT NULL;


-- ---------------------------------------------------------------------------
-- PART C: Missing indexes on stg.player_source_conformance
--
-- Anomaly: the table has a unique constraint on
-- (player_identity_id, source_system_code, source_table_name, source_row_pk)
-- but no index on individual lookup columns. Resolving a Statcast batter ID
-- requires scanning the whole table.
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS stg_player_src_conf_mlbam_idx
    ON stg.player_source_conformance (mlbam_player_id)
    WHERE mlbam_player_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS stg_player_src_conf_system_idx
    ON stg.player_source_conformance (source_system_code, player_identity_id);

CREATE INDEX IF NOT EXISTS stg_player_src_conf_bbref_idx
    ON stg.player_source_conformance (bbref_player_id)
    WHERE bbref_player_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS stg_player_src_conf_fangraphs_idx
    ON stg.player_source_conformance (fangraphs_player_id)
    WHERE fangraphs_player_id IS NOT NULL;


-- ---------------------------------------------------------------------------
-- PART D: Resolution audit log
--
-- Records every time the auto-resolution trigger fires, whether it found an
-- existing record, inserted a new pending placeholder, or encountered a
-- conflict. Keeps the trigger function auditable and debuggable.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stg.player_identity_resolution_log (
    resolution_log_id       BIGSERIAL PRIMARY KEY,
    triggered_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    trigger_source          TEXT NOT NULL,        -- e.g. 'raw_statcast.pitch'
    mlbam_player_id         BIGINT NOT NULL,
    player_name             TEXT,                 -- name from source row, if available
    action_taken            TEXT NOT NULL,        -- 'FOUND_EXISTING' | 'INSERTED_PENDING' | 'CONFLICT_SKIPPED'
    player_identity_id      BIGINT,               -- the row that was found or inserted
    note                    TEXT
);

CREATE INDEX IF NOT EXISTS stg_resolution_log_mlbam_idx
    ON stg.player_identity_resolution_log (mlbam_player_id);

CREATE INDEX IF NOT EXISTS stg_resolution_log_triggered_at_idx
    ON stg.player_identity_resolution_log (triggered_at DESC);

COMMENT ON TABLE stg.player_identity_resolution_log IS
    'Audit trail for every auto-resolution trigger firing. '
    'Records whether an existing identity was found, a new pending placeholder was inserted, '
    'or a conflict was skipped. Use this to track unresolved players and drive enrichment jobs.';


-- ---------------------------------------------------------------------------
-- PART E: Auto-resolution trigger function
--
-- When a new row is inserted into raw_statcast.pitch with an mlbam_player_id
-- (batter or pitcher) that does not yet exist in stg.player_identity, this
-- function inserts a PENDING placeholder row so the identity bridge is
-- immediately aware of the new entity.
--
-- Strategy (Option A — pragmatic partial insert):
--   - Insert with mlbam_player_id + player_name (from Statcast) + identity_source='auto'
--   - identity_confidence_score set to 0 (unresolved)
--   - A downstream enrichment job (pybaseball / Chadwick register lookup)
--     fills in the remaining IDs and bumps the confidence score
--   - If the ID already exists: no insert, log FOUND_EXISTING only
--   - If a race condition causes a unique violation: log CONFLICT_SKIPPED,
--     do not raise an error (non-blocking)
--
-- NOTE: This trigger fires AFTER INSERT to avoid blocking the Statcast load.
-- The statcast row is committed regardless of whether identity resolution
-- succeeds. This is intentional: raw capture must never fail due to bridge lag.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_auto_resolve_statcast_player()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_mlbam_ids   BIGINT[];
    v_mlbam_id    BIGINT;
    v_identity_id BIGINT;
    v_action      TEXT;
BEGIN
    -- Collect both batter and pitcher IDs from the inserted row;
    -- deduplicate in case they happen to be the same person (rare but possible
    -- in historic games with unusual lineups)
    v_mlbam_ids := ARRAY(
        SELECT DISTINCT unnest
        FROM   unnest(ARRAY[NEW.batter, NEW.pitcher]) AS unnest
        WHERE  unnest IS NOT NULL
    );

    FOREACH v_mlbam_id IN ARRAY v_mlbam_ids
    LOOP
        -- Check if already in bridge
        SELECT player_identity_id
        INTO   v_identity_id
        FROM   stg.player_identity
        WHERE  mlbam_player_id = v_mlbam_id
        LIMIT  1;

        IF FOUND THEN
            -- Already exists — log and move on
            INSERT INTO stg.player_identity_resolution_log
                (trigger_source, mlbam_player_id, player_name, action_taken, player_identity_id, note)
            VALUES
                ('raw_statcast.pitch', v_mlbam_id, NEW.player_name, 'FOUND_EXISTING', v_identity_id, NULL);
        ELSE
            -- Not found — insert pending placeholder
            BEGIN
                INSERT INTO stg.player_identity
                    (mlbam_player_id, full_name, identity_confidence_score, identity_source)
                VALUES
                    (v_mlbam_id, NEW.player_name, 0.0, 'auto:statcast')
                RETURNING player_identity_id INTO v_identity_id;

                v_action := 'INSERTED_PENDING';

            EXCEPTION
                WHEN unique_violation THEN
                    -- Race condition: another session inserted it between our
                    -- SELECT and INSERT. Safe to skip — the other session
                    -- already logged INSERTED_PENDING.
                    v_action := 'CONFLICT_SKIPPED';
                    v_identity_id := NULL;
            END;

            INSERT INTO stg.player_identity_resolution_log
                (trigger_source, mlbam_player_id, player_name, action_taken, player_identity_id,
                 note)
            VALUES
                ('raw_statcast.pitch', v_mlbam_id, NEW.player_name, v_action, v_identity_id,
                 CASE WHEN v_action = 'INSERTED_PENDING'
                      THEN 'Pending enrichment: run pybaseball/Chadwick register lookup to fill key_retro, key_bbref, key_fangraphs'
                      ELSE 'Race condition — row inserted by concurrent session'
                 END);
        END IF;
    END LOOP;

    RETURN NULL;  -- AFTER trigger; return value is ignored
END;
$$;

COMMENT ON FUNCTION stg.fn_auto_resolve_statcast_player() IS
    'AFTER INSERT trigger function on raw_statcast.pitch. '
    'For each new batter/pitcher MLBAM ID, checks stg.player_identity. '
    'If absent, inserts a PENDING placeholder row (confidence_score=0, source=auto:statcast). '
    'Logs every action to stg.player_identity_resolution_log. '
    'Non-blocking: the statcast row is committed regardless of bridge state. '
    'Downstream enrichment job should poll for rows WHERE identity_confidence_score = 0 '
    'AND identity_source = ''auto:statcast'' and fill in retro/bbref/fangraphs IDs.';


-- Attach the trigger to raw_statcast.pitch
-- AFTER INSERT so the Statcast row always commits first
-- FOR EACH ROW so we have access to NEW.batter / NEW.pitcher
CREATE OR REPLACE TRIGGER trg_statcast_pitch_player_resolve
    AFTER INSERT ON raw_statcast.pitch
    FOR EACH ROW
    EXECUTE FUNCTION stg.fn_auto_resolve_statcast_player();

COMMENT ON TRIGGER trg_statcast_pitch_player_resolve ON raw_statcast.pitch IS
    'Fires after every Statcast pitch insert. Ensures batter and pitcher MLBAM IDs '
    'are immediately visible in stg.player_identity as pending placeholders, '
    'ready for downstream enrichment to complete the cross-source bridge.';


-- ---------------------------------------------------------------------------
-- PART F: Enrichment helper view
--
-- Convenience view for the enrichment job to find all players that arrived
-- via auto-resolution and still need their cross-source IDs populated.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW stg.v_players_pending_enrichment AS
SELECT
    pi.player_identity_id,
    pi.mlbam_player_id,
    pi.full_name,
    pi.identity_source,
    pi.created_at                       AS first_seen_at,
    COUNT(DISTINCT l.resolution_log_id) AS times_seen_in_statcast,
    MAX(l.triggered_at)                 AS last_seen_at
FROM stg.player_identity pi
LEFT JOIN stg.player_identity_resolution_log l
    ON  l.mlbam_player_id = pi.mlbam_player_id
    AND l.action_taken IN ('INSERTED_PENDING', 'FOUND_EXISTING')
WHERE pi.identity_confidence_score = 0
  AND pi.identity_source LIKE 'auto:%'
GROUP BY
    pi.player_identity_id,
    pi.mlbam_player_id,
    pi.full_name,
    pi.identity_source,
    pi.created_at
ORDER BY times_seen_in_statcast DESC, first_seen_at;

COMMENT ON VIEW stg.v_players_pending_enrichment IS
    'All auto-inserted player identity placeholders that still need cross-source ID enrichment. '
    'Shows how many times each player has appeared in raw_statcast data since auto-insertion. '
    'Feed this view to the pybaseball/Chadwick enrichment job: '
    'SELECT mlbam_player_id, full_name FROM stg.v_players_pending_enrichment LIMIT 500;';

COMMIT;
