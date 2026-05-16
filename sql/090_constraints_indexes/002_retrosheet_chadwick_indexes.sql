BEGIN;

CREATE INDEX IF NOT EXISTS raw_retrosheet_game_game_id_idx
    ON raw_retrosheet.game (game_id);

CREATE INDEX IF NOT EXISTS raw_retrosheet_record_game_seq_idx
    ON raw_retrosheet.record (game_id, record_sequence);

CREATE INDEX IF NOT EXISTS raw_retrosheet_record_type_idx
    ON raw_retrosheet.record (record_type);

CREATE INDEX IF NOT EXISTS raw_retrosheet_info_game_key_idx
    ON raw_retrosheet.info (game_id, info_key);

CREATE INDEX IF NOT EXISTS raw_retrosheet_start_game_player_idx
    ON raw_retrosheet.start (game_id, player_id);

CREATE INDEX IF NOT EXISTS raw_retrosheet_sub_game_player_idx
    ON raw_retrosheet.sub (game_id, player_id);

CREATE INDEX IF NOT EXISTS raw_retrosheet_play_game_inning_side_idx
    ON raw_retrosheet.play (game_id, inning, batting_team_side);

CREATE INDEX IF NOT EXISTS raw_retrosheet_play_batter_idx
    ON raw_retrosheet.play (batter_id);

CREATE INDEX IF NOT EXISTS raw_retrosheet_data_game_type_idx
    ON raw_retrosheet.data (game_id, data_type);

CREATE INDEX IF NOT EXISTS raw_retrosheet_adjustment_game_type_idx
    ON raw_retrosheet.adjustment (game_id, adjustment_type);

CREATE INDEX IF NOT EXISTS raw_chadwick_cwevent_game_event_idx
    ON raw_chadwick.cwevent (game_id, event_id);

CREATE INDEX IF NOT EXISTS raw_chadwick_cwevent_batter_idx
    ON raw_chadwick.cwevent (bat_id);

CREATE INDEX IF NOT EXISTS raw_chadwick_cwevent_pitcher_idx
    ON raw_chadwick.cwevent (pit_id);

CREATE INDEX IF NOT EXISTS raw_chadwick_cwgame_game_id_idx
    ON raw_chadwick.cwgame (game_id);

CREATE INDEX IF NOT EXISTS raw_chadwick_cwsub_game_event_idx
    ON raw_chadwick.cwsub (game_id, event_id);

CREATE INDEX IF NOT EXISTS raw_chadwick_cwsub_player_idx
    ON raw_chadwick.cwsub (player_id);

COMMIT;