-- =============================================================================
-- SQL Tests for Identity Validation and Reconciliation Functions
--
-- Tests for:
--   - stg.fn_validate_identity_completeness()
--   - stg.fn_detect_orphaned_pitches()
--   - stg.fn_cross_validate_identities()
--   - stg.fn_reconcile_candidates()
--   - stg.fn_contextual_fingerprint_check()
--   - stg.fn_full_identity_health_report()
--   - stg.update_player_identity()
--   - util.resolve_player_id()
--   - util.resolve_team_id()
--   - util.ingest_chadwick_play()
--   - util.ingest_play_event()
--
-- Run after: sql/050_staging/001_identity_bridge.sql
--            sql/080_functions/013_identity_validation_functions.sql
--            sql/080_functions/014_identity_reconciliation_functions.sql
-- =============================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- Test 1: fn_validate_identity_completeness exists and returns correct columns
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    rec RECORD;
    col_count INT;
BEGIN
    -- Check function exists
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'stg' AND p.proname = 'fn_validate_identity_completeness'
    ) THEN
        RAISE EXCEPTION 'Function stg.fn_validate_identity_completeness does not exist';
    END IF;

    -- Check return columns
    SELECT COUNT(*) INTO col_count
    FROM pg_attribute
    WHERE attrelid = 'stg.fn_validate_identity_completeness'::regtype
    AND attnum > 0;

    -- Function should return at least these columns
    IF col_count < 12 THEN
        RAISE EXCEPTION 'fn_validate_identity_completeness missing expected columns, got %', col_count;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test 2: fn_detect_orphaned_pitches exists and returns correct columns
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'stg' AND p.proname = 'fn_detect_orphaned_pitches'
    ) THEN
        RAISE EXCEPTION 'Function stg.fn_detect_orphaned_pitches does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test 3: fn_cross_validate_identities exists
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'stg' AND p.proname = 'fn_cross_validate_identities'
    ) THEN
        RAISE EXCEPTION 'Function stg.fn_cross_validate_identities does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test 4: fn_reconcile_candidates exists
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'stg' AND p.proname = 'fn_reconcile_candidates'
    ) THEN
        RAISE EXCEPTION 'Function stg.fn_reconcile_candidates does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test 5: fn_contextual_fingerprint_check exists
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'stg' AND p.proname = 'fn_contextual_fingerprint_check'
    ) THEN
        RAISE EXCEPTION 'Function stg.fn_contextual_fingerprint_check does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test 6: fn_full_identity_health_report exists and returns JSONB
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    result JSONB;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'stg' AND p.proname = 'fn_full_identity_health_report'
    ) THEN
        RAISE EXCEPTION 'Function stg.fn_full_identity_health_report does not exist';
    END IF;

    -- Test that it returns valid JSONB
    SELECT stg.fn_full_identity_health_report() INTO result;

    IF result IS NULL THEN
        RAISE EXCEPTION 'fn_full_identity_health_report returned NULL';
    END IF;

    -- Check required keys exist
    IF NOT (result ? 'report_generated_at') THEN
        RAISE EXCEPTION 'fn_full_identity_health_report missing report_generated_at key';
    END IF;

    IF NOT (result ? 'critical_alert') THEN
        RAISE EXCEPTION 'fn_full_identity_health_report missing critical_alert key';
    END IF;

    IF NOT (result ? 'id_completeness') THEN
        RAISE EXCEPTION 'fn_full_identity_health_report missing id_completeness key';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test 7: stg.update_player_identity procedure exists
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'stg' AND p.proname = 'update_player_identity'
    ) THEN
        RAISE EXCEPTION 'Procedure stg.update_player_identity does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test 8: util.resolve_player_id function exists
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'resolve_player_id'
    ) THEN
        RAISE EXCEPTION 'Function util.resolve_player_id does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test 9: util.resolve_team_id function exists
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'resolve_team_id'
    ) THEN
        RAISE EXCEPTION 'Function util.resolve_team_id does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test 10: util.ingest_chadwick_play function exists
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'ingest_chadwick_play'
    ) THEN
        RAISE EXCEPTION 'Function util.ingest_chadwick_play does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test 11: util.ingest_play_event function exists
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'ingest_play_event'
    ) THEN
        RAISE EXCEPTION 'Function util.ingest_play_event does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test 12: stg.chadwick_register_snapshot table exists with correct columns
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    col_count INT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_class
        WHERE relname = 'chadwick_register_snapshot' AND relnamespace = 'stg'::regnamespace
    ) THEN
        RAISE EXCEPTION 'Table stg.chadwick_register_snapshot does not exist';
    END IF;

    -- Check key columns exist
    SELECT COUNT(*) INTO col_count
    FROM pg_attribute
    WHERE attrelid = 'stg.chadwick_register_snapshot'::regclass
    AND attname IN ('key_mlbam', 'key_retro', 'key_bbref', 'key_fangraphs', 'key_lahman');

    IF col_count < 5 THEN
        RAISE EXCEPTION 'chadwick_register_snapshot missing key columns, found %', col_count;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test 13: stg.player_identity_update_log table exists
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_class
        WHERE relname = 'player_identity_update_log' AND relnamespace = 'stg'::regnamespace
    ) THEN
        RAISE EXCEPTION 'Table stg.player_identity_update_log does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test 14: stg.retrosheet_lineup_snapshot table exists
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_class
        WHERE relname = 'retrosheet_lineup_snapshot' AND relnamespace = 'stg'::regnamespace
    ) THEN
        RAISE EXCEPTION 'Table stg.retrosheet_lineup_snapshot does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test 15: v_candidates_pending_human_review view exists
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_class
        WHERE relname = 'v_candidates_pending_human_review' AND relnamespace = 'stg'::regnamespace
    ) THEN
        RAISE EXCEPTION 'View stg.v_candidates_pending_human_review does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test 16: resolve_player_id creates placeholder when no identity exists
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_player_id BIGINT;
    v_identity_count INT;
BEGIN
    -- Call resolve_player_id with a non-existent MLBAM ID
    SELECT util.resolve_player_id(999999999, 'Test Player') INTO v_player_id;

    -- Should return a valid player_id
    IF v_player_id IS NULL THEN
        RAISE EXCEPTION 'resolve_player_id returned NULL for new player';
    END IF;

    -- Should have created a player_identity row
    SELECT COUNT(*) INTO v_identity_count
    FROM stg.player_identity
    WHERE mlbam_player_id = 999999999;

    IF v_identity_count = 0 THEN
        RAISE EXCEPTION 'resolve_player_id did not create player_identity row';
    END IF;

    -- Cleanup - remove test data
    DELETE FROM core.player WHERE player_id = v_player_id;
    DELETE FROM stg.player_identity WHERE mlbam_player_id = 999999999;
END $$;

-- ---------------------------------------------------------------------------
-- Test 17: update_player_identity writes to audit log
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_identity_id BIGINT;
    v_log_count INT;
BEGIN
    -- Create a test player_identity
    INSERT INTO stg.player_identity (
        mlbam_player_id, full_name, identity_confidence_score, identity_source
    ) VALUES (
        888888888, 'Audit Test Player', 0.5, 'test'
    )
    RETURNING player_identity_id INTO v_identity_id;

    -- Call update_player_identity
    CALL stg.update_player_identity(
        p_player_identity_id := v_identity_id,
        p_retrosheet_id := 'audit01',
        p_confidence := 0.75,
        p_change_source := 'test:audit_check',
        p_note := 'Test audit entry'
    );

    -- Check audit log was written
    SELECT COUNT(*) INTO v_log_count
    FROM stg.player_identity_update_log
    WHERE player_identity_id = v_identity_id
    AND change_source = 'test:audit_check';

    IF v_log_count = 0 THEN
        RAISE EXCEPTION 'update_player_identity did not write to audit log';
    END IF;

    -- Cleanup
    DELETE FROM stg.player_identity_update_log WHERE player_identity_id = v_identity_id;
    DELETE FROM stg.player_identity WHERE mlbam_player_id = 888888888;
END $$;

-- ---------------------------------------------------------------------------
-- Test 18: fn_validate_identity_completeness returns correct action for placeholder
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    rec RECORD;
BEGIN
    -- Create a placeholder player (confidence = 0)
    INSERT INTO stg.player_identity (
        mlbam_player_id, full_name, identity_confidence_score, identity_source
    ) VALUES (
        777777777, 'Placeholder Player', 0.0, 'auto:statcast'
    );

    -- Query the validation function
    FOR rec IN
        SELECT * FROM stg.fn_validate_identity_completeness(0.0, 1000)
        WHERE mlbam_player_id = 777777777
    LOOP
        -- Should recommend enrichment for placeholder
        IF rec.recommended_action NOT LIKE '%AUTO_PLACEHOLDER%' THEN
            RAISE EXCEPTION 'Expected AUTO_PLACEHOLDER action, got %', rec.recommended_action;
        END IF;
    END LOOP;

    -- Cleanup
    DELETE FROM stg.player_identity WHERE mlbam_player_id = 777777777;
END $$;

-- ---------------------------------------------------------------------------
-- Test 19: fn_validate_identity_completeness returns OK for complete identity
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    rec RECORD;
BEGIN
    -- Create a fully populated player identity
    INSERT INTO stg.player_identity (
        mlbam_player_id, full_name, identity_confidence_score, identity_source,
        retrosheet_player_id, bbref_player_id, fangraphs_player_id, lahman_player_id
    ) VALUES (
        666666666, 'Complete Player', 1.0, 'chadwick:seed',
        'complt01', 'complt01', '12345', 'complt01'
    );

    -- Query the validation function
    FOR rec IN
        SELECT * FROM stg.fn_validate_identity_completeness(0.0, 1000)
        WHERE mlbam_player_id = 666666666
    LOOP
        -- Should return OK for complete identity
        IF rec.recommended_action != 'OK' THEN
            RAISE EXCEPTION 'Expected OK action for complete identity, got %', rec.recommended_action;
        END IF;
    END LOOP;

    -- Cleanup
    DELETE FROM stg.player_identity WHERE mlbam_player_id = 666666666;
END $$;

-- ---------------------------------------------------------------------------
-- Test 20: resolve_team_id creates placeholder when no team exists
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_team_id BIGINT;
    v_identity_count INT;
BEGIN
    -- Call resolve_team_id with a non-existent MLBAM team ID
    SELECT util.resolve_team_id(99999, 'Test Team') INTO v_team_id;

    -- Should return a valid team_id
    IF v_team_id IS NULL THEN
        RAISE EXCEPTION 'resolve_team_id returned NULL for new team';
    END IF;

    -- Should have created a team_identity row
    SELECT COUNT(*) INTO v_identity_count
    FROM stg.team_identity
    WHERE mlbam_team_id = 99999;

    IF v_identity_count = 0 THEN
        RAISE EXCEPTION 'resolve_team_id did not create team_identity row';
    END IF;

    -- Cleanup
    DELETE FROM core.team WHERE team_id = v_team_id;
    DELETE FROM stg.team_identity WHERE mlbam_team_id = 99999;
END $$;

SELECT 'identity validation tests passed' AS result;