BEGIN;

CREATE TABLE IF NOT EXISTS raw_statcast.search_file (
    statcast_search_file_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    ingest_run_id UUID
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    source_endpoint_id BIGINT
        REFERENCES meta.source_endpoint(source_endpoint_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    query_start_date DATE,
    query_end_date DATE,
    query_params JSONB,
    export_source TEXT NOT NULL DEFAULT 'statcast_search_csv',
    tool_name TEXT,
    tool_version TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_statcast.search_file IS
    'Metadata for a Statcast search extraction, whether via direct CSV export or pybaseball.';

CREATE TABLE IF NOT EXISTS raw_statcast.pitch (
    raw_statcast_pitch_id BIGSERIAL PRIMARY KEY,
    statcast_search_file_id UUID NOT NULL
        REFERENCES raw_statcast.search_file(statcast_search_file_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    pitch_type TEXT,
    game_date DATE,
    release_speed NUMERIC(8,3),
    release_pos_x NUMERIC(10,5),
    release_pos_z NUMERIC(10,5),
    player_name TEXT,
    batter BIGINT,
    pitcher BIGINT,
    events TEXT,
    description TEXT,
    spin_dir NUMERIC(10,5),
    spin_rate_deprecated NUMERIC(10,5),
    break_angle_deprecated NUMERIC(10,5),
    break_length_deprecated NUMERIC(10,5),
    zone SMALLINT,
    des TEXT,
    game_type TEXT,
    stand TEXT,
    p_throws TEXT,
    home_team TEXT,
    away_team TEXT,
    type TEXT,
    hit_location SMALLINT,
    bb_type TEXT,
    balls SMALLINT,
    strikes SMALLINT,
    game_year INT,
    pfx_x NUMERIC(10,5),
    pfx_z NUMERIC(10,5),
    plate_x NUMERIC(10,5),
    plate_z NUMERIC(10,5),
    on_3b BIGINT,
    on_2b BIGINT,
    on_1b BIGINT,
    outs_when_up SMALLINT,
    inning SMALLINT,
    inning_topbot TEXT,
    hc_x NUMERIC(10,5),
    hc_y NUMERIC(10,5),
    tfs_deprecated TEXT,
    tfs_zulu_deprecated TIMESTAMPTZ,
    fielder_2 BIGINT,
    umpire BIGINT,
    sv_id TEXT,
    vx0 NUMERIC(12,6),
    vy0 NUMERIC(12,6),
    vz0 NUMERIC(12,6),
    ax NUMERIC(12,6),
    ay NUMERIC(12,6),
    az NUMERIC(12,6),
    sz_top NUMERIC(10,5),
    sz_bot NUMERIC(10,5),
    hit_distance_sc INT,
    launch_speed NUMERIC(8,3),
    launch_angle NUMERIC(8,3),
    effective_speed NUMERIC(8,3),
    release_spin_rate NUMERIC(10,5),
    release_extension NUMERIC(10,5),
    game_pk BIGINT,
    pitcher_1 BIGINT,
    fielder_2_1 BIGINT,
    fielder_3 BIGINT,
    fielder_4 BIGINT,
    fielder_5 BIGINT,
    fielder_6 BIGINT,
    fielder_7 BIGINT,
    fielder_8 BIGINT,
    fielder_9 BIGINT,
    release_pos_y NUMERIC(10,5),
    estimated_ba_using_speedangle NUMERIC(8,5),
    estimated_woba_using_speedangle NUMERIC(8,5),
    woba_value NUMERIC(8,5),
    woba_denom NUMERIC(8,5),
    babip_value NUMERIC(8,5),
    iso_value NUMERIC(8,5),
    launch_speed_angle SMALLINT,
    at_bat_number INT,
    pitch_number INT,
    pitch_name TEXT,
    home_score INT,
    away_score INT,
    bat_score INT,
    fld_score INT,
    post_away_score INT,
    post_home_score INT,
    post_bat_score INT,
    post_fld_score INT,
    if_fielding_alignment TEXT,
    of_fielding_alignment TEXT,
    spin_axis NUMERIC(8,3),
    delta_home_win_exp NUMERIC(10,5),
    delta_run_exp NUMERIC(10,5),

    row_hash BYTEA,
    raw_payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT raw_statcast_pitch_business_key_unique
        UNIQUE (statcast_search_file_id, game_pk, at_bat_number, pitch_number)
);

COMMENT ON TABLE raw_statcast.pitch IS
    'Raw Statcast pitch-level rows modeled from Baseball Savant CSV documentation and pybaseball extraction behavior.';

CREATE TABLE IF NOT EXISTS raw_statcast.lookup_observation (
    raw_statcast_lookup_observation_id BIGSERIAL PRIMARY KEY,
    statcast_search_file_id UUID NOT NULL
        REFERENCES raw_statcast.search_file(statcast_search_file_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    lookup_type TEXT NOT NULL,
    lookup_code TEXT NOT NULL,
    lookup_value TEXT,
    observed_count BIGINT NOT NULL DEFAULT 1,
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_statcast_lookup_unique
        UNIQUE (statcast_search_file_id, lookup_type, lookup_code, lookup_value)
);

COMMENT ON TABLE raw_statcast.lookup_observation IS
    'Observed lookup-like codes from Statcast rows, useful for downstream reference table generation and validation.';

COMMIT;