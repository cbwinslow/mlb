BEGIN;

-- ===========================================================================
-- 070_ml_ops / 010_mv_statcast_player_summary.sql
--
-- Baseball-data materialized views for the mart schema.
-- These complement the ML model management views in 006_marts_materialized_views.sql
-- and provide the core baseball analytics serving layer.
--
-- Views created:
--   mart.mv_player_statcast_summary  -- career + season batter/pitcher aggregates
--   mart.mv_pitch_arsenal_by_season  -- per-pitcher pitch type breakdown by season
--   mart.mv_game_score_context       -- game state and score context per pitch
--
-- All views are created WITH NO DATA and refreshed via:
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mart.<view_name>;
--
-- CONCURRENTLY-safe unique indexes are created on each view so that
-- REFRESH CONCURRENTLY never blocks reads.
--
-- Depends on: sql/040_raw/003_raw_statcast.sql
--             sql/060_core/001_core_entities.sql (core.player)
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- mart.mv_player_statcast_summary
--
-- One row per (player, season, role) where role IN ('batter', 'pitcher').
-- Aggregates all Statcast pitch-level data up to the player-season grain.
-- Covers:
--   - Counting stats (pitches seen/thrown, PA, AB, hits, HR, K, BB)
--   - Velocity / movement (release_speed, pfx_x/z, spin_rate)
--   - Bat tracking (bat_speed, swing_length) -- 2024+ only, NULL for prior seasons
--   - Expected outcomes (xba, xslg, xwoba, xwobacon, xobp, xiso)
--   - Hard contact (launch_speed, launch_angle, hit_distance_sc)
--   - Spray (hc_x, hc_y)
--   - Swing decisions (delta_run_exp, delta_home_run_exp)
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS mart.mv_player_statcast_summary AS
SELECT
    -- Identity
    p.player_id,
    p.full_name,
    p.mlbam_player_id,
    p.bbref_player_id,
    p.fangraphs_player_id,

    -- Season / role grain
    cp.game_year                        AS season,
    'batter'                            AS role,

    -- Volume
    COUNT(DISTINCT cp.game_pk)          AS games,
    COUNT(DISTINCT cp.at_bat_number
        || '-' || cp.game_pk::TEXT)     AS plate_appearances,
    COUNT(*) FILTER (
        WHERE cp.type != 'B')
        AS pitches_seen,

    -- Swing / contact rates
    ROUND(
        COUNT(*) FILTER (WHERE cp.description ILIKE '%swinging%' OR cp.description ILIKE 'foul%')
        ::NUMERIC
        / NULLIF(COUNT(*) FILTER (WHERE cp.type != 'B'), 0), 4
    )                                   AS swing_pct,
    ROUND(
        COUNT(*) FILTER (WHERE cp.description ILIKE '%hit_into_play%')
        ::NUMERIC
        / NULLIF(COUNT(*) FILTER (WHERE cp.description ILIKE '%swinging%' OR cp.description ILIKE 'foul%' OR cp.description ILIKE '%hit_into_play%'), 0), 4
    )                                   AS contact_pct,

    -- Bat tracking (2024+; NULL for older seasons)
    ROUND(AVG(cp.bat_speed)::NUMERIC, 1)          AS avg_bat_speed,
    ROUND(AVG(cp.swing_length)::NUMERIC, 2)       AS avg_swing_length,

    -- Launch / hard contact
    ROUND(AVG(cp.launch_speed)::NUMERIC, 1)       AS avg_exit_velocity,
    ROUND(AVG(cp.launch_angle)::NUMERIC, 1)       AS avg_launch_angle,
    ROUND(AVG(cp.hit_distance_sc)::NUMERIC, 0)    AS avg_hit_distance,
    ROUND(
        COUNT(*) FILTER (WHERE cp.launch_speed >= 95)
        ::NUMERIC
        / NULLIF(COUNT(*) FILTER (WHERE cp.launch_speed IS NOT NULL), 0), 4
    )                                   AS hard_hit_pct,

    -- Expected outcomes
    ROUND(AVG(cp.estimated_ba_using_speedangle)::NUMERIC, 3)   AS avg_xba,
    ROUND(AVG(cp.estimated_woba_using_speedangle)::NUMERIC, 3) AS avg_xwoba,
    ROUND(AVG(cp.estimated_slg_using_speedangle)::NUMERIC, 3)  AS avg_xslg,
    ROUND(AVG(cp.estimated_obp)::NUMERIC, 3)                 AS avg_xobp,

    -- Spray
    ROUND(AVG(cp.hc_x)::NUMERIC, 1)    AS avg_spray_x,
    ROUND(AVG(cp.hc_y)::NUMERIC, 1)    AS avg_spray_y,

    -- Run value
    ROUND(SUM(cp.delta_run_exp)::NUMERIC, 2)        AS total_delta_run_exp,
    ROUND(SUM(cp.delta_pitcher_run_exp)::NUMERIC, 4)  AS total_delta_hr_exp,
    ROUND(AVG(cp.delta_run_exp)::NUMERIC, 4)        AS avg_delta_run_exp_per_pitch,

    -- Metadata
    NOW()                               AS refreshed_at

FROM raw_statcast.pitch cp
JOIN core.player p
    ON p.mlbam_player_id = cp.batter::TEXT
WHERE cp.game_year IS NOT NULL
GROUP BY
    p.player_id, p.full_name, p.mlbam_player_id,
    p.bbref_player_id, p.fangraphs_player_id,
    cp.game_year

UNION ALL

-- Pitcher side
SELECT
    p.player_id,
    p.full_name,
    p.mlbam_player_id,
    p.bbref_player_id,
    p.fangraphs_player_id,

    cp.game_year                        AS season,
    'pitcher'                           AS role,

    COUNT(DISTINCT cp.game_pk)          AS games,
    COUNT(DISTINCT cp.at_bat_number
        || '-' || cp.game_pk::TEXT)     AS plate_appearances,
    COUNT(*)                            AS pitches_seen,

    -- Zone / swing rates from pitcher perspective
    ROUND(
        COUNT(*) FILTER (WHERE cp.zone BETWEEN 1 AND 9)
        ::NUMERIC / NULLIF(COUNT(*), 0), 4
    )                                   AS zone_pct,
    ROUND(
        COUNT(*) FILTER (WHERE cp.description ILIKE '%swinging%')
        ::NUMERIC / NULLIF(COUNT(*), 0), 4
    )                                   AS swinging_strike_pct,

    -- Bat tracking (not applicable to pitcher role; NULL)
    NULL::NUMERIC                       AS avg_bat_speed,
    NULL::NUMERIC                       AS avg_swing_length,

    -- Velocity / stuff
    ROUND(AVG(cp.release_speed)::NUMERIC, 1)      AS avg_exit_velocity,
    ROUND(AVG(cp.effective_speed)::NUMERIC, 1)    AS avg_launch_angle,
    ROUND(AVG(cp.release_spin_rate)::NUMERIC, 0)  AS avg_hit_distance,
    ROUND(
        COUNT(*) FILTER (WHERE cp.launch_speed >= 95)
        ::NUMERIC
        / NULLIF(COUNT(*) FILTER (WHERE cp.launch_speed IS NOT NULL), 0), 4
    )                                   AS hard_hit_pct,

    -- Expected outcomes allowed
    ROUND(AVG(cp.estimated_ba_using_speedangle)::NUMERIC, 3)   AS avg_xba,
    ROUND(AVG(cp.estimated_woba_using_speedangle)::NUMERIC, 3) AS avg_xwoba,
    ROUND(AVG(cp.estimated_slg_using_speedangle)::NUMERIC, 3)  AS avg_xslg,
    ROUND(AVG(cp.estimated_obp)::NUMERIC, 3)                AS avg_xobp,

    NULL::NUMERIC                        AS avg_spray_x,
    NULL::NUMERIC                        AS avg_spray_y,

    ROUND(SUM(cp.delta_run_exp)::NUMERIC, 2)        AS total_delta_run_exp,
    ROUND(SUM(cp.delta_pitcher_run_exp)::NUMERIC, 4)  AS total_delta_hr_exp,
    ROUND(AVG(cp.delta_run_exp)::NUMERIC, 4)        AS avg_delta_run_exp_per_pitch,

    NOW()                               AS refreshed_at

FROM raw_statcast.pitch cp
JOIN core.player p
    ON p.mlbam_player_id = cp.pitcher::TEXT
WHERE cp.game_year IS NOT NULL
GROUP BY
    p.player_id, p.full_name, p.mlbam_player_id,
    p.bbref_player_id, p.fangraphs_player_id,
    cp.game_year
WITH NO DATA;

COMMENT ON MATERIALIZED VIEW mart.mv_player_statcast_summary IS
    'One row per (player, season, role=batter|pitcher). Aggregates all Statcast pitch-level '
    'data to player-season grain. Covers bat tracking (2024+), expected outcomes (xba/xwoba/xslg), '
    'hard contact, spray, and run value. Refreshed via REFRESH MATERIALIZED VIEW CONCURRENTLY. '
    'Depends on raw_statcast.pitch, core.player.';

-- CONCURRENTLY-safe unique index (required for REFRESH CONCURRENTLY)
CREATE UNIQUE INDEX IF NOT EXISTS mart_mv_player_statcast_summary_uidx
    ON mart.mv_player_statcast_summary (player_id, season, role);


-- ---------------------------------------------------------------------------
-- mart.mv_pitch_arsenal_by_season
--
-- One row per (pitcher, season, pitch_type).
-- Pitcher arsenal breakdown: usage%, velocity, spin, movement, outcomes by pitch.
-- Primary use: pitch modelling, stuff+ metrics, platoon splits.
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS mart.mv_pitch_arsenal_by_season AS
SELECT
    p.player_id,
    p.full_name,
    p.mlbam_player_id,

    cp.game_year                                    AS season,
    cp.pitch_type,
    cp.pitch_name,

    -- Volume
    COUNT(*)                                        AS pitches_thrown,
    ROUND(
        COUNT(*)::NUMERIC
        / NULLIF(SUM(COUNT(*)) OVER (PARTITION BY p.player_id, cp.game_year), 0), 4
    )                                               AS usage_pct,

    -- Velocity
    ROUND(AVG(cp.release_speed)::NUMERIC, 1)        AS avg_velocity,
    ROUND(MAX(cp.release_speed)::NUMERIC, 1)        AS max_velocity,
    ROUND(MIN(cp.release_speed)::NUMERIC, 1)        AS min_velocity,
    ROUND(STDDEV(cp.release_speed)::NUMERIC, 2)     AS velocity_stddev,

    -- Spin
    ROUND(AVG(cp.release_spin_rate)::NUMERIC, 0)    AS avg_spin_rate,
    ROUND(AVG(cp.spin_axis)::NUMERIC, 0)            AS avg_spin_axis,

    -- Movement (inches)
    ROUND(AVG(cp.pfx_x)::NUMERIC, 2)               AS avg_horz_break,
    ROUND(AVG(cp.pfx_z)::NUMERIC, 2)               AS avg_vert_break,
    ROUND(AVG(cp.plate_x)::NUMERIC, 2)             AS avg_plate_x,
    ROUND(AVG(cp.plate_z)::NUMERIC, 2)             AS avg_plate_z,

    -- Release point
    ROUND(AVG(cp.release_pos_x)::NUMERIC, 2)       AS avg_release_x,
    ROUND(AVG(cp.release_pos_y)::NUMERIC, 2)       AS avg_release_y,
    ROUND(AVG(cp.release_pos_z)::NUMERIC, 2)       AS avg_release_z,
    ROUND(AVG(cp.release_extension)::NUMERIC, 2)   AS avg_extension,
    ROUND(AVG(cp.arm_angle)::NUMERIC, 1)           AS avg_arm_angle,

    -- Results
    ROUND(
        COUNT(*) FILTER (WHERE cp.zone BETWEEN 1 AND 9)
        ::NUMERIC / NULLIF(COUNT(*), 0), 4
    )                                               AS zone_pct,
    ROUND(
        COUNT(*) FILTER (WHERE cp.description ILIKE '%swinging%')
        ::NUMERIC / NULLIF(COUNT(*), 0), 4
    )                                               AS swinging_strike_pct,
    ROUND(
        COUNT(*) FILTER (WHERE cp.type = 'S')
        ::NUMERIC / NULLIF(COUNT(*), 0), 4
    )                                               AS strike_pct,
    ROUND(
        COUNT(*) FILTER (WHERE cp.description ILIKE '%hit_into_play%')
        ::NUMERIC / NULLIF(COUNT(*), 0), 4
    )                                               AS in_play_pct,

    -- Expected outcomes on contact
    ROUND(AVG(cp.estimated_ba_using_speedangle) FILTER (
        WHERE cp.description ILIKE '%hit_into_play%')::NUMERIC, 3)    AS avg_xba_on_contact,
    ROUND(AVG(cp.estimated_woba_using_speedangle) FILTER (
        WHERE cp.description ILIKE '%hit_into_play%')::NUMERIC, 3)    AS avg_xwoba_on_contact,

    -- Run value
    ROUND(SUM(cp.delta_run_exp)::NUMERIC, 2)        AS total_run_value,
    ROUND(AVG(cp.delta_run_exp)::NUMERIC, 4)        AS avg_run_value_per_pitch,

    NOW()                                           AS refreshed_at

FROM raw_statcast.pitch cp
JOIN core.player p
    ON p.mlbam_player_id = cp.pitcher::TEXT
WHERE cp.game_year IS NOT NULL
  AND cp.pitch_type IS NOT NULL
GROUP BY
    p.player_id, p.full_name, p.mlbam_player_id,
    cp.game_year, cp.pitch_type, cp.pitch_name
WITH NO DATA;

COMMENT ON MATERIALIZED VIEW mart.mv_pitch_arsenal_by_season IS
    'One row per (pitcher, season, pitch_type). Pitcher arsenal breakdown covering usage%, '
    'velocity, spin, movement, release point, arm angle, zone/whiff/contact rates, '
    'expected outcomes on contact, and per-pitch run value. '
    'Primary use: pitch modelling, stuff+ metrics, platoon analysis.';

CREATE UNIQUE INDEX IF NOT EXISTS mart_mv_pitch_arsenal_season_uidx
    ON mart.mv_pitch_arsenal_by_season (player_id, season, pitch_type);


-- ---------------------------------------------------------------------------
-- mart.mv_game_score_context
--
-- One row per (game_pk, inning, half_inning).
-- Game state context summary per inning half: score, outs, baserunners, leverage.
-- Primary use: game state features for in-game prediction models.
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS mart.mv_game_score_context AS
SELECT
    cp.game_pk,
    cp.game_date,
    cp.game_year                                        AS season,

    -- Score state at start of inning half (MIN = earliest pitch in inning)
    MIN(cp.home_score) FILTER (
        WHERE cp.pitch_number = 1)                  AS inning_start_home_score,
    MIN(cp.away_score) FILTER (
        WHERE cp.pitch_number = 1)                  AS inning_start_away_score,
    MAX(cp.home_score)                              AS inning_end_home_score,
    MAX(cp.away_score)                              AS inning_end_away_score,

    -- Runs scored in this inning half
    MAX(cp.home_score) - MIN(cp.home_score)         AS home_runs_this_half,
    MAX(cp.away_score) - MIN(cp.away_score)         AS away_runs_this_half,

    -- Plate appearances and pitches
    COUNT(DISTINCT cp.at_bat_number)                AS plate_appearances,
    COUNT(*)                                        AS pitches,

    -- Baserunner state frequencies (proportion of pitches with runner on each base)
    ROUND(
        COUNT(*) FILTER (WHERE cp.on_1b IS NOT NULL)
        ::NUMERIC / NULLIF(COUNT(*), 0), 4)         AS pct_pitches_runner_on_1b,
    ROUND(
        COUNT(*) FILTER (WHERE cp.on_2b IS NOT NULL)
        ::NUMERIC / NULLIF(COUNT(*), 0), 4)         AS pct_pitches_runner_on_2b,
    ROUND(
        COUNT(*) FILTER (WHERE cp.on_3b IS NOT NULL)
        ::NUMERIC / NULLIF(COUNT(*), 0), 4)         AS pct_pitches_runner_on_3b,

    -- Leverage (placeholder until leverage added)
    ROUND(AVG(cp.if_fielding_alignment)::NUMERIC, 0) AS most_common_if_align,
    ROUND(AVG(cp.delta_run_exp)::NUMERIC, 4)        AS avg_delta_run_exp,
    ROUND(SUM(cp.delta_run_exp)::NUMERIC, 2)        AS total_run_exp_added,

    NOW()                                           AS refreshed_at

FROM raw_statcast.pitch cp
WHERE cp.inning IS NOT NULL
GROUP BY
    cp.game_pk, cp.game_date, cp.game_year,
    cp.inning, cp.inning_topbot
WITH NO DATA;

COMMENT ON MATERIALIZED VIEW mart.mv_game_score_context IS
    'One row per (game_pk, inning, half_inning). Game state context per inning half: '
    'score at start/end, runs scored, PA count, pitch count, baserunner frequencies, '
    'run expectancy delta. Primary use: in-game state features for live prediction models.';

CREATE UNIQUE INDEX IF NOT EXISTS mart_mv_game_score_context_uidx
    ON mart.mv_game_score_context (game_pk, inning, half_inning);


COMMIT;
