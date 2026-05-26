-- =============================================================================
-- Issue #36: Player identity resolution functions for ingestion
--
-- Creates util.resolve_player_id() that resolves MLBAM IDs through
-- stg.player_identity -> core.player bridge before writing to core.plate_appearances.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- util.resolve_player_id() - Resolve MLBAM ID to core.player.player_id
--
-- Input: p_mlbam_player_id BIGINT, p_full_name TEXT
-- Output: BIGINT (resolved core.player.player_id)
--
-- Logic:
--   1. Try to find existing player_identity by mlbam_player_id
--   2. If no identity, create placeholder
--   3. Try to find existing core.player
--   4. If no core.player, create placeholder
--   5. Return the resolved player_id
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION util.resolve_player_id(
    p_mlbam_player_id BIGINT,
    p_full_name TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_identity_id BIGINT;
    v_player_id   BIGINT;
BEGIN
    -- Step 1: Find existing player_identity by mlbam_player_id
    SELECT player_identity_id
    INTO   v_identity_id
    FROM   stg.player_identity
    WHERE  mlbam_player_id = p_mlbam_player_id
    LIMIT  1;

    -- Step 2: If no identity found, create placeholder
    IF NOT FOUND THEN
        INSERT INTO stg.player_identity (
            mlbam_player_id, full_name, identity_confidence_score, identity_source,
            created_at, updated_at
        )
        VALUES (
            p_mlbam_player_id, p_full_name, 0.0, 'auto:ingest_chadwick',
            NOW(), NOW()
        )
        ON CONFLICT (mlbam_player_id) DO UPDATE
            SET full_name = COALESCE(EXCLUDED.full_name, stg.player_identity.full_name),
                updated_at = NOW()
        RETURNING player_identity_id INTO v_identity_id;
    END IF;

    -- Step 3: Find existing core.player via player_identity_id
    SELECT player_id
    INTO   v_player_id
    FROM   core.player
    WHERE  player_identity_id = v_identity_id
    LIMIT  1;

    -- Step 4: If no core.player, create placeholder
    IF NOT FOUND THEN
        INSERT INTO core.player (
            player_identity_id, full_name, active_flag,
            created_at, updated_at
        )
        VALUES (
            v_identity_id, p_full_name, TRUE,
            NOW(), NOW()
        )
        ON CONFLICT (player_identity_id) DO NOTHING
        RETURNING player_id INTO v_player_id;

        -- If still not found (race condition), get the existing one
        IF NOT FOUND THEN
            SELECT player_id
            INTO   v_player_id
            FROM   core.player
            WHERE  player_identity_id = v_identity_id;
        END IF;
    END IF;

    RETURN v_player_id;
END;
$$;

COMMENT ON FUNCTION util.resolve_player_id IS
    'Resolve MLBAM player ID to core.player.player_id through stg.player_identity bridge.
     Creates placeholder identity and player records if they do not exist.';

-- ---------------------------------------------------------------------------
-- util.resolve_team_id() - Resolve MLBAM team ID to core.team.team_id
--
-- Following the same pattern as util.resolve_player_id() for team identity resolution.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION util.resolve_team_id(
    p_mlbam_team_id BIGINT,
    p_team_name TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_identity_id BIGINT;
    v_team_id     BIGINT;
BEGIN
    -- Step 1: Find existing team_identity by mlbam_team_id
    SELECT team_identity_id
    INTO   v_identity_id
    FROM   stg.team_identity
    WHERE  mlbam_team_id = p_mlbam_team_id
    LIMIT  1;

    -- Step 2: If no identity found, create placeholder
    IF NOT FOUND THEN
        INSERT INTO stg.team_identity (
            mlbam_team_id, team_name, identity_confidence_score, identity_source,
            created_at, updated_at
        )
        VALUES (
            p_mlbam_team_id, p_team_name, 0.0, 'auto:ingest_chadwick',
            NOW(), NOW()
        )
        ON CONFLICT (mlbam_team_id) DO UPDATE
            SET team_name = COALESCE(EXCLUDED.team_name, stg.team_identity.team_name),
                updated_at = NOW()
        RETURNING team_identity_id INTO v_identity_id;
    END IF;

    -- Step 3: Find existing core.team via team_identity_id
    SELECT team_id
    INTO   v_team_id
    FROM   core.team
    WHERE  team_identity_id = v_identity_id
    LIMIT  1;

    -- Step 4: If no core.team, create placeholder
    IF NOT FOUND THEN
        INSERT INTO core.team (
            team_identity_id, team_name,
            created_at, updated_at
        )
        VALUES (
            v_identity_id, p_team_name,
            NOW(), NOW()
        )
        ON CONFLICT (team_identity_id) DO NOTHING
        RETURNING team_id INTO v_team_id;

        -- If still not found (race condition), get the existing one
        IF NOT FOUND THEN
            SELECT team_id
            INTO   v_team_id
            FROM   core.team
            WHERE  team_identity_id = v_identity_id;
        END IF;
    END IF;

    RETURN v_team_id;
END;
$$;

COMMENT ON FUNCTION util.resolve_team_id IS
    'Resolve MLBAM team ID to core.team.team_id through stg.team_identity bridge.
     Creates placeholder identity and team records if they do not exist.';

COMMIT;