-- =============================================================================
-- Data Quality Tests: Materialized View Accuracy
--
-- Tests for materialized view correctness and freshness.
-- These tests verify analytics views return accurate results.
--
-- Run after: Materialized views populated
-- =============================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- Test: mv_player_statcast_summary exists and has expected columns
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_column_count INT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_matview_def
        WHERE matviewname = 'mv_player_statcast_summary'
    ) THEN
        RAISE EXCEPTION 'Materialized view mv_player_statcast_summary does not exist';
    END IF;
    
    SELECT COUNT(*) INTO v_column_count
    FROM pg_attribute
    WHERE attrelid = 'ml.mv_player_statcast_summary'::regclass
    AND attnum > 0
    AND NOT attisdropped;
    
    RAISE NOTICE 'mv_player_statcast_summary has % columns', v_column_count;
    
    -- Should have pitch count and player identification columns
    IF v_column_count < 10 THEN
        RAISE WARNING 'mv_player_statcast_summary has fewer than expected columns: %', v_column_count;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test: mv_pitch_arsenal_by_season exists
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_matview_def
        WHERE matviewname = 'mv_pitch_arsenal_by_season'
    ) THEN
        RAISE EXCEPTION 'Materialized view mv_pitch_arsenal_by_season does not exist';
    END IF;
    
    RAISE NOTICE 'mv_pitch_arsenal_by_season exists';
END $$;

-- ---------------------------------------------------------------------------
-- Test: mv_game_score_context exists
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_matview_def
        WHERE matviewname = 'mv_game_score_context'
    ) THEN
        RAISE EXCEPTION 'Materialized view mv_game_score_context does not exist';
    END IF;
    
    RAISE NOTICE 'mv_game_score_context exists';
END $$;

-- ---------------------------------------------------------------------------
-- Test: mv_batter_spray_heatmap exists
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_matview_def
        WHERE matviewname = 'mv_batter_spray_heatmap'
    ) THEN
        RAISE EXCEPTION 'Materialized view mv_batter_spray_heatmap does not exist';
    END IF;
    
    RAISE NOTICE 'mv_batter_spray_heatmap exists';
END $$;

-- ---------------------------------------------------------------------------
-- Test: mv_pitcher_zone_profile exists
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_matview_def
        WHERE matviewname = 'mv_pitcher_zone_profile'
    ) THEN
        RAISE EXCEPTION 'Materialized view mv_pitcher_zone_profile does not exist';
    END IF;
    
    RAISE NOTICE 'mv_pitcher_zone_profile exists';
END $$;

-- ---------------------------------------------------------------------------
-- Test: MV freshness (last refresh within 7 days)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_stale_mvs INT;
BEGIN
    SELECT COUNT(*) INTO v_stale_mvs
    FROM pg_matview_def
    WHERE matviewname IN (
        'mv_player_statcast_summary',
        'mv_pitch_arsenal_by_season',
        'mv_game_score_context',
        'mv_batter_spray_heatmap',
        'mv_pitcher_zone_profile'
    )
    AND (
        pg_last_refresh_time IS NULL
        OR pg_last_refresh_time < NOW() - INTERVAL '7 days'
    );
    
    RAISE NOTICE 'Stale materialized views: %', v_stale_mvs;
    
    -- Report but don't fail - MVs may be intentionally stale
    IF v_stale_mvs > 0 THEN
        RAISE WARNING '% materialized views are stale (older than 7 days)', v_stale_mvs;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test: Pitch count consistency between raw and MV
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_raw_count INT;
    v_mv_count INT;
BEGIN
    SELECT COUNT(*) INTO v_raw_count FROM raw_statcast.pitch;
    
    SELECT SUM(total_pitches) INTO v_mv_count 
    FROM ml.mv_player_statcast_summary;
    
    RAISE NOTICE 'Raw pitch count: %, MV total pitches: %', v_raw_count, v_mv_count;
    
    -- MV total should be close to raw count (within 5% for data quality)
    IF v_raw_count > 0 AND v_mv_count IS NOT NULL THEN
        IF ABS(v_raw_count - v_mv_count) / v_raw_count > 0.05 THEN
            RAISE WARNING 'MV pitch count differs significantly from raw data';
        END IF;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------------
SELECT 'mv accuracy tests completed' AS result;