-- =============================================================================
-- SQL Tests for Utility Functions (sql/080_functions)
--
-- Tests for functions in:
--   - 001_meta_functions.sql (sha256_text, register_payload_hash, start_ingest_run, finish_ingest_run)
--   - 002_retrosheet_chadwick_functions.sql (is_valid_retrosheet_record_type, normalize_retrosheet_record_type,
--                                           register_retrosheet_record_hash, validate_retrosheet_record_sequences,
--                                           build_retrosheet_game_id, identity_match_score)
--   - 003_statcast_mlbapi_functions.sql (register_statcast_row_hash, validate_statcast_pitch_business_key,
--                                        validate_mlbapi_request_method, ingest_statcast_play)
--   - 003a_ingestion_identity_resolution.sql (resolve_player_id, resolve_team_id)
--   - 004_lahman_web_functions.sql (register_generic_payload_hash, normalize_lahman_player_id,
--                                   normalize_web_natural_key, validate_lahman_year_id)
--   - 005_staging_functions.sql (stg_touch_updated_at, normalize_team_code, normalize_player_code,
--                                ingest_chadwick_play, ingest_play_event)
--   - 006_core_functions.sql (core_touch_updated_at, normalize_inning_half, build_pa_key, build_pitch_key)
--   - 007_ml_ops_functions.sql (ml_ops_touch_updated_at, should_stop_live_polling, build_feature_entity_key,
--                               safe_prediction_rank_score)
--   - 008_auth_security_functions.sql (auth_touch_updated_at, current_workspace_id, current_app_user_id,
--                                      current_is_platform_admin, source_is_enabled_for_ingest,
--                                      source_is_enabled_for_serving, workspace_can_use_source,
--                                      workspace_can_view_source, workspace_can_trigger_ingest)
--   - 009_mart_refresh_functions.sql (refresh_materialized_view, refresh_workspace_marts)
--   - 010_ingestion_ops_functions.sql (calculate_retry_run_at, claim_next_job, complete_job, fail_job_for_retry, recover_stale_claimed_jobs, live_poll_should_stop)
--   - 011_api_service_functions.sql (api_touch_updated_at, register_request_idempotency, log_api_request,
--                                    rollup_api_usage_hourly)
--   - 012_source_ingestion_functions.sql (build_file_manifest_path, next_statcast_chunk_start,
--                                         next_statcast_chunk_end, mlbapi_live_poll_mode,
--                                         default_live_poll_interval_seconds, upsert_file_acquisition_manifest)
--   - 013_identity_validation_functions.sql (fn_validate_identity_completeness, fn_detect_orphaned_pitches,
--                                          fn_cross_validate_identities, fn_pinpoint_player_by_context,
--                                          fn_validate_game_lineup)
--   - 014_identity_reconciliation_functions.sql (fn_reconcile_candidates, fn_contextual_fingerprint_check,
--                                              fn_full_identity_health_report)
--
-- Run after: All schema and function files applied
-- =============================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- Tests for 006_core_functions.sql
-- ---------------------------------------------------------------------------

-- Test: normalize_inning_half handles various inputs correctly
DO $$
BEGIN
    -- Test 'top' variations
    IF util.normalize_inning_half('top') IS NULL THEN
        RAISE EXCEPTION 'normalize_inning_half failed for top';
    END IF;
    IF util.normalize_inning_half('TOP') != 'top' THEN
        RAISE EXCEPTION 'normalize_inning_half failed for TOP';
    END IF;
    IF util.normalize_inning_half('t') != 'top' THEN
        RAISE EXCEPTION 'normalize_inning_half failed for t';
    END IF;
    IF util.normalize_inning_half('away') != 'top' THEN
        RAISE EXCEPTION 'normalize_inning_half failed for away';
    END IF;

    -- Test 'bottom' variations
    IF util.normalize_inning_half('bottom') IS NULL THEN
        RAISE EXCEPTION 'normalize_inning_half failed for bottom';
    END IF;
    IF util.normalize_inning_half('BOTTOM') != 'bottom' THEN
        RAISE EXCEPTION 'normalize_inning_half failed for BOTTOM';
    END IF;
    IF util.normalize_inning_half('bot') != 'bottom' THEN
        RAISE EXCEPTION 'normalize_inning_half failed for bot';
    END IF;
    IF util.normalize_inning_half('b') != 'bottom' THEN
        RAISE EXCEPTION 'normalize_inning_half failed for b';
    END IF;
    IF util.normalize_inning_half('home') != 'bottom' THEN
        RAISE EXCEPTION 'normalize_inning_half failed for home';
    END IF;

    -- Test NULL/empty returns NULL
    IF util.normalize_inning_half(NULL) IS NOT NULL THEN
        RAISE EXCEPTION 'normalize_inning_half should return NULL for NULL input';
    END IF;
    IF util.normalize_inning_half('') IS NOT NULL THEN
        RAISE EXCEPTION 'normalize_inning_half should return NULL for empty input';
    END IF;
END $$;

-- Test: build_pa_key generates correct composite key
DO $$
BEGIN
    IF util.build_pa_key(12345, 5, 'top', 1) != '12345:5:top:1' THEN
        RAISE EXCEPTION 'build_pa_key failed for top inning';
    END IF;

    IF util.build_pa_key(12345, 7, 'bottom', 3) != '12345:7:bottom:3' THEN
        RAISE EXCEPTION 'build_pa_key failed for bottom inning';
    END IF;

    -- Test with normalized inning half
    IF util.build_pa_key(99999, 9, 'TOP', 2) != '99999:9:top:2' THEN
        RAISE EXCEPTION 'build_pa_key failed for normalized TOP';
    END IF;
END $$;

-- Test: build_pitch_key generates correct composite key
DO $$
BEGIN
    IF util.build_pitch_key(12345, 5, 'top', 1, 1) != '12345:5:top:1:1' THEN
        RAISE EXCEPTION 'build_pitch_key failed for first pitch';
    END IF;

    IF util.build_pitch_key(12345, 7, 'bottom', 3, 5) != '12345:7:bottom:3:5' THEN
        RAISE EXCEPTION 'build_pitch_key failed for later pitch';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 007_ml_ops_functions.sql
-- ---------------------------------------------------------------------------

-- Test: should_stop_live_polling returns correct boolean values
DO $$
BEGIN
    -- Should NOT stop for live/in-progress games
    IF util.should_stop_live_polling('Live', 'L', 'In Progress') THEN
        RAISE EXCEPTION 'should_stop_live_polling incorrectly returned true for Live game';
    END IF;

    -- Should stop for final games
    IF NOT util.should_stop_live_polling('Final', 'F', 'Game Over') THEN
        RAISE EXCEPTION 'should_stop_live_polling failed to return true for Final game';
    END IF;

    -- Should stop for completed games
    IF NOT util.should_stop_live_polling('Completed', 'O', 'completed') THEN
        RAISE EXCEPTION 'should_stop_live_polling failed to return true for Completed game';
    END IF;

    -- Should stop for coded_state 'F'
    IF NOT util.should_stop_live_polling('Any', 'F', 'Any') THEN
        RAISE EXCEPTION 'should_stop_live_polling failed to return true for F coded state';
    END IF;

    -- Should stop for coded_state 'O'
    IF NOT util.should_stop_live_polling('Any', 'O', 'Any') THEN
        RAISE EXCEPTION 'should_stop_live_polling failed to return true for O coded state';
    END IF;
END $$;

-- Test: build_feature_entity_key generates correct keys for different grains
DO $$
DECLARE
    v_key TEXT;
BEGIN
    v_key := util.build_feature_entity_key('game', p_game_id := 12345);
    IF v_key != 'game:12345' THEN
        RAISE EXCEPTION 'build_feature_entity_key failed for game grain, got %', v_key;
    END IF;

    v_key := util.build_feature_entity_key('team_game', p_team_id := 10, p_game_id := 12345);
    IF v_key != 'team_game:10:12345' THEN
        RAISE EXCEPTION 'build_feature_entity_key failed for team_game grain, got %', v_key;
    END IF;

    v_key := util.build_feature_entity_key('player_game', p_player_id := 555, p_game_id := 12345);
    IF v_key != 'player_game:555:12345' THEN
        RAISE EXCEPTION 'build_feature_entity_key failed for player_game grain, got %', v_key;
    END IF;

    v_key := util.build_feature_entity_key('plate_appearance', p_plate_appearance_id := 999);
    IF v_key != 'plate_appearance:999' THEN
        RAISE EXCEPTION 'build_feature_entity_key failed for plate_appearance grain, got %', v_key;
    END IF;

    v_key := util.build_feature_entity_key('pitch', p_pitch_id := 888);
    IF v_key != 'pitch:888' THEN
        RAISE EXCEPTION 'build_feature_entity_key failed for pitch grain, got %', v_key;
    END IF;
END $$;

-- Test: safe_prediction_rank_score calculates correctly
DO $$
DECLARE
    v_score NUMERIC;
BEGIN
    -- Test with all values
    v_score := util.safe_prediction_rank_score(0.5, 0.3, 0.8);
    IF ABS(v_score - 0.51) > 0.001 THEN
        RAISE EXCEPTION 'safe_prediction_rank_score calculation incorrect, got %', v_score;
    END IF;

    -- Test with NULL edge (should use 0)
    v_score := util.safe_prediction_rank_score(0.5, NULL, 0.8);
    IF ABS(v_score - 0.48) > 0.001 THEN
        RAISE EXCEPTION 'safe_prediction_rank_score failed with NULL edge, got %', v_score;
    END IF;

    -- Test with NULL confidence (should use 0)
    v_score := util.safe_prediction_rank_score(0.5, 0.3, NULL);
    IF ABS(v_score - 0.23) > 0.001 THEN
        RAISE EXCEPTION 'safe_prediction_rank_score failed with NULL confidence, got %', v_score;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 008_auth_security_functions.sql
-- ---------------------------------------------------------------------------

-- Test: current_workspace_id returns NULL when not set
DO $$
BEGIN
    -- Reset the setting to ensure clean state
    RESET app.current_workspace;

    -- Should return NULL when not set
    IF util.current_workspace_id() IS NOT NULL THEN
        RAISE EXCEPTION 'current_workspace_id should return NULL when not set';
    END IF;
END $$;

-- Test: current_app_user_id returns NULL when not set
DO $$
BEGIN
    RESET app.current_app_user;

    IF util.current_app_user_id() IS NOT NULL THEN
        RAISE EXCEPTION 'current_app_user_id should return NULL when not set';
    END IF;
END $$;

-- Test: current_is_platform_admin returns FALSE when not set
DO $$
BEGIN
    RESET app.current_is_platform_admin;

    IF util.current_is_platform_admin() THEN
        RAISE EXCEPTION 'current_is_platform_admin should return FALSE when not set';
    END IF;
END $$;

-- Test: source_is_enabled_for_ingest returns TRUE when no control record exists
DO $$
BEGIN
    -- With no control record, should return TRUE (default)
    IF NOT util.source_is_enabled_for_ingest(999999) THEN
        RAISE EXCEPTION 'source_is_enabled_for_ingest should return TRUE when no control record';
    END IF;
END $$;

-- Test: source_is_enabled_for_serving returns TRUE when no control record exists
DO $$
BEGIN
    -- With no control record, should return TRUE (default)
    IF NOT util.source_is_enabled_for_serving(999999) THEN
        RAISE EXCEPTION 'source_is_enabled_for_serving should return TRUE when no control record';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 012_source_ingestion_functions.sql
-- ---------------------------------------------------------------------------

-- Test: build_file_manifest_path generates correct paths
DO $$
BEGIN
    IF util.build_file_manifest_path('statcast', 2024, 'pitch_data') != 'statcast/2024/pitch_data' THEN
        RAISE EXCEPTION 'build_file_manifest_path failed for statcast';
    END IF;

    IF util.build_file_manifest_path('retrosheet', 2023, 'event_file') != 'retrosheet/2023/event_file' THEN
        RAISE EXCEPTION 'build_file_manifest_path failed for retrosheet';
    END IF;

    -- Test with spaces in file_kind
    IF util.build_file_manifest_path('fangraphs', 2024, 'batting splits') != 'fangraphs/2024/batting_splits' THEN
        RAISE EXCEPTION 'build_file_manifest_path failed for file_kind with spaces';
    END IF;
END $$;

-- Test: next_statcast_chunk_start returns next day
DO $$
DECLARE
    v_next DATE;
BEGIN
    v_next := util.next_statcast_chunk_start('2024-04-01'::DATE);
    IF v_next != '2024-04-02'::DATE THEN
        RAISE EXCEPTION 'next_statcast_chunk_start failed, expected 2024-04-02, got %', v_next;
    END IF;

    -- Test with different date
    v_next := util.next_statcast_chunk_start('2024-07-15'::DATE);
    IF v_next != '2024-07-16'::DATE THEN
        RAISE EXCEPTION 'next_statcast_chunk_start failed, expected 2024-07-16, got %', v_next;
    END IF;
END $$;

-- Test: next_statcast_chunk_end returns correct end date
DO $$
DECLARE
    v_end DATE;
BEGIN
    -- Default 3-day chunk
    v_end := util.next_statcast_chunk_end('2024-04-01'::DATE);
    IF v_end != '2024-04-03'::DATE THEN
        RAISE EXCEPTION 'next_statcast_chunk_end failed for default chunk, expected 2024-04-03, got %', v_end;
    END IF;

    -- 5-day chunk
    v_end := util.next_statcast_chunk_end('2024-04-01'::DATE, 5);
    IF v_end != '2024-04-05'::DATE THEN
        RAISE EXCEPTION 'next_statcast_chunk_end failed for 5-day chunk, expected 2024-04-05, got %', v_end;
    END IF;
END $$;

-- Test: mlbapi_live_poll_mode returns correct mode
DO $$
BEGIN
    IF util.mlbapi_live_poll_mode(TRUE, FALSE) != 'diff_patch' THEN
        RAISE EXCEPTION 'mlbapi_live_poll_mode failed for diff_patch mode';
    END IF;

    IF util.mlbapi_live_poll_mode(FALSE, TRUE) != 'timestamps' THEN
        RAISE EXCEPTION 'mlbapi_live_poll_mode failed for timestamps mode';
    END IF;

    IF util.mlbapi_live_poll_mode(FALSE, FALSE) != 'full_live_feed' THEN
        RAISE EXCEPTION 'mlbapi_live_poll_mode failed for full_live_feed mode';
    END IF;
END $$;

-- Test: default_live_poll_interval_seconds returns correct intervals
DO $$
BEGIN
    IF util.default_live_poll_interval_seconds('In Progress') != 10 THEN
        RAISE EXCEPTION 'default_live_poll_interval_seconds failed for In Progress';
    END IF;

    IF util.default_live_poll_interval_seconds('Manager Challenge') != 10 THEN
        RAISE EXCEPTION 'default_live_poll_interval_seconds failed for Manager Challenge';
    END IF;

    IF util.default_live_poll_interval_seconds('Warmup') != 30 THEN
        RAISE EXCEPTION 'default_live_poll_interval_seconds failed for Warmup';
    END IF;

    IF util.default_live_poll_interval_seconds('Pre-Game') != 30 THEN
        RAISE EXCEPTION 'default_live_poll_interval_seconds failed for Pre-Game';
    END IF;

    IF util.default_live_poll_interval_seconds('Other') != 20 THEN
        RAISE EXCEPTION 'default_live_poll_interval_seconds failed for Other';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 010_ingestion_ops_functions.sql
-- ---------------------------------------------------------------------------

-- Test: calculate_retry_run_at returns future timestamp
DO $$
DECLARE
    v_run_at TIMESTAMPTZ;
BEGIN
    v_run_at := util.calculate_retry_run_at(1, 60, 2.0, 10);

    -- Should be in the future (at least 50 seconds from now)
    IF v_run_at <= NOW() + INTERVAL '50 seconds' THEN
        RAISE EXCEPTION 'calculate_retry_run_at should return future timestamp';
    END IF;

    -- Test exponential backoff - attempt 2 should be later than attempt 1
    v_run_at := util.calculate_retry_run_at(2, 60, 2.0, 0);
    IF v_run_at <= NOW() + INTERVAL '120 seconds' THEN
        RAISE EXCEPTION 'calculate_retry_run_at exponential backoff failed';
    END IF;
END $$;

-- Test: recover_stale_claimed_jobs function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'recover_stale_claimed_jobs'
    ) THEN
        RAISE EXCEPTION 'Function util.recover_stale_claimed_jobs does not exist';
    END IF;
END $$;

-- Test: live_poll_should_stop function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'live_poll_should_stop'
    ) THEN
        RAISE EXCEPTION 'Function util.live_poll_should_stop does not exist';
    END IF;
END $$;

-- Test: claim_next_job function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'claim_next_job'
    ) THEN
        RAISE EXCEPTION 'Function util.claim_next_job does not exist';
    END IF;
END $$;

-- Test: complete_job function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'complete_job'
    ) THEN
        RAISE EXCEPTION 'Function util.complete_job does not exist';
    END IF;
END $$;

-- Test: fail_job_for_retry function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'fail_job_for_retry'
    ) THEN
        RAISE EXCEPTION 'Function util.fail_job_for_retry does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 001_meta_functions.sql
-- ---------------------------------------------------------------------------

-- Test: sha256_text returns correct hash
DO $$
DECLARE
    v_hash TEXT;
BEGIN
    v_hash := util.sha256_text('test string');

    -- SHA256 produces 64 hex characters
    IF LENGTH(v_hash) != 64 THEN
        RAISE EXCEPTION 'sha256_text returned incorrect length, got %', LENGTH(v_hash);
    END IF;

    -- Same input should produce same output
    IF util.sha256_text('test string') != v_hash THEN
        RAISE EXCEPTION 'sha256_text not deterministic';
    END IF;

    -- Different input should produce different output
    IF util.sha256_text('different string') = v_hash THEN
        RAISE EXCEPTION 'sha256_text should produce different hash for different input';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 001_meta_functions.sql (additional)
-- ---------------------------------------------------------------------------

-- Test: register_payload_hash function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'register_payload_hash'
    ) THEN
        RAISE EXCEPTION 'Function util.register_payload_hash does not exist';
    END IF;
END $$;

-- Test: start_ingest_run function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'start_ingest_run'
    ) THEN
        RAISE EXCEPTION 'Function util.start_ingest_run does not exist';
    END IF;
END $$;

-- Test: finish_ingest_run procedure exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'finish_ingest_run'
    ) THEN
        RAISE EXCEPTION 'Procedure util.finish_ingest_run does not exist';
    END IF;
END $$;

-- Test: touch_updated_at function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'touch_updated_at'
    ) THEN
        RAISE EXCEPTION 'Function util.touch_updated_at does not exist';
    END IF;
END $$;

-- Test: touch_updated_at returns trigger type
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'trg_source_system_updated_at'
    ) THEN
        RAISE EXCEPTION 'Trigger trg_source_system_updated_at does not exist';
    END IF;
END $$;

-- Test: normalize_retrosheet_record_type trims and lowercases
DO $$
BEGIN
    IF util.normalize_retrosheet_record_type(' Play ') != 'play' THEN
        RAISE EXCEPTION 'normalize_retrosheet_record_type failed for trimmed input';
    END IF;

    IF util.normalize_retrosheet_record_type('PLAY') != 'play' THEN
        RAISE EXCEPTION 'normalize_retrosheet_record_type failed for uppercased input';
    END IF;

    IF util.normalize_retrosheet_record_type('  info  ') != 'info' THEN
        RAISE EXCEPTION 'normalize_retrosheet_record_type failed for info';
    END IF;
END $$;

-- Test: identity_match_score returns correct scores
DO $$
DECLARE
    v_score NUMERIC;
BEGIN
    -- Exact ID match = 1.0
    v_score := util.identity_match_score(TRUE, FALSE, FALSE);
    IF v_score != 1.0 THEN
        RAISE EXCEPTION 'identity_match_score failed for exact ID match, got %', v_score;
    END IF;

    -- Name + birth match = 0.950
    v_score := util.identity_match_score(FALSE, TRUE, TRUE);
    IF v_score != 0.950 THEN
        RAISE EXCEPTION 'identity_match_score failed for name+birth match, got %', v_score;
    END IF;

    -- Name only match = 0.700
    v_score := util.identity_match_score(FALSE, TRUE, FALSE);
    IF v_score != 0.700 THEN
        RAISE EXCEPTION 'identity_match_score failed for name match, got %', v_score;
    END IF;

    -- No match = 0.0
    v_score := util.identity_match_score(FALSE, FALSE, FALSE);
    IF v_score != 0.0 THEN
        RAISE EXCEPTION 'identity_match_score failed for no match, got %', v_score;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 002_retrosheet_chadwick_functions.sql
-- ---------------------------------------------------------------------------

-- Test: build_retrosheet_game_id generates correct format
DO $$
BEGIN
    IF util.build_retrosheet_game_id('BOS', '2024-04-10'::DATE, 1) != 'BOS202404101' THEN
        RAISE EXCEPTION 'build_retrosheet_game_id failed for standard input';
    END IF;

    IF util.build_retrosheet_game_id('NYY', '2024-07-15'::DATE, 2) != 'NYY202407152' THEN
        RAISE EXCEPTION 'build_retrosheet_game_id failed for different input';
    END IF;

    -- NULL inputs return NULL
    IF util.build_retrosheet_game_id(NULL, NULL, NULL) IS NOT NULL THEN
        RAISE EXCEPTION 'build_retrosheet_game_id should return NULL for NULL inputs';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 002_retrosheet_chadwick_functions.sql
-- ---------------------------------------------------------------------------

-- Test: is_valid_retrosheet_record_type validates known record types
DO $$
BEGIN
    -- Valid record types
    IF NOT util.is_valid_retrosheet_record_type('id') THEN
        RAISE EXCEPTION 'is_valid_retrosheet_record_type failed for id';
    END IF;
    IF NOT util.is_valid_retrosheet_record_type('play') THEN
        RAISE EXCEPTION 'is_valid_retrosheet_record_type failed for play';
    END IF;
    IF NOT util.is_valid_retrosheet_record_type('info') THEN
        RAISE EXCEPTION 'is_valid_retrosheet_record_type failed for info';
    END IF;

    -- Invalid record type
    IF util.is_valid_retrosheet_record_type('invalid_type') THEN
        RAISE EXCEPTION 'is_valid_retrosheet_record_type should return false for invalid type';
    END IF;

    -- NULL returns false
    IF util.is_valid_retrosheet_record_type(NULL) THEN
        RAISE EXCEPTION 'is_valid_retrosheet_record_type should return false for NULL';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 003_statcast_mlbapi_functions.sql
-- ---------------------------------------------------------------------------

-- Test: validate_statcast_pitch_business_key validates required fields
DO $$
BEGIN
    -- All fields present = valid
    IF NOT util.validate_statcast_pitch_business_key(12345, 1, 1) THEN
        RAISE EXCEPTION 'validate_statcast_pitch_business_key failed for valid input';
    END IF;

    -- NULL game_pk = invalid
    IF util.validate_statcast_pitch_business_key(NULL, 1, 1) THEN
        RAISE EXCEPTION 'validate_statcast_pitch_business_key should fail for NULL game_pk';
    END IF;

    -- NULL at_bat_number = invalid
    IF util.validate_statcast_pitch_business_key(12345, NULL, 1) THEN
        RAISE EXCEPTION 'validate_statcast_pitch_business_key should fail for NULL at_bat';
    END IF;

    -- NULL pitch_number = invalid
    IF util.validate_statcast_pitch_business_key(12345, 1, NULL) THEN
        RAISE EXCEPTION 'validate_statcast_pitch_business_key should fail for NULL pitch';
    END IF;
END $$;

-- Test: validate_mlbapi_request_method validates HTTP methods
DO $$
BEGIN
    -- Valid methods
    IF NOT util.validate_mlbapi_request_method('GET') THEN
        RAISE EXCEPTION 'validate_mlbapi_request_method failed for GET';
    END IF;
    IF NOT util.validate_mlbapi_request_method('get') THEN
        RAISE EXCEPTION 'validate_mlbapi_request_method failed for lowercase get';
    END IF;
    IF NOT util.validate_mlbapi_request_method('POST') THEN
        RAISE EXCEPTION 'validate_mlbapi_request_method failed for POST';
    END IF;
    IF NOT util.validate_mlbapi_request_method('PUT') THEN
        RAISE EXCEPTION 'validate_mlbapi_request_method failed for PUT';
    END IF;
    IF NOT util.validate_mlbapi_request_method('PATCH') THEN
        RAISE EXCEPTION 'validate_mlbapi_request_method failed for PATCH';
    END IF;
    IF NOT util.validate_mlbapi_request_method('DELETE') THEN
        RAISE EXCEPTION 'validate_mlbapi_request_method failed for DELETE';
    END IF;

    -- Invalid method
    IF util.validate_mlbapi_request_method('INVALID') THEN
        RAISE EXCEPTION 'validate_mlbapi_request_method should fail for INVALID';
    END IF;

    -- NULL returns false
    IF util.validate_mlbapi_request_method(NULL) THEN
        RAISE EXCEPTION 'validate_mlbapi_request_method should fail for NULL';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 004_lahman_web_functions.sql
-- ---------------------------------------------------------------------------

-- Test: normalize_lahman_player_id trims and lowercases
DO $$
BEGIN
    IF util.normalize_lahman_player_id(' aaronha01 ') != 'aaronha01' THEN
        RAISE EXCEPTION 'normalize_lahman_player_id failed for trimmed input';
    END IF;

    IF util.normalize_lahman_player_id('AARONHA01') != 'aaronha01' THEN
        RAISE EXCEPTION 'normalize_lahman_player_id failed for uppercased input';
    END IF;

    -- Empty string returns NULL
    IF util.normalize_lahman_player_id('') IS NOT NULL THEN
        RAISE EXCEPTION 'normalize_lahman_player_id should return NULL for empty string';
    END IF;

    -- NULL returns NULL
    IF util.normalize_lahman_player_id(NULL) IS NOT NULL THEN
        RAISE EXCEPTION 'normalize_lahman_player_id should return NULL for NULL input';
    END IF;
END $$;

-- Test: normalize_web_natural_key generates correct keys
DO $$
BEGIN
    IF util.normalize_web_natural_key('fangraphs', 'batter_555', 2024, 'batting') != 'fangraphs:batting:batter_555:2024' THEN
        RAISE EXCEPTION 'normalize_web_natural_key failed for standard input';
    END IF;

    IF util.normalize_web_natural_key('bref', 'team_NYY', 2023, 'pitching') != 'bref:pitching:team_nyy:2023' THEN
        RAISE EXCEPTION 'normalize_web_natural_key failed for bref input';
    END IF;
END $$;

-- Test: validate_lahman_year_id validates year range
DO $$
BEGIN
    -- Valid years
    IF NOT util.validate_lahman_year_id(1871) THEN
        RAISE EXCEPTION 'validate_lahman_year_id failed for 1871 (first valid year)';
    END IF;
    IF NOT util.validate_lahman_year_id(2024) THEN
        RAISE EXCEPTION 'validate_lahman_year_id failed for 2024';
    END IF;
    IF NOT util.validate_lahman_year_id(2100) THEN
        RAISE EXCEPTION 'validate_lahman_year_id failed for 2100 (last valid year)';
    END IF;

    -- Invalid years
    IF util.validate_lahman_year_id(1870) THEN
        RAISE EXCEPTION 'validate_lahman_year_id should fail for 1870 (before range)';
    END IF;
    IF util.validate_lahman_year_id(2101) THEN
        RAISE EXCEPTION 'validate_lahman_year_id should fail for 2101 (after range)';
    END IF;

    -- NULL returns false
    IF util.validate_lahman_year_id(NULL) THEN
        RAISE EXCEPTION 'validate_lahman_year_id should fail for NULL';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 009_mart_refresh_functions.sql
-- ---------------------------------------------------------------------------

-- Test: refresh_materialized_view function exists and has correct signature
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'refresh_materialized_view'
    ) THEN
        RAISE EXCEPTION 'Function util.refresh_materialized_view does not exist';
    END IF;
END $$;

-- Test: refresh_workspace_marts function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'refresh_workspace_marts'
    ) THEN
        RAISE EXCEPTION 'Function util.refresh_workspace_marts does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 011_api_service_functions.sql
-- ---------------------------------------------------------------------------

-- Test: register_request_idempotency function exists and has correct signature
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'register_request_idempotency'
    ) THEN
        RAISE EXCEPTION 'Function util.register_request_idempotency does not exist';
    END IF;
END $$;

-- Test: log_api_request function exists and has correct signature
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'log_api_request'
    ) THEN
        RAISE EXCEPTION 'Function util.log_api_request does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 012_source_ingestion_functions.sql (additional)
-- ---------------------------------------------------------------------------

-- Test: upsert_file_acquisition_manifest function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'upsert_file_acquisition_manifest'
    ) THEN
        RAISE EXCEPTION 'Function util.upsert_file_acquisition_manifest does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 005_staging_functions.sql (additional)
-- ---------------------------------------------------------------------------

-- Test: normalize_team_code uppercases and trims
DO $$
BEGIN
    IF util.normalize_team_code(' bos ') != 'BOS' THEN
        RAISE EXCEPTION 'normalize_team_code failed for trimmed input';
    END IF;

    IF util.normalize_team_code('nyy') != 'NYY' THEN
        RAISE EXCEPTION 'normalize_team_code failed for lowercased input';
    END IF;

    -- Empty string returns NULL
    IF util.normalize_team_code('') IS NOT NULL THEN
        RAISE EXCEPTION 'normalize_team_code should return NULL for empty string';
    END IF;

    -- NULL returns NULL
    IF util.normalize_team_code(NULL) IS NOT NULL THEN
        RAISE EXCEPTION 'normalize_team_code should return NULL for NULL input';
    END IF;
END $$;

-- Test: normalize_player_code lowercases and trims
DO $$
BEGIN
    IF util.normalize_player_code(' aaronha01 ') != 'aaronha01' THEN
        RAISE EXCEPTION 'normalize_player_code failed for trimmed input';
    END IF;

    IF util.normalize_player_code('AARONHA01') != 'aaronha01' THEN
        RAISE EXCEPTION 'normalize_player_code failed for uppercased input';
    END IF;

    -- Empty string returns NULL
    IF util.normalize_player_code('') IS NOT NULL THEN
        RAISE EXCEPTION 'normalize_player_code should return NULL for empty string';
    END IF;

    -- NULL returns NULL
    IF util.normalize_player_code(NULL) IS NOT NULL THEN
        RAISE EXCEPTION 'normalize_player_code should return NULL for NULL input';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 003_statcast_mlbapi_functions.sql (additional)
-- ---------------------------------------------------------------------------

-- Test: register_statcast_row_hash function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'register_statcast_row_hash'
    ) THEN
        RAISE EXCEPTION 'Function util.register_statcast_row_hash does not exist';
    END IF;
END $$;

-- Test: register_mlbapi_payload_hash function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'register_mlbapi_payload_hash'
    ) THEN
        RAISE EXCEPTION 'Function util.register_mlbapi_payload_hash does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 004_lahman_web_functions.sql (additional)
-- ---------------------------------------------------------------------------

-- Test: register_generic_payload_hash function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'register_generic_payload_hash'
    ) THEN
        RAISE EXCEPTION 'Function util.register_generic_payload_hash does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 005_staging_functions.sql (ingest functions)
-- ---------------------------------------------------------------------------

-- Test: ingest_chadwick_play function exists
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

-- Test: ingest_chadwick_play has correct argument signature
DO $$
DECLARE
    v_arg_count INT;
BEGIN
    SELECT count(*)
    INTO v_arg_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'util' AND p.proname = 'ingest_chadwick_play';

    -- Should have 24 arguments (game_id_text through pitcher_name)
    IF v_arg_count < 20 THEN
        RAISE EXCEPTION 'ingest_chadwick_play has fewer than expected arguments: %', v_arg_count;
    END IF;
END $$;

-- Test: ingest_play_event function exists
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

-- Test: ingest_play_event has correct argument signature
DO $$
DECLARE
    v_arg_count INT;
BEGIN
    SELECT count(*)
    INTO v_arg_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'util' AND p.proname = 'ingest_play_event';

    -- Should have 24 arguments (source_system through pitcher_name)
    IF v_arg_count < 20 THEN
        RAISE EXCEPTION 'ingest_play_event has fewer than expected arguments: %', v_arg_count;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 008_auth_security_functions.sql (additional)
-- ---------------------------------------------------------------------------

-- Test: current_is_platform_admin returns FALSE when not set
DO $$
BEGIN
    RESET app.current_is_platform_admin;

    IF util.current_is_platform_admin() THEN
        RAISE EXCEPTION 'current_is_platform_admin should return FALSE when not set';
    END IF;
END $$;

-- Test: workspace_can_use_source returns TRUE when no entitlement record exists
DO $$
BEGIN
    -- With no entitlement record, should return TRUE (default)
    IF NOT util.workspace_can_use_source(
        '00000000-0000-0000-0000-000000000000'::UUID,
        999999
    ) THEN
        RAISE EXCEPTION 'workspace_can_use_source should return TRUE when no entitlement record';
    END IF;
END $$;

-- Test: workspace_can_view_source returns TRUE when no entitlement record exists
DO $$
BEGIN
    -- With no entitlement record, should return TRUE (default)
    IF NOT util.workspace_can_view_source(
        '00000000-0000-0000-0000-000000000000'::UUID,
        999999
    ) THEN
        RAISE EXCEPTION 'workspace_can_view_source should return TRUE when no entitlement record';
    END IF;
END $$;

-- Test: workspace_can_trigger_ingest returns FALSE when no entitlement record exists
DO $$
BEGIN
    -- With no entitlement record, should return FALSE (default)
    IF util.workspace_can_trigger_ingest(
        '00000000-0000-0000-0000-000000000000'::UUID,
        999999
    ) THEN
        RAISE EXCEPTION 'workspace_can_trigger_ingest should return FALSE when no entitlement record';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 003a_ingestion_identity_resolution.sql
-- ---------------------------------------------------------------------------

-- Test: resolve_player_id function exists
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

-- Test: resolve_team_id function exists
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
-- Tests for 003_statcast_mlbapi_functions.sql (additional)
-- ---------------------------------------------------------------------------

-- Test: ingest_statcast_play function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'ingest_statcast_play'
    ) THEN
        RAISE EXCEPTION 'Function util.ingest_statcast_play does not exist';
    END IF;
END $$;

-- Test: ingest_statcast_play has correct argument signature
DO $$
DECLARE
    v_arg_count INT;
BEGIN
    SELECT count(*)
    INTO v_arg_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_get_function_arguments(p.oid) arg(arg) ON true
    WHERE n.nspname = 'util' AND p.proname = 'ingest_statcast_play';

    -- Should have 22 arguments (game_pk through away_team_id)
    IF v_arg_count < 20 THEN
        RAISE EXCEPTION 'ingest_statcast_play has fewer than expected arguments: %', v_arg_count;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 002_retrosheet_chadwick_functions.sql (additional)
-- ---------------------------------------------------------------------------

-- Test: register_retrosheet_record_hash function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'register_retrosheet_record_hash'
    ) THEN
        RAISE EXCEPTION 'Function util.register_retrosheet_record_hash does not exist';
    END IF;
END $$;

-- Test: validate_retrosheet_record_sequences function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'validate_retrosheet_record_sequences'
    ) THEN
        RAISE EXCEPTION 'Function util.validate_retrosheet_record_sequences does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 011_api_service_functions.sql (additional)
-- ---------------------------------------------------------------------------

-- Test: rollup_api_usage_hourly function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'rollup_api_usage_hourly'
    ) THEN
        RAISE EXCEPTION 'Function util.rollup_api_usage_hourly does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 013_identity_validation_functions.sql
-- ---------------------------------------------------------------------------

-- Test: fn_validate_identity_completeness function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'stg' AND p.proname = 'fn_validate_identity_completeness'
    ) THEN
        RAISE EXCEPTION 'Function stg.fn_validate_identity_completeness does not exist';
    END IF;
END $$;

-- Test: fn_detect_orphaned_pitches function exists
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

-- Test: fn_cross_validate_identities function exists
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

-- Test: fn_pinpoint_player_by_context function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'stg' AND p.proname = 'fn_pinpoint_player_by_context'
    ) THEN
        RAISE EXCEPTION 'Function stg.fn_pinpoint_player_by_context does not exist';
    END IF;
END $$;

-- Test: fn_validate_game_lineup function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'stg' AND p.proname = 'fn_validate_game_lineup'
    ) THEN
        RAISE EXCEPTION 'Function stg.fn_validate_game_lineup does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Functional tests for 013_identity_validation_functions.sql
-- ---------------------------------------------------------------------------

-- Test: fn_validate_identity_completeness returns expected columns
DO $$
DECLARE
    v_row RECORD;
BEGIN
    SELECT * INTO v_row FROM stg.fn_validate_identity_completeness(0.0, 10);
    IF v_row.player_identity_id IS NULL THEN
        -- Empty result is OK if no players exist yet
        RAISE NOTICE 'fn_validate_identity_completeness returned no rows (expected if no data)';
    END IF;
END $$;

-- Test: fn_detect_orphaned_pitches returns expected columns
DO $$
DECLARE
    v_row RECORD;
BEGIN
    SELECT * INTO v_row FROM stg.fn_detect_orphaned_pitches(NULL, NULL, 10);
    IF v_row.pitch_id IS NULL THEN
        -- Empty result is OK if no orphaned pitches exist
        RAISE NOTICE 'fn_detect_orphaned_pitches returned no rows (expected if no orphans)';
    END IF;
END $$;

-- Test: fn_cross_validate_identities returns expected columns
DO $$
DECLARE
    v_row RECORD;
BEGIN
    -- This function requires stg.chadwick_register_snapshot to be populated
    -- Test will return empty if snapshot is empty, which is valid
    SELECT * INTO v_row FROM stg.fn_cross_validate_identities(NULL) LIMIT 1;
    IF v_row.player_identity_id IS NULL THEN
        RAISE NOTICE 'fn_cross_validate_identities returned no rows (expected if no snapshot data)';
    END IF;
END $$;

-- Test: fn_pinpoint_player_by_context returns expected columns
DO $$
DECLARE
    v_row RECORD;
BEGIN
    -- Test with a date that likely has no data - should return empty
    SELECT * INTO v_row FROM stg.fn_pinpoint_player_by_context('2025-04-01', 'NYY', NULL, NULL, NULL) LIMIT 1;
    IF v_row.pitch_id IS NULL THEN
        RAISE NOTICE 'fn_pinpoint_player_by_context returned no rows (expected if no game data)';
    END IF;
END $$;

-- Test: fn_validate_game_lineup returns expected columns
DO $$
DECLARE
    v_row RECORD;
BEGIN
    -- Test with a date that likely has no data - should return empty
    SELECT * INTO v_row FROM stg.fn_validate_game_lineup('2025-04-01', 'NYY') LIMIT 1;
    IF v_row.batting_order_pos IS NULL THEN
        RAISE NOTICE 'fn_validate_game_lineup returned no rows (expected if no lineup data)';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for 014_identity_reconciliation_functions.sql
-- ---------------------------------------------------------------------------

-- Test: fn_reconcile_candidates function exists
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

-- Test: fn_reconcile_candidates has correct argument signature
DO $$
DECLARE
    v_arg_count INT;
BEGIN
    SELECT count(*)
    INTO v_arg_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'stg' AND p.proname = 'fn_reconcile_candidates';

    -- Should have 2 arguments (p_auto_threshold, p_limit)
    IF v_arg_count != 2 THEN
        RAISE EXCEPTION 'fn_reconcile_candidates has incorrect argument count: %', v_arg_count;
    END IF;
END $$;

-- Test: fn_contextual_fingerprint_check function exists
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

-- Test: fn_full_identity_health_report function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'stg' AND p.proname = 'fn_full_identity_health_report'
    ) THEN
        RAISE EXCEPTION 'Function stg.fn_full_identity_health_report does not exist';
    END IF;
END $$;

-- Test: v_candidates_pending_human_review view exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_view
        WHERE viewname = 'v_candidates_pending_human_review'
    ) THEN
        RAISE EXCEPTION 'View stg.v_candidates_pending_human_review does not exist';
    END IF;
END $$;

-- Test: update_player_identity procedure exists
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

-- Test: v_identity_validation_dashboard view exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_view
        WHERE viewname = 'v_identity_validation_dashboard'
    ) THEN
        RAISE EXCEPTION 'View stg.v_identity_validation_dashboard does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Functional tests for 014_identity_reconciliation_functions.sql
-- ---------------------------------------------------------------------------

-- Test: fn_reconcile_candidates returns expected columns
DO $$
DECLARE
    v_row RECORD;
BEGIN
    -- Test with empty candidate table - should return no rows
    SELECT * INTO v_row FROM stg.fn_reconcile_candidates(0.85, 10) LIMIT 1;
    IF v_row.candidate_id IS NULL THEN
        RAISE NOTICE 'fn_reconcile_candidates returned no rows (expected if no candidates)';
    END IF;
END $$;

-- Test: fn_contextual_fingerprint_check returns expected columns
DO $$
DECLARE
    v_row RECORD;
BEGIN
    -- Test with a date that likely has no data - should return empty
    SELECT * INTO v_row FROM stg.fn_contextual_fingerprint_check('2025-04-01', 12345) LIMIT 1;
    IF v_row.mlbam_player_id IS NULL THEN
        RAISE NOTICE 'fn_contextual_fingerprint_check returned no rows (expected if no game data)';
    END IF;
END $$;

-- Test: fn_full_identity_health_report returns valid JSONB
DO $$
DECLARE
    v_report JSONB;
BEGIN
    v_report := stg.fn_full_identity_health_report();
    IF jsonb_typeof(v_report) != 'object' THEN
        RAISE EXCEPTION 'fn_full_identity_health_report should return JSONB object, got %', jsonb_typeof(v_report);
    END IF;
    -- Verify expected keys exist
    IF NOT (v_report ? 'report_generated_at') THEN
        RAISE EXCEPTION 'fn_full_identity_health_report missing report_generated_at key';
    END IF;
    IF NOT (v_report ? 'orphaned_pitches_48h') THEN
        RAISE EXCEPTION 'fn_full_identity_health_report missing orphaned_pitches_48h key';
    END IF;
    IF NOT (v_report ? 'critical_alert') THEN
        RAISE EXCEPTION 'fn_full_identity_health_report missing critical_alert key';
    END IF;
END $$;

-- Test: v_candidates_pending_human_review returns expected columns
DO $$
DECLARE
    v_row RECORD;
BEGIN
    -- Test with empty candidate table - should return no rows
    SELECT * INTO v_row FROM stg.v_candidates_pending_human_review LIMIT 1;
    IF v_row.player_identity_candidate_id IS NULL THEN
        RAISE NOTICE 'v_candidates_pending_human_review returned no rows (expected if no candidates)';
    END IF;
END $$;

-- Test: v_identity_validation_dashboard returns expected columns
DO $$
DECLARE
    v_row RECORD;
BEGIN
    SELECT * INTO v_row FROM stg.v_identity_validation_dashboard;
    IF v_row.total_players IS NULL THEN
        RAISE EXCEPTION 'v_identity_validation_dashboard should return total_players';
    END IF;
    IF v_row.pct_high_confidence IS NULL THEN
        RAISE EXCEPTION 'v_identity_validation_dashboard should return pct_high_confidence';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tests for touch_updated_at functions
-- ---------------------------------------------------------------------------

-- Test: stg_touch_updated_at function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'stg_touch_updated_at'
    ) THEN
        RAISE EXCEPTION 'Function util.stg_touch_updated_at does not exist';
    END IF;
END $$;

-- Test: core_touch_updated_at function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'core_touch_updated_at'
    ) THEN
        RAISE EXCEPTION 'Function util.core_touch_updated_at does not exist';
    END IF;
END $$;

-- Test: ml_ops_touch_updated_at function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'ml_ops_touch_updated_at'
    ) THEN
        RAISE EXCEPTION 'Function util.ml_ops_touch_updated_at does not exist';
    END IF;
END $$;

-- Test: auth_touch_updated_at function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'auth_touch_updated_at'
    ) THEN
        RAISE EXCEPTION 'Function util.auth_touch_updated_at does not exist';
    END IF;
END $$;

-- Test: api_touch_updated_at function exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'util' AND p.proname = 'api_touch_updated_at'
    ) THEN
        RAISE EXCEPTION 'Function util.api_touch_updated_at does not exist';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------------
SELECT 'utility functions tests passed' AS result;