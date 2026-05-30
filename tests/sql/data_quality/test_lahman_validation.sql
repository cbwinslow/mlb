-- =============================================================================
-- Data Quality Tests: Lahman Validation
--
-- Tests for Lahman data quality and completeness.
-- These tests verify all 21 Lahman tables have expected structure and data.
--
-- Run after: raw_lahman tables populated
-- =============================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- Test: All 21 Lahman tables exist
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_table_count INT;
BEGIN
    SELECT COUNT(*) INTO v_table_count
    FROM pg_tables
    WHERE schemaname = 'raw_lahman';
    
    RAISE NOTICE 'raw_lahman has % tables', v_table_count;
    
    -- Should have 21 tables
    IF v_table_count < 20 THEN
        RAISE WARNING 'Expected 21 Lahman tables, found %', v_table_count;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test: Lahman year range validation
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_min_year INT;
    v_max_year INT;
BEGIN
    SELECT 
        MIN(yearid),
        MAX(yearid)
    INTO v_min_year, v_max_year
    FROM raw_lahman.batting;
    
    RAISE NOTICE 'Lahman batting year range: % to %', v_min_year, v_max_year;
    
    -- Lahman starts in 1871
    IF v_min_year IS NOT NULL AND v_min_year < 1871 THEN
        RAISE WARNING 'Found Lahman data before 1871: %', v_min_year;
    END IF;
    
    -- Lahman should not exceed 2100
    IF v_max_year IS NOT NULL AND v_max_year > 2100 THEN
        RAISE WARNING 'Found Lahman data after 2100: %', v_max_year;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test: Lahman people table completeness
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_player_count INT;
    v_null_names INT;
BEGIN
    SELECT COUNT(*) INTO v_player_count FROM raw_lahman.people;
    SELECT COUNT(*) INTO v_null_names FROM raw_lahman.people WHERE namefirst IS NULL OR namelast IS NULL;
    
    RAISE NOTICE 'Lahman people: % total, % with NULL names', v_player_count, v_null_names;
    
    -- Should have ~24,000+ players (historical)
    IF v_player_count < 20000 THEN
        RAISE WARNING 'Expected 20000+ players, found %', v_player_count;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test: Lahman batting/pitching data consistency
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_batting_years INT;
    v_pitching_years INT;
BEGIN
    SELECT COUNT(DISTINCT yearid) INTO v_batting_years FROM raw_lahman.batting;
    SELECT COUNT(DISTINCT yearid) INTO v_pitching_years FROM raw_lahman.pitching;
    
    RAISE NOTICE 'Batting years: %, Pitching years: %', v_batting_years, v_pitching_years;
    
    -- Should have similar year coverage
    IF ABS(v_batting_years - v_pitching_years) > 5 THEN
        RAISE WARNING 'Batting and pitching year counts differ significantly';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test: Lahman team codes consistency
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_teams_batting INT;
    v_teams_pitching INT;
    v_teams_fielding INT;
BEGIN
    SELECT COUNT(DISTINCT teamid) INTO v_teams_batting FROM raw_lahman.batting;
    SELECT COUNT(DISTINCT teamid) INTO v_teams_pitching FROM raw_lahman.pitching;
    SELECT COUNT(DISTINCT teamid) INTO v_teams_fielding FROM raw_lahman.fielding;
    
    RAISE NOTICE 'Teams in batting: %, pitching: %, fielding: %', 
        v_teams_batting, v_teams_pitching, v_teams_fielding;
END $$;

-- ---------------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------------
SELECT 'lahman validation tests completed' AS result;