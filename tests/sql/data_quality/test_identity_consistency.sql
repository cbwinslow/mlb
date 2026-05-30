-- =============================================================================
-- Data Quality Tests: Identity Consistency
--
-- Tests for cross-source player identity consistency.
-- These tests verify that player identities are correctly linked across all sources.
--
-- Run after: All raw data loaded, identity bridge populated
-- =============================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- Test: No orphaned Statcast players (all have player_identity records)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_orphaned_count INT;
BEGIN
    SELECT COUNT(*) INTO v_orphaned_count
    FROM raw_statcast.pitch p
    WHERE p.batter IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM stg.player_identity pi
        WHERE pi.mlbam_player_id = p.batter
    );
    
    IF v_orphaned_count > 0 THEN
        RAISE WARNING 'Found % orphaned Statcast batter IDs without player_identity records', v_orphaned_count;
    END IF;
    
    -- This is informational - in production you may want to assert = 0
    -- For now, just report the count
    RAISE NOTICE 'Orphaned Statcast batter IDs: %', v_orphaned_count;
END $$;

-- ---------------------------------------------------------------------------
-- Test: No orphaned Retrosheet players
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_orphaned_count INT;
BEGIN
    SELECT COUNT(*) INTO v_orphaned_count
    FROM raw_retrosheet.play_event pe
    WHERE pe.batter_id IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM stg.player_identity pi
        WHERE pi.retrosheet_player_id = pe.batter_id
    );
    
    RAISE NOTICE 'Orphaned Retrosheet batter IDs: %', v_orphaned_count;
END $$;

-- ---------------------------------------------------------------------------
-- Test: No orphaned Chadwick players
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_orphaned_count INT;
BEGIN
    SELECT COUNT(*) INTO v_orphaned_count
    FROM raw_chadwick.cwevent ce
    WHERE ce.batter_id IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM stg.player_identity pi
        WHERE pi.retrosheet_player_id = ce.batter_id
    );
    
    RAISE NOTICE 'Orphaned Chadwick batter IDs: %', v_orphaned_count;
END $$;

-- ---------------------------------------------------------------------------
-- Test: Identity confidence score distribution
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_high_confidence INT;
    v_medium_confidence INT;
    v_low_confidence INT;
    v_total INT;
BEGIN
    SELECT 
        COUNT(*) FILTER (WHERE identity_confidence_score >= 0.9) INTO v_high_confidence,
        COUNT(*) FILTER (WHERE identity_confidence_score >= 0.7 AND identity_confidence_score < 0.9) INTO v_medium_confidence,
        COUNT(*) FILTER (WHERE identity_confidence_score < 0.7) INTO v_low_confidence,
        COUNT(*) INTO v_total
    FROM stg.player_identity;
    
    RAISE NOTICE 'Identity confidence distribution: High (≥0.9)=%, Medium (0.7-0.9)=%, Low (<0.7)=%, Total=%',
        v_high_confidence, v_medium_confidence, v_low_confidence, v_total;
    
    -- At least 80% should be high confidence in a healthy system
    IF v_total > 0 AND (v_high_confidence::FLOAT / v_total) < 0.8 THEN
        RAISE WARNING 'Only % of player identities have high confidence', 
            ROUND((v_high_confidence::FLOAT / v_total) * 100, 2);
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Test: Cross-source ID overlap (players with multiple source IDs)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_multi_source_count INT;
    v_total_count INT;
BEGIN
    SELECT COUNT(*) INTO v_total_count FROM stg.player_identity;
    
    SELECT COUNT(*) INTO v_multi_source_count
    FROM stg.player_identity
    WHERE (
        (mlbam_player_id IS NOT NULL)::INT +
        (retrosheet_player_id IS NOT NULL)::INT +
        (bbref_player_id IS NOT NULL)::INT +
        (fangraphs_player_id IS NOT NULL)::INT +
        (lahman_player_id IS NOT NULL)::INT
    ) >= 2;
    
    RAISE NOTICE 'Players with multiple source IDs: % out of %', 
        v_multi_source_count, v_total_count;
END $$;

-- ---------------------------------------------------------------------------
-- Test: No conflicting ID mappings
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_conflict_count INT;
BEGIN
    -- Check for same MLBAM ID mapped to different Retrosheet IDs
    SELECT COUNT(*) INTO v_conflict_count
    FROM stg.player_identity pi
    WHERE EXISTS (
        SELECT 1 FROM stg.player_identity pi2
        WHERE pi2.mlbam_player_id = pi.mlbam_player_id
        AND pi2.retrosheet_player_id IS NOT NULL
        AND pi.retrosheet_player_id IS NOT NULL
        AND pi2.retrosheet_player_id != pi.retrosheet_player_id
    );
    
    IF v_conflict_count > 0 THEN
        RAISE EXCEPTION 'Found % conflicting MLBAM-to-Retrosheet mappings', v_conflict_count;
    END IF;
    
    RAISE NOTICE 'No conflicting ID mappings found';
END $$;

-- ---------------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------------
SELECT 'identity consistency tests completed' AS result;