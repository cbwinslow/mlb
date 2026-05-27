BEGIN;

-- ===========================================================================
-- 070_ml_ops / 012_mv_spray_zone_analytics.sql
--
-- Additional baseball analytics materialized views for ML feature mart.
-- All views are created WITH NO DATA and refreshed via:
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mart.<view_name>;
--
-- Views created:
--   mart.mv_batter_spray_heatmap   -- spray chart aggregated by player/season/situation
--   mart.mv_pitcher_zone_profile    -- zone profile aggregated by pitcher/season
--
-- Depends on: sql/040_raw/003_raw_statcast.sql
--             sql/060_core/001_core_entities.sql (core.player)
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- mart.mv_batter_spray_heatmap
--
-- One row per (batter, season) with spray chart distribution.
-- Aggregates batted ball spray data into pull/center/oppo tendencies.
-- Primary use: swing analysis, pull tendencies, defensive positioning models.
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS mart.mv_batter_spray_heatmap AS
SELECT
    p.player_id,
    p.full_name,
    p.mlbam_player_id,

    cp.game_year                                    AS season,

    -- Pull/Oppo tendencies (hc_x in feet: negative = pull field, positive = oppo field)
    ROUND(
        COUNT(*) FILTER (WHERE cp.hc_x IS NOT NULL AND cp.hc_x < -3)
        ::NUMERIC / NULLIF(COUNT(*) FILTER (WHERE cp.events IS NOT NULL AND cp.description ILIKE '%hit_into_play%'), 0), 4
    )                                               AS pull_pct,
    ROUND(
        COUNT(*) FILTER (WHERE cp.hc_x IS NOT NULL AND cp.hc_x BETWEEN -3 AND 3)
        ::NUMERIC / NULLIF(COUNT(*) FILTER (WHERE cp.events IS NOT NULL AND cp.description ILIKE '%hit_into_play%'), 0), 4
    )                                               AS center_pct,
    ROUND(
        COUNT(*) FILTER (WHERE cp.hc_x IS NOT NULL AND cp.hc_x > 3)
        ::NUMERIC / NULLIF(COUNT(*) FILTER (WHERE cp.events IS NOT NULL AND cp.description ILIKE '%hit_into_play%'), 0), 4
    )                                               AS oppo_pct,

    -- Spray coordinates (avg, not binned for heat map - downstream bin)
    ROUND(AVG(cp.hc_x)::NUMERIC, 1)               AS avg_spray_x,
    ROUND(AVG(cp.hc_y)::NUMERIC, 1)               AS avg_spray_y,

    -- Launch angle buckets
    ROUND(
        COUNT(*) FILTER (WHERE cp.launch_angle < 10)
        ::NUMERIC / NULLIF(COUNT(*) FILTER (WHERE cp.launch_angle IS NOT NULL), 0), 4
    )                                               AS groundball_pct,
    ROUND(
        COUNT(*) FILTER (WHERE cp.launch_angle BETWEEN 10 AND 25)
        ::NUMERIC / NULLIF(COUNT(*) FILTER (WHERE cp.launch_angle IS NOT NULL), 0), 4
    )                                               AS line_drive_pct,
    ROUND(
        COUNT(*) FILTER (WHERE cp.launch_angle > 25)
        ::NUMERIC / NULLIF(COUNT(*) FILTER (WHERE cp.launch_angle IS NOT NULL), 0), 4
    )                                               AS flyball_pct,

    -- Hit location by field (Rawlings hit_location codes: 1-15)
    COUNT(*) FILTER (WHERE cp.hit_location BETWEEN 1 AND 5)  AS hits_left_field,
    COUNT(*) FILTER (WHERE cp.hit_location BETWEEN 6 AND 8)  AS hits_center_field,
    COUNT(*) FILTER (WHERE cp.hit_location BETWEEN 9 AND 13) AS hits_right_field,

    -- Expected outcomes on contact
    ROUND(AVG(cp.estimated_ba_using_speedangle) FILTER (
        WHERE cp.description ILIKE '%hit_into_play%')::NUMERIC, 3)    AS avg_xba_on_contact,
    ROUND(AVG(cp.estimated_slg_using_speedangle) FILTER (
        WHERE cp.description ILIKE '%hit_into_play%')::NUMERIC, 3)    AS avg_xslg_on_contact,

    -- Distance and exit velocity
    ROUND(AVG(cp.hit_distance_sc)::NUMERIC, 0)      AS avg_hit_distance,
    ROUND(AVG(cp.launch_speed)::NUMERIC, 1)         AS avg_exit_velocity,
    ROUND(MAX(cp.launch_speed)::NUMERIC, 1)         AS max_exit_velocity,

    -- Volume
    COUNT(*) FILTER (WHERE cp.events IS NOT NULL AND cp.description ILIKE '%hit_into_play%') AS batted_balls,
    COUNT(*) FILTER (WHERE cp.launch_speed >= 95)    AS hard_hits,

    NOW()                                           AS refreshed_at

FROM raw_statcast.pitch cp
JOIN core.player p
    ON p.mlbam_player_id = cp.batter::TEXT
WHERE cp.game_year IS NOT NULL
  AND cp.description ILIKE '%hit_into_play%'
  AND cp.hc_x IS NOT NULL
GROUP BY
    p.player_id, p.full_name, p.mlbam_player_id,
    cp.game_year
WITH NO DATA;

COMMENT ON MATERIALIZED VIEW mart.mv_batter_spray_heatmap IS
    'One row per (batter, season) with spray chart distribution. '
    'Aggregates batted ball spray data into pull/center/oppo tendencies, '
    'field location counts, launch angle buckets, and expected outcomes on contact. '
    'Primary use: swing analysis, pull tendencies, defensive positioning models. '
    'Refreshed via REFRESH MATERIALIZED VIEW CONCURRENTLY.';

-- CONCURRENTLY-safe unique index
CREATE UNIQUE INDEX IF NOT EXISTS mart_mv_batter_spray_heatmap_uidx
    ON mart.mv_batter_spray_heatmap (player_id, season);


-- ---------------------------------------------------------------------------
-- mart.mv_pitcher_zone_profile
--
-- One row per (pitcher, season, zone) with pitch distribution and outcomes.
-- Zones: 1-9 (strike zone grid), balls counted separately as zone IS NULL.
-- Primary use: pitch sequencing analysis, zone control metrics.
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS mart.mv_pitcher_zone_profile AS
SELECT
    p.player_id,
    p.full_name,
    p.mlbam_player_id,

    cp.game_year                                    AS season,

    -- Zone dimension (1-9 strike zone, NULL = ball)
    cp.zone,

    -- Pitch counts by type within zone
    COUNT(*) FILTER (WHERE cp.pitch_type = 'FF')     AS four_seam_fb_count,
    COUNT(*) FILTER (WHERE cp.pitch_type = 'FT')     AS two_seam_fb_count,
    COUNT(*) FILTER (WHERE cp.pitch_type = 'FC')     AS cutter_count,
    COUNT(*) FILTER (WHERE cp.pitch_type = 'SL')     AS slider_count,
    COUNT(*) FILTER (WHERE cp.pitch_type = 'CH')     AS changeup_count,
    COUNT(*) FILTER (WHERE cp.pitch_type = 'CU')     AS curveball_count,
    COUNT(*) FILTER (WHERE cp.pitch_type = 'KC')     AS knuckle_curve_count,

    -- Overall volume
    COUNT(*)                                        AS pitches,

    -- Zone rate (within zone) - proportion of pitcher's pitches that land in this zone
    ROUND(
        COUNT(*)::NUMERIC / NULLIF(
            (SELECT COUNT(*) FROM raw_statcast.pitch r WHERE r.pitcher = cp.pitcher AND r.game_year = cp.game_year), 0
        ), 4
    )                                               AS zone_usage_pct,

    -- Swing rates within zone
    ROUND(
        COUNT(*) FILTER (WHERE cp.description ILIKE '%swinging%')::NUMERIC
        / NULLIF(COUNT(*), 0), 4
    )                                               AS swing_pct_in_zone,

    -- Whiff rate within zone
    ROUND(
        COUNT(*) FILTER (WHERE cp.description ILIKE '%swinging_strike%')::NUMERIC
        / NULLIF(COUNT(*) FILTER (WHERE cp.description ILIKE '%swinging%'), 0), 4
    )                                               AS whiff_pct_in_zone,

    -- Contact rate within zone
    ROUND(
        COUNT(*) FILTER (WHERE cp.description ILIKE '%hit_into_play%')::NUMERIC
        / NULLIF(COUNT(*) FILTER (WHERE cp.description ILIKE '%swinging%'), 0), 4
    )                                               AS contact_pct_in_zone,

    -- Expected outcome when contacted in zone
    ROUND(AVG(cp.estimated_ba_using_speedangle) FILTER (
        WHERE cp.description ILIKE '%hit_into_play%')::NUMERIC, 3)    AS avg_xba_in_zone,
    ROUND(AVG(cp.estimated_woba_using_speedangle) FILTER (
        WHERE cp.description ILIKE '%hit_into_play%')::NUMERIC, 3)    AS avg_xwoba_in_zone,

    -- Run value in zone
    ROUND(SUM(cp.delta_run_exp)::NUMERIC, 2)          AS total_run_exp_in_zone,
    ROUND(AVG(cp.delta_run_exp)::NUMERIC, 4)          AS avg_run_exp_per_pitch_in_zone,

    -- Velocity and movement within zone
    ROUND(AVG(cp.release_speed)::NUMERIC, 1)         AS avg_velocity_in_zone,
    ROUND(AVG(cp.release_spin_rate)::NUMERIC, 0)     AS avg_spin_rate_in_zone,
    ROUND(AVG(cp.pfx_x)::NUMERIC, 2)               AS avg_horz_break_in_zone,
    ROUND(AVG(cp.pfx_z)::NUMERIC, 2)               AS avg_vert_break_in_zone,

    NOW()                                           AS refreshed_at

FROM raw_statcast.pitch cp
JOIN core.player p
    ON p.mlbam_player_id = cp.pitcher::TEXT
WHERE cp.game_year IS NOT NULL
  AND cp.zone IS NOT NULL
GROUP BY
    p.player_id, p.full_name, p.mlbam_player_id,
    cp.game_year, cp.zone
WITH NO DATA;

COMMENT ON MATERIALIZED VIEW mart.mv_pitcher_zone_profile IS
    'One row per (pitcher, season, zone) with pitch distribution and outcomes. '
    'Zones 1-9 represent the strike zone grid (upper-left to lower-right). '
    'Covers pitch type counts, swing/whiff/contact rates, expected outcomes, '
    'and run expectancy by zone. Primary use: pitch sequencing analysis, '
    'zone control metrics, and pitcher approach modeling. '
    'Refreshed via REFRESH MATERIALIZED VIEW CONCURRENTLY.';

-- CONCURRENTLY-safe unique index
CREATE UNIQUE INDEX IF NOT EXISTS mart_mv_pitcher_zone_profile_uidx
    ON mart.mv_pitcher_zone_profile (player_id, season, zone);


COMMIT;
