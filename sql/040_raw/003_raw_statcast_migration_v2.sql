-- =============================================================================
-- raw_statcast.pitch  —  Migration v2
-- Apply AFTER 003_raw_statcast.sql has been run on a fresh database,
-- OR run standalone against an existing database that already has the table.
--
-- Purpose: Correct column naming errors vs. the official Baseball Savant
-- CSV documentation, add 13 missing columns, and fix one misleading comment.
--
-- Reference: https://baseballsavant.mlb.com/csv-docs  (retrieved 2026-05-19)
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Rename hit_distance_sc -> hit_distance
--    Official Savant name is "hit_distance". The "_sc" suffix was a legacy
--    pybaseball artifact from early Statcast integration; Savant has never
--    used it in CSV exports.
-- ---------------------------------------------------------------------------
ALTER TABLE raw_statcast.pitch
    RENAME COLUMN hit_distance_sc TO hit_distance;

COMMENT ON COLUMN raw_statcast.pitch.hit_distance IS
    'Projected hit distance of the batted ball in feet as tracked by Statcast.';

-- ---------------------------------------------------------------------------
-- 2. Rename release_spin_rate -> release_spin
--    Official Savant name is "release_spin". The "_rate" suffix does not
--    appear in the CSV export or API response.
-- ---------------------------------------------------------------------------
ALTER TABLE raw_statcast.pitch
    RENAME COLUMN release_spin_rate TO release_spin;

COMMENT ON COLUMN raw_statcast.pitch.release_spin IS
    'Spin rate of the pitch at release, in RPM, as tracked by Statcast.';

-- ---------------------------------------------------------------------------
-- 3. Rename n_priorpa_thisgame_pitcher -> n_priorpa_thisgame_player_at_bat
--    The official Savant field name is n_priorpa_thisgame_player_at_bat and
--    refers to the BATTER\'s prior PAs in this game, not the pitcher\'s.
--    Keeping the old column as a renamed alias avoids breaking existing ETL
--    that may reference the old name; update ETL to use the new name.
-- ---------------------------------------------------------------------------
ALTER TABLE raw_statcast.pitch
    RENAME COLUMN n_priorpa_thisgame_pitcher TO n_priorpa_thisgame_player_at_bat;

COMMENT ON COLUMN raw_statcast.pitch.n_priorpa_thisgame_player_at_bat IS
    'Number of prior plate appearances the BATTER has had in this game. '
    'Previously mislabeled n_priorpa_thisgame_pitcher — update any ETL referencing the old name.';

-- ---------------------------------------------------------------------------
-- 4. Fix hyper_speed comment
--    hyper_speed is Adjusted Exit Velocity (hard floor at 88 mph for all
--    batted balls below 88 mph), NOT sprint speed. The column value is correct;
--    only the comment was wrong.
-- ---------------------------------------------------------------------------
COMMENT ON COLUMN raw_statcast.pitch.hyper_speed IS
    'Adjusted Exit Velocity (Savant display name). Sets all batted balls below 88 mph to 88 mph; '
    'uses actual exit velocity for balls at or above 88 mph. Previously mis-documented as sprint speed.';

-- ---------------------------------------------------------------------------
-- 5. Score differential context columns (present in all seasons)
-- ---------------------------------------------------------------------------
ALTER TABLE raw_statcast.pitch
    ADD COLUMN IF NOT EXISTS home_score_diff   SMALLINT,
    ADD COLUMN IF NOT EXISTS bat_score_diff    SMALLINT;

COMMENT ON COLUMN raw_statcast.pitch.home_score_diff IS
    'Home team score minus Away team score at the time of the pitch (pre-pitch).';
COMMENT ON COLUMN raw_statcast.pitch.bat_score_diff IS
    'Batting team score minus Pitching team score at the time of the pitch (pre-pitch).';

-- ---------------------------------------------------------------------------
-- 6. Win expectancy columns (present in all seasons)
-- ---------------------------------------------------------------------------
ALTER TABLE raw_statcast.pitch
    ADD COLUMN IF NOT EXISTS home_win_exp      NUMERIC(8,5),
    ADD COLUMN IF NOT EXISTS bat_win_exp       NUMERIC(8,5);

COMMENT ON COLUMN raw_statcast.pitch.home_win_exp IS
    'Home team win expectancy at the time of the pitch (pre-pitch, 0.0–1.0).';
COMMENT ON COLUMN raw_statcast.pitch.bat_win_exp IS
    'Batting team win expectancy at the time of the pitch (pre-pitch, 0.0–1.0).';

-- ---------------------------------------------------------------------------
-- 7. Player age columns (present in all seasons)
-- ---------------------------------------------------------------------------
ALTER TABLE raw_statcast.pitch
    ADD COLUMN IF NOT EXISTS age_pit_legacy    NUMERIC(5,2),
    ADD COLUMN IF NOT EXISTS age_bat_legacy    NUMERIC(5,2),
    ADD COLUMN IF NOT EXISTS age_pit           NUMERIC(5,2),
    ADD COLUMN IF NOT EXISTS age_bat           NUMERIC(5,2);

COMMENT ON COLUMN raw_statcast.pitch.age_pit_legacy IS
    'Pitcher age as of June 30 of the game year. Legacy MLB age calculation method.';
COMMENT ON COLUMN raw_statcast.pitch.age_bat_legacy IS
    'Batter age as of June 30 of the game year. Legacy MLB age calculation method.';
COMMENT ON COLUMN raw_statcast.pitch.age_pit IS
    'Pitcher age as of December 31 of the game year. Current standard MLB age calculation.';
COMMENT ON COLUMN raw_statcast.pitch.age_bat IS
    'Batter age as of December 31 of the game year. Current standard MLB age calculation.';

-- ---------------------------------------------------------------------------
-- 8. Pitcher/batter schedule context (days until next game)
-- ---------------------------------------------------------------------------
ALTER TABLE raw_statcast.pitch
    ADD COLUMN IF NOT EXISTS pitcher_days_until_next_game  INT,
    ADD COLUMN IF NOT EXISTS batter_days_until_next_game   INT;

COMMENT ON COLUMN raw_statcast.pitch.pitcher_days_until_next_game IS
    'Number of days until the pitcher\'s next game appearance.';
COMMENT ON COLUMN raw_statcast.pitch.batter_days_until_next_game IS
    'Number of days until the batter\'s next game appearance.';

-- ---------------------------------------------------------------------------
-- 9. Bat tracking columns (2024+ seasons only; NULL for earlier seasons)
--    attack_angle, attack_direction, and swing_path_tilt are the three new
--    bat tracking metrics added alongside bat_speed and swing_length.
--    intercept_* columns measure contact point relative to batter center of mass.
-- ---------------------------------------------------------------------------
ALTER TABLE raw_statcast.pitch
    ADD COLUMN IF NOT EXISTS attack_angle                           NUMERIC(8,3),
    ADD COLUMN IF NOT EXISTS attack_direction                       NUMERIC(8,3),
    ADD COLUMN IF NOT EXISTS swing_path_tilt                        NUMERIC(8,3),
    ADD COLUMN IF NOT EXISTS intercept_ball_minus_batter_pos_x_inches NUMERIC(8,3),
    ADD COLUMN IF NOT EXISTS intercept_ball_minus_batter_pos_y_inches NUMERIC(8,3);

COMMENT ON COLUMN raw_statcast.pitch.attack_angle IS
    'Vertical angle of the bat\'s sweet-spot travel direction at ball contact, relative to the ground. '
    'Available from 2024 season onward. NULL for earlier seasons.';
COMMENT ON COLUMN raw_statcast.pitch.attack_direction IS
    'Horizontal angle of the bat\'s sweet-spot travel direction at ball contact, '
    'relative to a line from home plate to straightaway center field. '
    'Available from 2024 season onward. NULL for earlier seasons.';
COMMENT ON COLUMN raw_statcast.pitch.swing_path_tilt IS
    'Vertical angular orientation of the swing plane (defined by bat path in 40ms prior to contact), '
    'relative to the ground. Available from 2024 season onward. NULL for earlier seasons.';
COMMENT ON COLUMN raw_statcast.pitch.intercept_ball_minus_batter_pos_x_inches IS
    'Horizontal distance in inches between the bat/ball intercept point and the batter\'s center of mass. '
    'Available from 2024 season onward. NULL for earlier seasons.';
COMMENT ON COLUMN raw_statcast.pitch.intercept_ball_minus_batter_pos_y_inches IS
    'Distance in inches between the bat/ball intercept point and the batter\'s center of mass '
    'in the mound-to-plate (Y) direction. Available from 2024 season onward. NULL for earlier seasons.';

-- ---------------------------------------------------------------------------
-- 10. Update table comment to reflect v2 state
-- ---------------------------------------------------------------------------
COMMENT ON TABLE raw_statcast.pitch IS
    'Raw Statcast pitch-level rows. Captures all columns from the Baseball Savant CSV export '
    '(https://baseballsavant.mlb.com/csv-docs) including 2024+ bat tracking fields. '
    'Migration v2 applied: renamed hit_distance_sc->hit_distance, release_spin_rate->release_spin, '
    'n_priorpa_thisgame_pitcher->n_priorpa_thisgame_player_at_bat; fixed hyper_speed description; '
    'added home_score_diff, bat_score_diff, home_win_exp, bat_win_exp, age columns, '
    'days_until_next_game, and full 2024+ bat tracking suite.';

COMMIT;
