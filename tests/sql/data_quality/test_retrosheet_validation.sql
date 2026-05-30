-- =============================================================================
-- Data Quality Tests: Retrosheet Validation
--
-- Tests for Retrosheet data quality and completeness.
-- These tests verify event file structure and data integrity.
--
-- Run after: raw_retrosheet tables populated
-- =============================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- Test: Retrosheet tables exist
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_table_count INT;
BEGIN
    SELECT COUNT(*) INTO v_table_count
    FROM pg_tables
    WHERE schemaname = 'raw_retrosheet';
    
    RAISE NOTICE 'raw_retrosheet has % tables', v_table_count;
    
    -- Should have at least play_event and game tables
    IF v_table_count < 2 THEN
        RAISE WARNING 'Expected at least 2 Retrosheet tables, found %', v_table_count;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test: Retrosheet year range validation
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
    FROM raw_retrosheet.game
    WHERE game_date IS NOT NULL;
    
    RAISE NOTICE 'Retrosheet game date range: % to %', v_min_year, v_max_year;
    
    -- Retrosheet starts in 1950s
    IF v_min_year IS NOT NULL AND v_min_year < 1950 THEN
        RAISE WARNING 'Found Retrosheet data before 1950: %', v_min_year;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test: Retrosheet play_event structure
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_event_count INT;
    v_null_game_ids INT;
BEGIN
    SELECT COUNT(*) INTO v_event_count FROM raw_retrosheet.play_event;
    SELECT COUNT(*) INTO v_null_game_ids FROM raw_retrosheet.play_event WHERE game_id IS NULL;
    
    RAISE NOTICE 'Retrosheet play_event: % total, % with NULL game_id', 
        v_event_count, v_null_game_ids;
    
    -- Most events should have game_id
    IF v_event_count > 0 AND (v_null_game_ids::FLOAT / v_event_count) > 0.01 THEN
        RAISE WARNING 'More than 1% of play events have NULL game_id';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test: Retrosheet record type distribution
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_record_types TEXT;
BEGIN
    SELECT string_agg(DISTINCT record_type, ', ') INTO v_record_types
    FROM raw_retrosheet.play_event
    WHERE record_type IS NOT NULL;
    
    RAISE NOTICE 'Retrosheet record types found: %', v_record_types;
    
    -- Should have at least 'play' and 'id' types
    IF v_record_types IS NULL OR v_record_types NOT LIKE '%play%' THEN
        RAISE WARNING 'Missing expected record type: play';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test: Retrosheet game_id format
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_invalid_format INT;
BEGIN
    -- Game IDs should follow RETROYYYYMMDD format (e.g., SLN202404101)
    SELECT COUNT(*) INTO v_invalid_format
    FROM raw_retrosheet.game
    WHERE game_id IS NOT NULL
    AND game_id !~ '^[A-Z]{3}[0-9]{7}[12]$';
    
    RAISE NOTICE 'Games with invalid ID format: %', v_invalid_format;
    
    -- All game IDs should follow expected format
    IF v_invalid_format > 0 THEN
        RAISE WARNING '% games have invalid game_id format', v_invalid_format;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------------
SELECT 'retrosheet validation tests completed' AS result;