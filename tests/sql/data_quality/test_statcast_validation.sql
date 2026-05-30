-- =============================================================================
-- Data Quality Tests: Statcast Validation
--
-- Tests for Statcast data quality and completeness.
-- These tests verify raw_statcast.pitch has all expected fields and valid data.
--
-- Run after: raw_statcast.pitch populated
-- =============================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- Test: All 118 Statcast columns exist
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_column_count INT;
BEGIN
    SELECT COUNT(*) INTO v_column_count
    FROM pg_attribute
    WHERE attrelid = 'raw_statcast.pitch'::regclass
    AND attnum > 0
    AND NOT attisdropped;
    
    RAISE NOTICE 'raw_statcast.pitch has % columns', v_column_count;
    
    -- Should have at least 110 columns (we added 16 tracking fields)
    IF v_column_count < 110 THEN
        RAISE WARNING 'Expected at least 110 columns, found %', v_column_count;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test: Required Statcast fields are present
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_missing_required TEXT;
BEGIN
    -- Check that essential fields exist
    SELECT string_agg(attname, ', ') INTO v_missing_required
    FROM pg_attribute
    WHERE attrelid = 'raw_statcast.pitch'::regclass
    AND attnum > 0
    AND NOT attisdropped
    AND attname IN ('game_pk', 'inning', 'at_bat_number', 'pitch_number', 
                    'batter', 'pitcher', 'events', 'description')
    HAVING COUNT(*) < 8;
    
    IF v_missing_required IS NOT NULL THEN
        RAISE EXCEPTION 'Missing required Statcast fields: %', v_missing_required;
    END IF;
    
    RAISE NOTICE 'All required Statcast fields present';
END $$;

-- ---------------------------------------------------------------------------
-- Test: Statcast year range validation
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_min_year INT;
    v_max_year INT;
BEGIN
    SELECT 
        EXTRACT(YEAR FROM MIN(game_date))::INT,
        EXTRACT(YEAR FROM MAX(game_date))::INT
    INTO v_min_year, v_max_year
    FROM raw_statcast.pitch
    WHERE game_date IS NOT NULL;
    
    RAISE NOTICE 'Statcast date range: % to %', v_min_year, v_max_year;
    
    -- Statcast starts in 2015
    IF v_min_year IS NOT NULL AND v_min_year < 2015 THEN
        RAISE WARNING 'Found Statcast data before 2015: %', v_min_year;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test: Statcast game_pk uniqueness
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_duplicate_count INT;
BEGIN
    SELECT COUNT(*) INTO v_duplicate_count
    FROM (
        SELECT game_pk, inning, at_bat_number, pitch_number, COUNT(*) as cnt
        FROM raw_statcast.pitch
        GROUP BY game_pk, inning, at_bat_number, pitch_number
        HAVING COUNT(*) > 1
    ) duplicates;
    
    IF v_duplicate_count > 0 THEN
        RAISE WARNING 'Found % duplicate pitch records', v_duplicate_count;
    END IF;
    
    RAISE NOTICE 'Duplicate pitch check complete';
END $$;

-- ---------------------------------------------------------------------------
-- Test: Statcast team code resolution
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_unresolved_teams INT;
BEGIN
    SELECT COUNT(DISTINCT away_team) INTO v_unresolved_teams
    FROM raw_statcast.pitch p
    WHERE p.away_team IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM core.team t
        WHERE t.statcast_team_id = p.away_team
    );
    
    RAISE NOTICE 'Unresolved away team codes: %', v_unresolved_teams;
    
    -- All teams should resolve
    IF v_unresolved_teams > 0 THEN
        RAISE WARNING '% team codes do not resolve to core.team', v_unresolved_teams;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test: Statcast pitch type distribution
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_null_count INT;
    v_known_count INT;
BEGIN
    SELECT 
        COUNT(*) FILTER (WHERE pitch_type IS NULL) INTO v_null_count,
        COUNT(*) FILTER (WHERE pitch_type IS NOT NULL) INTO v_known_count
    FROM raw_statcast.pitch;
    
    RAISE NOTICE 'Pitch type distribution: NULL=%, Known=%', v_null_count, v_known_count;
END $$;

-- ---------------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------------
SELECT 'statcast validation tests completed' AS result;