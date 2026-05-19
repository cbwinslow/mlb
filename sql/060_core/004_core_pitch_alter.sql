-- =============================================================================
-- Step 7: Expand core.pitch to mirror raw_statcast.pitch
--         Fix updated_at triggers on ALL core entity tables
--         Add missing unique indexes on core.player
--
-- Diff result: 110 raw_statcast.pitch columns vs 36 covered in core.pitch
-- Result: 74 columns missing from core.pitch — all added below.
--
-- Apply after:
--   sql/060_core/001_core_entities.sql
--   sql/060_core/002_core_gameplay.sql
--   sql/060_core/003_core_relationships.sql
--   sql/050_staging/004_identity_trigger_and_indexes.sql (Step 6)
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- PART A: updated_at triggers on core entity tables
--
-- Anomaly: core.player, core.team, core.venue, and core.game all carry
-- updated_at columns but have no BEFORE UPDATE trigger to maintain them.
-- Identical bug to the one fixed in staging (Step 6, Part A).
-- We reuse the stg.set_updated_at() function created in Step 6.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE TRIGGER trg_core_player_updated_at
    BEFORE UPDATE ON core.player
    FOR EACH ROW
    EXECUTE FUNCTION stg.set_updated_at();

CREATE OR REPLACE TRIGGER trg_core_team_updated_at
    BEFORE UPDATE ON core.team
    FOR EACH ROW
    EXECUTE FUNCTION stg.set_updated_at();

CREATE OR REPLACE TRIGGER trg_core_venue_updated_at
    BEFORE UPDATE ON core.venue
    FOR EACH ROW
    EXECUTE FUNCTION stg.set_updated_at();

CREATE OR REPLACE TRIGGER trg_core_game_updated_at
    BEFORE UPDATE ON core.game
    FOR EACH ROW
    EXECUTE FUNCTION stg.set_updated_at();


-- ---------------------------------------------------------------------------
-- PART B: Missing unique indexes on core.player
--
-- Anomaly: core.player has unique indexes for mlbam and retrosheet IDs
-- (006_core_indexes.sql) but NOT for bbref or fangraphs — same gap as
-- stg.player_identity before Step 6.
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS core_player_bbref_uidx
    ON core.player (bbref_player_id)
    WHERE bbref_player_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS core_player_fangraphs_uidx
    ON core.player (fangraphs_player_id)
    WHERE fangraphs_player_id IS NOT NULL;


-- ---------------------------------------------------------------------------
-- PART C: Expand core.pitch — 74 missing columns
--
-- Design principle: core.pitch is the conformed fact for every Statcast pitch.
-- It must hold ALL columns from raw_statcast.pitch so that downstream views,
-- marts, and ML features never need to join back to raw.
-- NULLs are fine for historical rows predating a metric (e.g. bat_speed
-- only exists 2024+). PostgreSQL stores NULLs in a compact null bitmap.
-- ---------------------------------------------------------------------------

-- GROUP 1: Raw source natural keys
-- core.pitch already has game_id FK (BIGINT to core.game). These are the
-- original string keys from Statcast, preserved for direct debugging and
-- cross-source joins without going through the bridge tables.
ALTER TABLE core.pitch
    ADD COLUMN IF NOT EXISTS raw_game_pk           BIGINT,
    ADD COLUMN IF NOT EXISTS raw_game_id           TEXT,      -- Retrosheet-style e.g. TEX202304060
    ADD COLUMN IF NOT EXISTS game_date             DATE,
    ADD COLUMN IF NOT EXISTS game_year             INT,
    ADD COLUMN IF NOT EXISTS game_type             TEXT,
    ADD COLUMN IF NOT EXISTS at_bat_number         INT;       -- Statcast at_bat_number (= plate_appearance_number)

COMMENT ON COLUMN core.pitch.raw_game_pk   IS 'Raw MLBAM gamePk from Statcast, for direct debugging without bridging.';
COMMENT ON COLUMN core.pitch.raw_game_id   IS 'Retrosheet-style game ID from Statcast row (e.g. TEX202304060).';
COMMENT ON COLUMN core.pitch.game_date     IS 'Game date copied from Statcast row. Should match core.game.game_date.';
COMMENT ON COLUMN core.pitch.game_year     IS 'Season year. Denormalized for partition pruning and quick season filters.';
COMMENT ON COLUMN core.pitch.game_type     IS 'Game type code from Statcast: R=regular, P=postseason, S=spring training.';
COMMENT ON COLUMN core.pitch.at_bat_number IS 'Statcast at_bat_number (same concept as plate_appearance_number, kept for raw-matching).';


-- GROUP 2: Batter / pitcher raw MLBAM IDs
-- core.pitch already has batter_id and pitcher_id as FKs to core.player.
-- These raw columns preserve the original MLBAM IDs for rows where the
-- identity bridge is still pending (confidence_score=0).
ALTER TABLE core.pitch
    ADD COLUMN IF NOT EXISTS raw_batter_mlbam      BIGINT,
    ADD COLUMN IF NOT EXISTS raw_pitcher_mlbam     BIGINT,
    ADD COLUMN IF NOT EXISTS player_name           TEXT,
    ADD COLUMN IF NOT EXISTS stand                 TEXT,      -- batter handedness: R/L/S
    ADD COLUMN IF NOT EXISTS p_throws              TEXT;      -- pitcher handedness: R/L

COMMENT ON COLUMN core.pitch.raw_batter_mlbam  IS 'Raw Statcast batter MLBAM ID, preserved when identity bridge is pending.';
COMMENT ON COLUMN core.pitch.raw_pitcher_mlbam IS 'Raw Statcast pitcher MLBAM ID, preserved when identity bridge is pending.';
COMMENT ON COLUMN core.pitch.player_name       IS 'Player name string from Statcast row. Not normalized — for display and search only.';
COMMENT ON COLUMN core.pitch.stand             IS 'Batter handedness at this plate appearance: R=right, L=left, S=switch.';
COMMENT ON COLUMN core.pitch.p_throws          IS 'Pitcher handedness: R=right, L=left.';


-- GROUP 3: Full defensive alignment (fielder/umpire MLBAM IDs)
-- Statcast carries the entire 9-man defense + umpire on every pitch.
ALTER TABLE core.pitch
    ADD COLUMN IF NOT EXISTS fielder_2             BIGINT,    -- catcher
    ADD COLUMN IF NOT EXISTS fielder_2_1           BIGINT,    -- backup catcher (alt slot)
    ADD COLUMN IF NOT EXISTS pitcher_1             BIGINT,    -- relief pitcher tracking slot
    ADD COLUMN IF NOT EXISTS fielder_3             BIGINT,    -- 1B
    ADD COLUMN IF NOT EXISTS fielder_4             BIGINT,    -- 2B
    ADD COLUMN IF NOT EXISTS fielder_5             BIGINT,    -- 3B
    ADD COLUMN IF NOT EXISTS fielder_6             BIGINT,    -- SS
    ADD COLUMN IF NOT EXISTS fielder_7             BIGINT,    -- LF
    ADD COLUMN IF NOT EXISTS fielder_8             BIGINT,    -- CF
    ADD COLUMN IF NOT EXISTS fielder_9             BIGINT,    -- RF
    ADD COLUMN IF NOT EXISTS umpire                BIGINT;    -- home plate umpire MLBAM ID

COMMENT ON COLUMN core.pitch.fielder_2   IS 'Catcher MLBAM player ID at time of pitch.';
COMMENT ON COLUMN core.pitch.fielder_3   IS '1B MLBAM player ID at time of pitch.';
COMMENT ON COLUMN core.pitch.fielder_4   IS '2B MLBAM player ID at time of pitch.';
COMMENT ON COLUMN core.pitch.fielder_5   IS '3B MLBAM player ID at time of pitch.';
COMMENT ON COLUMN core.pitch.fielder_6   IS 'SS MLBAM player ID at time of pitch.';
COMMENT ON COLUMN core.pitch.fielder_7   IS 'LF MLBAM player ID at time of pitch.';
COMMENT ON COLUMN core.pitch.fielder_8   IS 'CF MLBAM player ID at time of pitch.';
COMMENT ON COLUMN core.pitch.fielder_9   IS 'RF MLBAM player ID at time of pitch.';
COMMENT ON COLUMN core.pitch.umpire      IS 'Home plate umpire MLBAM ID at time of pitch.';


-- GROUP 4: Game / PA context
ALTER TABLE core.pitch
    ADD COLUMN IF NOT EXISTS home_team             TEXT,      -- team abbreviation
    ADD COLUMN IF NOT EXISTS away_team             TEXT,
    ADD COLUMN IF NOT EXISTS on_1b                 BIGINT,    -- runner on 1B MLBAM ID (NULL if empty)
    ADD COLUMN IF NOT EXISTS on_2b                 BIGINT,
    ADD COLUMN IF NOT EXISTS on_3b                 BIGINT,
    ADD COLUMN IF NOT EXISTS bb_type               TEXT,      -- batted ball type: ground_ball/fly_ball/line_drive/popup
    ADD COLUMN IF NOT EXISTS hit_location          SMALLINT,  -- fielder position where ball was hit
    ADD COLUMN IF NOT EXISTS if_fielding_alignment TEXT,      -- infield alignment code
    ADD COLUMN IF NOT EXISTS of_fielding_alignment TEXT,      -- outfield alignment code
    ADD COLUMN IF NOT EXISTS type                  TEXT,      -- S=strike, B=ball, X=in-play
    ADD COLUMN IF NOT EXISTS des                   TEXT;      -- full pitch/event description text

COMMENT ON COLUMN core.pitch.on_1b IS 'MLBAM player ID of runner on 1B at start of pitch. NULL if base empty.';
COMMENT ON COLUMN core.pitch.on_2b IS 'MLBAM player ID of runner on 2B at start of pitch. NULL if base empty.';
COMMENT ON COLUMN core.pitch.on_3b IS 'MLBAM player ID of runner on 3B at start of pitch. NULL if base empty.';
COMMENT ON COLUMN core.pitch.bb_type IS 'Batted ball type: ground_ball, fly_ball, line_drive, popup. NULL for non-contact pitches.';
COMMENT ON COLUMN core.pitch.hit_location IS 'Defensive position number of the fielder who fielded the ball (1-9).';
COMMENT ON COLUMN core.pitch.if_fielding_alignment IS 'Infield defensive alignment: Standard, Shift, Strategic, etc.';
COMMENT ON COLUMN core.pitch.of_fielding_alignment IS 'Outfield defensive alignment: Standard, Strategic, etc.';
COMMENT ON COLUMN core.pitch.type IS 'Pitch result type: B=ball, S=strike (any), X=in play.';
COMMENT ON COLUMN core.pitch.des  IS 'Full natural language description of pitch or play event from Statcast.';


-- GROUP 5: Score context (pre-pitch and post-PA)
ALTER TABLE core.pitch
    ADD COLUMN IF NOT EXISTS home_score            INT,       -- home score at START of PA
    ADD COLUMN IF NOT EXISTS away_score            INT,       -- away score at START of PA
    ADD COLUMN IF NOT EXISTS bat_score             INT,       -- batting team score at pitch
    ADD COLUMN IF NOT EXISTS fld_score             INT,       -- fielding team score at pitch
    ADD COLUMN IF NOT EXISTS home_score_ct         INT,       -- home score at moment of PITCH
    ADD COLUMN IF NOT EXISTS away_score_ct         INT,       -- away score at moment of PITCH
    ADD COLUMN IF NOT EXISTS post_home_score       INT,       -- home score after PA resolves
    ADD COLUMN IF NOT EXISTS post_away_score       INT,
    ADD COLUMN IF NOT EXISTS post_bat_score        INT,
    ADD COLUMN IF NOT EXISTS post_fld_score        INT;

COMMENT ON COLUMN core.pitch.home_score_ct IS 'Home score at the moment this pitch is thrown (differs from post_home_score which reflects PA outcome).';
COMMENT ON COLUMN core.pitch.away_score_ct IS 'Away score at the moment this pitch is thrown.';
COMMENT ON COLUMN core.pitch.post_home_score IS 'Home team score after the plate appearance resolves.';
COMMENT ON COLUMN core.pitch.post_away_score IS 'Away team score after the plate appearance resolves.';


-- GROUP 6: Release point 3D coordinates + arm angle
ALTER TABLE core.pitch
    ADD COLUMN IF NOT EXISTS release_pos_x         NUMERIC(10,5),  -- horizontal release point (ft, catcher view)
    ADD COLUMN IF NOT EXISTS release_pos_y         NUMERIC(10,5),  -- distance from rubber at release (ft)
    ADD COLUMN IF NOT EXISTS release_pos_z         NUMERIC(10,5),  -- vertical release height (ft)
    ADD COLUMN IF NOT EXISTS arm_angle             NUMERIC(8,3);   -- pitcher arm slot at release (degrees)

COMMENT ON COLUMN core.pitch.release_pos_x IS 'Horizontal release point in feet, from catcher perspective. Left is negative.';
COMMENT ON COLUMN core.pitch.release_pos_y IS 'Distance from rubber at point of release in feet.';
COMMENT ON COLUMN core.pitch.release_pos_z IS 'Vertical height of release point in feet above ground.';
COMMENT ON COLUMN core.pitch.arm_angle     IS 'Pitcher arm slot angle at release in degrees (0=sidearm, 90=overhand).';


-- GROUP 7: API-derived break metrics
ALTER TABLE core.pitch
    ADD COLUMN IF NOT EXISTS api_break_z_with_gravity  NUMERIC(10,5),
    ADD COLUMN IF NOT EXISTS api_break_x_arm           NUMERIC(10,5),
    ADD COLUMN IF NOT EXISTS api_break_x_batter_in     NUMERIC(10,5);

COMMENT ON COLUMN core.pitch.api_break_z_with_gravity IS 'Vertical pitch break in inches including gravity effect, as reported by the Statcast API.';
COMMENT ON COLUMN core.pitch.api_break_x_arm          IS 'Horizontal break in inches from arm-side perspective.';
COMMENT ON COLUMN core.pitch.api_break_x_batter_in    IS 'Horizontal break in inches from batter-in perspective.';


-- GROUP 8: Bat tracking (2024+) + sprint speed
ALTER TABLE core.pitch
    ADD COLUMN IF NOT EXISTS bat_speed             NUMERIC(8,3),  -- mph at contact
    ADD COLUMN IF NOT EXISTS swing_length          NUMERIC(8,3),  -- feet
    ADD COLUMN IF NOT EXISTS hyper_speed           NUMERIC(8,3);  -- baserunner sprint speed on event

COMMENT ON COLUMN core.pitch.bat_speed    IS 'Bat speed at contact in mph. Available 2024 season onward. NULL for pre-2024 rows.';
COMMENT ON COLUMN core.pitch.swing_length IS 'Swing path length in feet. Available 2024 season onward. NULL for pre-2024 rows.';
COMMENT ON COLUMN core.pitch.hyper_speed  IS 'Baserunner sprint speed on batted ball events (Statcast Hyper Speed). NULL when not applicable.';


-- GROUP 9: Full expected outcome suite
-- core.pitch previously had estimated_ba and estimated_woba but was missing
-- xSLG, wOBA value/denom, BABIP value, and ISO value.
ALTER TABLE core.pitch
    ADD COLUMN IF NOT EXISTS estimated_slg_using_speedangle  NUMERIC(8,5),
    ADD COLUMN IF NOT EXISTS woba_value                      NUMERIC(8,5),
    ADD COLUMN IF NOT EXISTS woba_denom                      NUMERIC(8,5),
    ADD COLUMN IF NOT EXISTS babip_value                     NUMERIC(8,5),
    ADD COLUMN IF NOT EXISTS iso_value                       NUMERIC(8,5),
    ADD COLUMN IF NOT EXISTS delta_pitcher_run_exp           NUMERIC(10,5);

COMMENT ON COLUMN core.pitch.estimated_slg_using_speedangle IS 'Expected SLG (xSLG) from launch speed/angle model. NULL for non-contact pitches.';
COMMENT ON COLUMN core.pitch.woba_value        IS 'Linear weights wOBA value assigned to this PA outcome.';
COMMENT ON COLUMN core.pitch.woba_denom        IS 'wOBA denominator flag (1 if PA counts toward wOBA, 0 otherwise).';
COMMENT ON COLUMN core.pitch.babip_value       IS 'BABIP numerator value for this PA (1=BABIP hit, 0=out, NULL=not applicable).';
COMMENT ON COLUMN core.pitch.iso_value         IS 'Isolated power value assigned to this PA outcome.';
COMMENT ON COLUMN core.pitch.delta_pitcher_run_exp IS 'Pitcher-perspective run expectancy delta (sign-flipped from batter delta).';


-- GROUP 10: Pitcher/batter context (fatigue, lineup cycling, rest)
ALTER TABLE core.pitch
    ADD COLUMN IF NOT EXISTS n_thruorder_pitcher         INT,
    ADD COLUMN IF NOT EXISTS n_priorpa_thisgame_pitcher  INT,
    ADD COLUMN IF NOT EXISTS pitcher_days_since_prev_game INT,
    ADD COLUMN IF NOT EXISTS batter_days_since_prev_game  INT;

COMMENT ON COLUMN core.pitch.n_thruorder_pitcher         IS 'Number of times pitcher has been through the lineup at this pitch.';
COMMENT ON COLUMN core.pitch.n_priorpa_thisgame_pitcher  IS 'Prior PAs this batter has seen this pitcher in the current game.';
COMMENT ON COLUMN core.pitch.pitcher_days_since_prev_game IS 'Rest days for pitcher since previous game appearance.';
COMMENT ON COLUMN core.pitch.batter_days_since_prev_game  IS 'Rest days for batter since previous game appearance.';


-- GROUP 11: Batted ball hit coordinates and exit speed angle tier
ALTER TABLE core.pitch
    ADD COLUMN IF NOT EXISTS hc_x                  NUMERIC(10,5),  -- hit coordinate X (pixels, Statcast graphic system)
    ADD COLUMN IF NOT EXISTS hc_y                  NUMERIC(10,5),  -- hit coordinate Y
    ADD COLUMN IF NOT EXISTS launch_speed_angle    SMALLINT;       -- 1-6 speed/angle outcome tier

COMMENT ON COLUMN core.pitch.hc_x IS 'Hit coordinate X in Statcast graphic pixel space (origin = home plate).';
COMMENT ON COLUMN core.pitch.hc_y IS 'Hit coordinate Y in Statcast graphic pixel space.';
COMMENT ON COLUMN core.pitch.launch_speed_angle IS 'Exit velocity / launch angle outcome tier (1=weak, 6=barrel). NULL for non-contact.';


-- GROUP 12: Deprecated / legacy columns
-- Retained for historical completeness on pre-PITCHf/x rows.
-- All nullable; do not use in new analysis.
ALTER TABLE core.pitch
    ADD COLUMN IF NOT EXISTS sv_id                     TEXT,
    ADD COLUMN IF NOT EXISTS spin_dir                  NUMERIC(10,5),
    ADD COLUMN IF NOT EXISTS spin_rate_deprecated      NUMERIC(10,5),
    ADD COLUMN IF NOT EXISTS break_angle_deprecated    NUMERIC(10,5),
    ADD COLUMN IF NOT EXISTS break_length_deprecated   NUMERIC(10,5),
    ADD COLUMN IF NOT EXISTS tfs_deprecated            TEXT,
    ADD COLUMN IF NOT EXISTS tfs_zulu_deprecated       TIMESTAMPTZ;

COMMENT ON COLUMN core.pitch.sv_id                  IS 'Legacy PITCHf/x pitch identifier. Deprecated — preserved for pre-2015 historical joins.';
COMMENT ON COLUMN core.pitch.spin_dir               IS 'Deprecated spin direction from original PITCHf/x system. Use spin_axis instead.';
COMMENT ON COLUMN core.pitch.spin_rate_deprecated   IS 'Deprecated spin rate field from PITCHf/x era. Use release_spin_rate instead.';
COMMENT ON COLUMN core.pitch.break_angle_deprecated IS 'Deprecated break angle from PITCHf/x. Use pfx_x / api_break_x_arm instead.';
COMMENT ON COLUMN core.pitch.break_length_deprecated IS 'Deprecated break length from PITCHf/x. Use pfx_z / api_break_z_with_gravity instead.';
COMMENT ON COLUMN core.pitch.tfs_deprecated         IS 'Deprecated timestamp field from PITCHf/x system.';
COMMENT ON COLUMN core.pitch.tfs_zulu_deprecated    IS 'Deprecated UTC timestamp from PITCHf/x system.';


-- ---------------------------------------------------------------------------
-- PART D: New indexes for frequently-queried new columns
-- ---------------------------------------------------------------------------

-- Bat tracking lookup (2024+ queries will filter WHERE bat_speed IS NOT NULL)
CREATE INDEX IF NOT EXISTS core_pitch_bat_tracking_idx
    ON core.pitch (game_year, bat_speed)
    WHERE bat_speed IS NOT NULL;

-- Release position / arm angle for pitcher biomechanics queries
CREATE INDEX IF NOT EXISTS core_pitch_arm_angle_idx
    ON core.pitch (pitcher_id, arm_angle)
    WHERE arm_angle IS NOT NULL;

-- Hit coordinates for spray chart queries
CREATE INDEX IF NOT EXISTS core_pitch_hit_coords_idx
    ON core.pitch (hc_x, hc_y)
    WHERE hc_x IS NOT NULL AND hc_y IS NOT NULL;

-- Base state for run expectancy analysis
CREATE INDEX IF NOT EXISTS core_pitch_base_state_idx
    ON core.pitch (outs_before, on_1b, on_2b, on_3b)
    WHERE on_1b IS NOT NULL OR on_2b IS NOT NULL OR on_3b IS NOT NULL;

-- Fielding alignment for shift analysis
CREATE INDEX IF NOT EXISTS core_pitch_alignment_idx
    ON core.pitch (if_fielding_alignment, of_fielding_alignment)
    WHERE if_fielding_alignment IS NOT NULL;

-- Pitcher fatigue / order cycling
CREATE INDEX IF NOT EXISTS core_pitch_thruorder_idx
    ON core.pitch (pitcher_id, n_thruorder_pitcher)
    WHERE n_thruorder_pitcher IS NOT NULL;


-- ---------------------------------------------------------------------------
-- PART E: Update table comment to reflect full scope
-- ---------------------------------------------------------------------------
COMMENT ON TABLE core.pitch IS
    'Canonical pitch fact mirroring the full raw_statcast.pitch column set. '
    'Holds all 110+ Statcast fields including 2024+ bat tracking (bat_speed, swing_length), '
    'API break metrics, full defensive alignment, score context, expected outcome suite, '
    'pitcher/batter fatigue context, and deprecated PITCHf/x legacy columns. '
    'NULLs are used for metrics not available in a given season or game type. '
    'Linked to core.game, core.player (batter/pitcher FKs), and core.plate_appearance.';

COMMIT;
