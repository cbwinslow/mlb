BEGIN;

CREATE TABLE IF NOT EXISTS core.roster_assignment (
    roster_assignment_id BIGSERIAL PRIMARY KEY,
    game_id BIGINT NOT NULL
        REFERENCES core.game(game_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    team_id BIGINT NOT NULL
        REFERENCES core.team(team_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    player_id BIGINT NOT NULL
        REFERENCES core.player(player_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    source_role_code TEXT,
    batting_order_slot SMALLINT,
    field_position_code SMALLINT,
    starter_flag BOOLEAN NOT NULL DEFAULT FALSE,
    substitute_flag BOOLEAN NOT NULL DEFAULT FALSE,
    lineup_sequence INT,
    entered_inning SMALLINT,
    exited_inning SMALLINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE core.roster_assignment IS
    'Game-level roster, lineup, and defensive assignment facts.';

CREATE TABLE IF NOT EXISTS core.plate_appearance (
    plate_appearance_id BIGSERIAL PRIMARY KEY,
    game_id BIGINT NOT NULL
        REFERENCES core.game(game_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    batting_team_id BIGINT NOT NULL
        REFERENCES core.team(team_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    fielding_team_id BIGINT NOT NULL
        REFERENCES core.team(team_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    batter_id BIGINT
        REFERENCES core.player(player_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    pitcher_id BIGINT
        REFERENCES core.player(player_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    inning SMALLINT NOT NULL,
    inning_half TEXT NOT NULL,
    plate_appearance_number INT NOT NULL,
    outs_before SMALLINT,
    balls_end SMALLINT,
    strikes_end SMALLINT,
    start_base_state_code TEXT,
    end_base_state_code TEXT,
    runs_scored_on_pa SMALLINT,
    event_code TEXT,
    event_text TEXT,
    hit_type_code TEXT,
    batted_ball_type_code TEXT,
    pa_result_group TEXT,
    ab_flag BOOLEAN,
    hit_flag BOOLEAN,
    on_base_flag BOOLEAN,
    strikeout_flag BOOLEAN,
    walk_flag BOOLEAN,
    hbp_flag BOOLEAN,
    sac_fly_flag BOOLEAN,
    sac_hit_flag BOOLEAN,
    gidp_flag BOOLEAN,
    rbi INT,
    woba_value NUMERIC(8,5),
    run_expectancy_delta NUMERIC(10,5),
    win_expectancy_delta NUMERIC(10,5),
    source_system_code TEXT,
    source_pa_key TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT core_plate_appearance_unique
        UNIQUE (game_id, inning, inning_half, plate_appearance_number)
);

COMMENT ON TABLE core.plate_appearance IS
    'Canonical plate appearance fact, sourced from Retrosheet/Chadwick and enriched with Statcast or MLB StatsAPI where available.';

CREATE TABLE IF NOT EXISTS core.pitch (
    pitch_id BIGSERIAL PRIMARY KEY,
    game_id BIGINT NOT NULL
        REFERENCES core.game(game_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    plate_appearance_id BIGINT
        REFERENCES core.plate_appearance(plate_appearance_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    batter_id BIGINT
        REFERENCES core.player(player_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    pitcher_id BIGINT
        REFERENCES core.player(player_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    inning SMALLINT NOT NULL,
    inning_half TEXT NOT NULL,
    plate_appearance_number INT,
    pitch_number INT NOT NULL,
    outs_before SMALLINT,
    balls_before SMALLINT,
    strikes_before SMALLINT,
    pitch_type_code TEXT,
    pitch_name TEXT,
    pitch_call_code TEXT,
    pitch_call_text TEXT,
    release_speed NUMERIC(8,3),
    effective_speed NUMERIC(8,3),
    release_spin_rate NUMERIC(10,3),
    release_extension NUMERIC(10,3),
    spin_axis NUMERIC(8,3),
    plate_x NUMERIC(10,5),
    plate_z NUMERIC(10,5),
    sz_top NUMERIC(10,5),
    sz_bot NUMERIC(10,5),
    zone SMALLINT,
    pfx_x NUMERIC(10,5),
    pfx_z NUMERIC(10,5),
    vx0 NUMERIC(12,6),
    vy0 NUMERIC(12,6),
    vz0 NUMERIC(12,6),
    ax NUMERIC(12,6),
    ay NUMERIC(12,6),
    az NUMERIC(12,6),
    launch_speed NUMERIC(8,3),
    launch_angle NUMERIC(8,3),
    hit_distance_sc INT,
    events TEXT,
    description TEXT,
    estimated_ba_using_speedangle NUMERIC(8,5),
    estimated_woba_using_speedangle NUMERIC(8,5),
    delta_run_exp NUMERIC(10,5),
    delta_home_win_exp NUMERIC(10,5),
    source_system_code TEXT,
    source_pitch_key TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT core_pitch_unique
        UNIQUE (game_id, inning, inning_half, plate_appearance_number, pitch_number)
);

COMMENT ON TABLE core.pitch IS
    'Canonical pitch fact centered on Statcast pitch-level structure and linked to canonical game and plate appearance facts.';

COMMIT;