BEGIN;

CREATE INDEX IF NOT EXISTS raw_statcast_search_file_ingest_run_idx
    ON raw_statcast.search_file (ingest_run_id);

CREATE INDEX IF NOT EXISTS raw_statcast_pitch_game_pk_idx
    ON raw_statcast.pitch (game_pk);

CREATE INDEX IF NOT EXISTS raw_statcast_pitch_game_ab_pitch_idx
    ON raw_statcast.pitch (game_pk, at_bat_number, pitch_number);

CREATE INDEX IF NOT EXISTS raw_statcast_pitch_batter_game_date_idx
    ON raw_statcast.pitch (batter, game_date);

CREATE INDEX IF NOT EXISTS raw_statcast_pitch_pitcher_game_date_idx
    ON raw_statcast.pitch (pitcher, game_date);

CREATE INDEX IF NOT EXISTS raw_statcast_pitch_sv_id_idx
    ON raw_statcast.pitch (sv_id);

CREATE INDEX IF NOT EXISTS raw_statcast_pitch_row_hash_idx
    ON raw_statcast.pitch (row_hash);

CREATE INDEX IF NOT EXISTS raw_mlbapi_request_endpoint_idx
    ON raw_mlbapi.request (source_endpoint_id, requested_at DESC);

CREATE INDEX IF NOT EXISTS raw_mlbapi_payload_endpoint_idx
    ON raw_mlbapi.payload (endpoint_code, created_at DESC);

CREATE INDEX IF NOT EXISTS raw_mlbapi_payload_game_pk_idx
    ON raw_mlbapi.payload (game_pk);

CREATE INDEX IF NOT EXISTS raw_mlbapi_payload_person_id_idx
    ON raw_mlbapi.payload (person_id);

CREATE INDEX IF NOT EXISTS raw_mlbapi_payload_team_id_idx
    ON raw_mlbapi.payload (team_id);

CREATE INDEX IF NOT EXISTS raw_mlbapi_schedule_game_game_pk_idx
    ON raw_mlbapi.schedule_game (game_pk);

CREATE INDEX IF NOT EXISTS raw_mlbapi_schedule_game_official_date_idx
    ON raw_mlbapi.schedule_game (official_date);

CREATE INDEX IF NOT EXISTS raw_mlbapi_live_play_game_pk_idx
    ON raw_mlbapi.live_play (game_pk, all_plays_index);

CREATE INDEX IF NOT EXISTS raw_mlbapi_live_play_batter_pitcher_idx
    ON raw_mlbapi.live_play (batter_id, pitcher_id);

CREATE INDEX IF NOT EXISTS raw_mlbapi_live_pitch_play_idx
    ON raw_mlbapi.live_pitch (raw_live_play_id, pitch_index);

CREATE INDEX IF NOT EXISTS raw_mlbapi_person_person_id_idx
    ON raw_mlbapi.person (person_id);

CREATE INDEX IF NOT EXISTS raw_mlbapi_team_team_id_idx
    ON raw_mlbapi.team (team_id);

CREATE INDEX IF NOT EXISTS raw_mlbapi_meta_value_type_code_idx
    ON raw_mlbapi.meta_value (meta_type, value_code);

COMMIT;