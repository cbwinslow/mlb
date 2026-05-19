BEGIN;

-- ===========================================================================
-- raw_chadwick  — Output from Chadwick Bureau cwevent / cwgame / cwsub tools
-- Reference: https://chadwick-bureau.com/the-tools/
-- Field spec: cwevent -f 0-95 (all fields, version 0.10.x)
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- cwevent_file — metadata for each cwevent extraction run
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_chadwick.cwevent_file (
    cwevent_file_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    ingest_run_id UUID
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    event_file_id UUID
        REFERENCES raw_retrosheet.event_file(event_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT,
    tool_version TEXT,
    field_spec TEXT NOT NULL,
    command_text TEXT,
    output_file_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_chadwick.cwevent_file IS
    'Metadata for a cwevent extraction run and output artifact.';

-- ---------------------------------------------------------------------------
-- cwevent — full 96-field play-by-play event table
-- Field numbers follow cwevent -f 0-95 column order.
-- All 96 fields are typed; no JSONB catch-all.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_chadwick.cwevent (
    cwevent_row_id      BIGSERIAL PRIMARY KEY,
    cwevent_file_id     UUID NOT NULL
        REFERENCES raw_chadwick.cwevent_file(cwevent_file_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    -- -----------------------------------------------------------------------
    -- FIELD GROUP 1: Game / event identification  (fields 0-5)
    -- -----------------------------------------------------------------------
    game_id             TEXT    NOT NULL,   -- f0  Retrosheet game ID  (e.g. ANA202304050)
    away_team_id        TEXT,               -- f1  Visiting team ID
    inn_ct              SMALLINT,           -- f2  Inning number
    bat_home_id         SMALLINT,           -- f3  1 = home team batting, 0 = visitor
    outs_ct             SMALLINT,           -- f4  Outs at start of play (0-2)
    event_id            INT     NOT NULL,   -- f5  Sequential event number within game

    -- -----------------------------------------------------------------------
    -- FIELD GROUP 2: Lineup state (fields 6-9)
    -- -----------------------------------------------------------------------
    bat_lineup_id       SMALLINT,           -- f6  Batter lineup position (1-9)
    fld_cd              SMALLINT,           -- f7  Fielding position of batter (11 = DH, 12 = PH, 13 = PR)
    bat_id              TEXT,               -- f8  Batter Retrosheet player ID
    bat_hand_cd         CHAR(1),            -- f9  Batter handedness: L/R/B/?

    -- -----------------------------------------------------------------------
    -- FIELD GROUP 3: Pitcher state (fields 10-13)
    -- -----------------------------------------------------------------------
    pit_id              TEXT,               -- f10 Pitcher Retrosheet player ID
    pit_hand_cd         CHAR(1),            -- f11 Pitcher handedness: L/R/B/?
    pos2_fld_id         TEXT,               -- f12 Catcher player ID (position 2)
    pos3_fld_id         TEXT,               -- f13 First baseman player ID

    -- -----------------------------------------------------------------------
    -- FIELD GROUP 4: Remaining fielder IDs (fields 14-19)
    -- -----------------------------------------------------------------------
    pos4_fld_id         TEXT,               -- f14 Second baseman
    pos5_fld_id         TEXT,               -- f15 Third baseman
    pos6_fld_id         TEXT,               -- f16 Shortstop
    pos7_fld_id         TEXT,               -- f17 Left fielder
    pos8_fld_id         TEXT,               -- f18 Center fielder
    pos9_fld_id         TEXT,               -- f19 Right fielder

    -- -----------------------------------------------------------------------
    -- FIELD GROUP 5: Responsible batter / pitcher (fields 20-23)
    -- Differs from bat_id/pit_id on inherited-runner situations
    -- -----------------------------------------------------------------------
    res_bat_id          TEXT,               -- f20 Responsible batter ID
    res_bat_hand_cd     CHAR(1),            -- f21 Responsible batter handedness
    res_pit_id          TEXT,               -- f22 Responsible pitcher ID
    res_pit_hand_cd     CHAR(1),            -- f23 Responsible pitcher handedness

    -- -----------------------------------------------------------------------
    -- FIELD GROUP 6: Base runners at start of play (fields 24-26)
    -- -----------------------------------------------------------------------
    first_runner_id     TEXT,               -- f24 Runner on 1B (NULL if empty)
    second_runner_id    TEXT,               -- f25 Runner on 2B
    third_runner_id     TEXT,               -- f26 Runner on 3B

    -- -----------------------------------------------------------------------
    -- FIELD GROUP 7: Event description & count (fields 27-35)
    -- -----------------------------------------------------------------------
    event_tx            TEXT,               -- f27 Event text (e.g. "S7/G5")
    leadoff_fl          BOOLEAN,            -- f28 TRUE if batter led off inning
    ph_fl               BOOLEAN,            -- f29 TRUE if batter was pinch hitter
    balls_ct            SMALLINT,           -- f30 Balls at time of event
    strikes_ct          SMALLINT,           -- f31 Strikes at time of event
    pitch_seq_tx        TEXT,               -- f32 Pitch sequence string (BCFHIKLMNOPQRSTUVX...)
    event_cd            SMALLINT,           -- f33 Event code (0-23; see Retrosheet codes)
    battedball_cd       CHAR(1),            -- f34 Batted ball type: G/L/F/P/?
    bunt_fl             BOOLEAN,            -- f35 TRUE if bunt attempt

    -- -----------------------------------------------------------------------
    -- FIELD GROUP 8: Foul / hit details (fields 36-40)
    -- -----------------------------------------------------------------------
    foul_fl             BOOLEAN,            -- f36 TRUE if foul ball
    hit_val             SMALLINT,           -- f37 Hit value: 0=no hit, 1-4=single-HR
    sh_fl               BOOLEAN,            -- f38 Sacrifice hit flag
    sf_fl               BOOLEAN,            -- f39 Sacrifice fly flag
    hit_location_tx     TEXT,               -- f40 Hit location code (e.g. "78XD", "25F")

    -- -----------------------------------------------------------------------
    -- FIELD GROUP 9: Special play flags (fields 41-45)
    -- -----------------------------------------------------------------------
    num_err_ct          SMALLINT,           -- f41 Number of errors on play
    wp_fl               BOOLEAN,            -- f42 Wild pitch flag
    pb_fl               BOOLEAN,            -- f43 Passed ball flag
    ab_fl               BOOLEAN,            -- f44 At-bat flag
    h_fl                BOOLEAN,            -- f45 Hit flag (base hit)

    -- -----------------------------------------------------------------------
    -- FIELD GROUP 10: Batter outcome (fields 46-50)
    -- -----------------------------------------------------------------------
    sh_ball_fl          BOOLEAN,            -- f46 Intentional walk flag (alt source)
    ibb_fl              BOOLEAN,            -- f47 Intentional base on balls flag
    gdp_fl              BOOLEAN,            -- f48 Grounded into double play flag
    xi_fl               BOOLEAN,            -- f49 Catcher's interference flag (batter reached)
    bball_fl            BOOLEAN,            -- f50 Base on balls flag

    -- -----------------------------------------------------------------------
    -- FIELD GROUP 11: Play-level accumulators (fields 51-56)
    -- -----------------------------------------------------------------------
    event_runs_ct       SMALLINT,           -- f51 Runs scored on this event
    bat_dest_id         SMALLINT,           -- f52 Batter destination base (0-6; 6=scored)
    run1_dest_id        SMALLINT,           -- f53 Runner from 1B destination (0-6)
    run2_dest_id        SMALLINT,           -- f54 Runner from 2B destination
    run3_dest_id        SMALLINT,           -- f55 Runner from 3B destination
    event_outs_ct       SMALLINT,           -- f56 Outs made on this event

    -- -----------------------------------------------------------------------
    -- FIELD GROUP 12: Runner play text (fields 57-60)
    -- Describes how each base runner advanced / was put out
    -- -----------------------------------------------------------------------
    bat_play_tx         TEXT,               -- f57 Batter advance play text
    run1_play_tx        TEXT,               -- f58 Runner from 1B play text
    run2_play_tx        TEXT,               -- f59 Runner from 2B play text
    run3_play_tx        TEXT,               -- f60 Runner from 3B play text

    -- -----------------------------------------------------------------------
    -- FIELD GROUP 13: Stolen base / caught stealing / pickoff flags (fields 61-69)
    -- -----------------------------------------------------------------------
    sb1_fl              BOOLEAN,            -- f61 Stolen base of 2B flag
    sb2_fl              BOOLEAN,            -- f62 Stolen base of 3B flag
    sb3_fl              BOOLEAN,            -- f63 Stolen base of home flag
    cs1_fl              BOOLEAN,            -- f64 Caught stealing 2B flag
    cs2_fl              BOOLEAN,            -- f65 Caught stealing 3B flag
    cs3_fl              BOOLEAN,            -- f66 Caught stealing home flag
    po1_fl              BOOLEAN,            -- f67 Pickoff 1B flag
    po2_fl              BOOLEAN,            -- f68 Pickoff 2B flag
    po3_fl              BOOLEAN,            -- f69 Pickoff 3B flag

    -- -----------------------------------------------------------------------
    -- FIELD GROUP 14: Fielder responsible for putouts (fields 70-72)
    -- -----------------------------------------------------------------------
    resp_fielder1_id    TEXT,               -- f70 Fielder making first putout
    resp_fielder2_id    TEXT,               -- f71 Fielder making second putout
    resp_fielder3_id    TEXT,               -- f72 Fielder making third putout

    -- -----------------------------------------------------------------------
    -- FIELD GROUP 15: Fielder assist & error credits (fields 73-81)
    -- -----------------------------------------------------------------------
    resp_fielder_a1_id  TEXT,               -- f73 Fielder with assist 1
    resp_fielder_a2_id  TEXT,               -- f74 Fielder with assist 2
    resp_fielder_a3_id  TEXT,               -- f75 Fielder with assist 3
    resp_fielder_a4_id  TEXT,               -- f76 Fielder with assist 4
    resp_fielder_a5_id  TEXT,               -- f77 Fielder with assist 5
    resp_fielder_e1_id  TEXT,               -- f78 Fielder with error 1
    resp_fielder_e2_id  TEXT,               -- f79 Fielder with error 2
    resp_fielder_e3_id  TEXT,               -- f80 Fielder with error 3
    resp_fielder_po1_id TEXT,               -- f81 Fielder putout on pickoff play 1

    -- -----------------------------------------------------------------------
    -- FIELD GROUP 16: Pickoff assist / error (fields 82-83)
    -- -----------------------------------------------------------------------
    resp_fielder_po2_id TEXT,               -- f82 Fielder putout on pickoff play 2
    resp_fielder_po3_id TEXT,               -- f83 Fielder putout on pickoff play 3

    -- -----------------------------------------------------------------------
    -- FIELD GROUP 17: Running linescore accumulators (fields 84-89)
    -- Cumulative totals as of end of this play
    -- -----------------------------------------------------------------------
    away_score_ct       SMALLINT,           -- f84 Visitor score (end of play)
    home_score_ct       SMALLINT,           -- f85 Home score (end of play)
    away_hits_ct        SMALLINT,           -- f86 Visitor hit count
    home_hits_ct        SMALLINT,           -- f87 Home hit count
    away_err_ct         SMALLINT,           -- f88 Visitor error count
    home_err_ct         SMALLINT,           -- f89 Home error count

    -- -----------------------------------------------------------------------
    -- FIELD GROUP 18: Lead runner flags (fields 90-92)
    -- -----------------------------------------------------------------------
    away_score_fl       BOOLEAN,            -- f90 Visitor scored on play
    home_score_fl       BOOLEAN,            -- f91 Home scored on play
    bunt_fc_fl          BOOLEAN,            -- f92 Bunt fielder's choice flag

    -- -----------------------------------------------------------------------
    -- FIELD GROUP 19: Miscellaneous PA flags (fields 93-95)
    -- -----------------------------------------------------------------------
    pa_ball_ct          SMALLINT,           -- f93 Balls in this PA as of event
    pa_strike_ct        SMALLINT,           -- f94 Strikes in this PA as of event
    pa_truncated_fl     BOOLEAN,            -- f95 PA truncated (game ended mid-PA)

    CONSTRAINT raw_chadwick_cwevent_unique
        UNIQUE (cwevent_file_id, game_id, event_id)
);

COMMENT ON TABLE raw_chadwick.cwevent IS
    'Full 96-field play-by-play event rows from Chadwick cwevent -f 0-95 output. '
    'One row per plate appearance / play event. Covers all Retrosheet event files (1913-present). '
    'Field groups: identification, lineup state, fielders, responsible bat/pit, baserunners, '
    'event description, hit/bunt/foul flags, base outcomes, runner advances, '
    'SB/CS/PO flags, fielder credits, linescore accumulators, PA state.';


-- ===========================================================================
-- cwgame — game-level summary (preserved from original)
-- ===========================================================================

CREATE TABLE IF NOT EXISTS raw_chadwick.cwgame_file (
    cwgame_file_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    ingest_run_id UUID
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    event_file_id UUID
        REFERENCES raw_retrosheet.event_file(event_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT,
    tool_version TEXT,
    field_spec TEXT NOT NULL,
    command_text TEXT,
    output_file_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_chadwick.cwgame_file IS
    'Metadata for a cwgame extraction run and output artifact.';

CREATE TABLE IF NOT EXISTS raw_chadwick.cwgame (
    cwgame_row_id BIGSERIAL PRIMARY KEY,
    cwgame_file_id UUID NOT NULL
        REFERENCES raw_chadwick.cwgame_file(cwgame_file_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    game_id TEXT NOT NULL,
    game_date DATE,
    game_number SMALLINT,
    weekday TEXT,
    visit_team TEXT,
    home_team TEXT,
    day_night TEXT,
    start_time TEXT,
    dh_used_fl BOOLEAN,
    tiebreakbase_fl BOOLEAN,
    attendance INT,
    park_id TEXT,
    temp INT,
    winddir TEXT,
    windspeed INT,
    fieldcond TEXT,
    precip TEXT,
    sky TEXT,
    time_of_game INT,
    raw_game_row JSONB,
    CONSTRAINT raw_chadwick_cwgame_unique
        UNIQUE (cwgame_file_id, game_id)
);

COMMENT ON TABLE raw_chadwick.cwgame IS
    'Structured game summary rows from Chadwick cwgame output.';


-- ===========================================================================
-- cwsub — substitution events (preserved from original)
-- ===========================================================================

CREATE TABLE IF NOT EXISTS raw_chadwick.cwsub_file (
    cwsub_file_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    ingest_run_id UUID
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    event_file_id UUID
        REFERENCES raw_retrosheet.event_file(event_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT,
    tool_version TEXT,
    field_spec TEXT,
    command_text TEXT,
    output_file_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_chadwick.cwsub_file IS
    'Metadata for a cwsub extraction run and output artifact.';

CREATE TABLE IF NOT EXISTS raw_chadwick.cwsub (
    cwsub_row_id BIGSERIAL PRIMARY KEY,
    cwsub_file_id UUID NOT NULL
        REFERENCES raw_chadwick.cwsub_file(cwsub_file_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    game_id TEXT NOT NULL,
    event_id INT,
    inning INT,
    batting_team_side INT,
    player_id TEXT NOT NULL,
    player_name TEXT,
    team_side INT,
    batting_order INT,
    field_position INT,
    removed_player_id TEXT,
    raw_sub_row JSONB
);

COMMENT ON TABLE raw_chadwick.cwsub IS
    'Structured substitution rows from Chadwick cwsub output.';

COMMIT;
