BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS core_player_mlbam_uidx
    ON core.player (mlbam_player_id)
    WHERE mlbam_player_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS core_player_retrosheet_uidx
    ON core.player (retrosheet_player_id)
    WHERE retrosheet_player_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS core_player_name_idx
    ON core.player (last_name, first_name);

CREATE UNIQUE INDEX IF NOT EXISTS core_team_mlbam_uidx
    ON core.team (mlbam_team_id)
    WHERE mlbam_team_id IS NOT NULL;

-- NOTE: core_game_mlbam_uidx removed -- mlbam_game_pk now lives in stg.game_identity_bridge
-- NOTE: core_game_retrosheet_uidx removed -- retrosheet_game_id now lives in stg.game_identity_bridge


-- Source key uniqueness is enforced by pk_game_identity_bridge PRIMARY KEY
-- These supplemental indexes support fast lookup on the bridge
CREATE INDEX IF NOT EXISTS idx_stg_game_bridge_season
    ON stg.game_identity_bridge (season, game_date);

CREATE INDEX IF NOT EXISTS idx_stg_game_bridge_home_team
    ON stg.game_identity_bridge (home_team_code, season);

CREATE INDEX IF NOT EXISTS core_game_date_idx
    ON core.games (game_date, season);

CREATE INDEX IF NOT EXISTS core_game_home_away_idx
    ON core.games (home_team_id, away_team_id, game_date);

CREATE INDEX IF NOT EXISTS core_roster_assignment_game_team_idx
    ON core.roster_assignment (game_id, team_id);

CREATE INDEX IF NOT EXISTS core_roster_assignment_player_idx
    ON core.roster_assignment (player_id, game_id);

CREATE INDEX IF NOT EXISTS core_plate_appearances_game_idx
    ON core.plate_appearances (game_id, inning, half_inning, pa_sequence_order);

CREATE INDEX IF NOT EXISTS core_plate_appearances_batter_idx
    ON core.plate_appearances (batter_id, game_id);

CREATE INDEX IF NOT EXISTS core_plate_appearances_pitcher_idx
    ON core.plate_appearances (pitcher_id, game_id);

CREATE INDEX IF NOT EXISTS core_plate_appearances_game_batter_pitcher_idx
    ON core.plate_appearances (game_id, batter_id, pitcher_id);

CREATE INDEX IF NOT EXISTS core_plate_appearances_result_group_idx
    ON core.plate_appearances (event_result_code);

CREATE INDEX IF NOT EXISTS core_pitches_plate_appearance_idx
    ON core.pitches (plate_appearance_id);

CREATE INDEX IF NOT EXISTS core_pitches_sequence_idx
    ON core.pitches (plate_appearance_id, pitch_sequence_num);

CREATE INDEX IF NOT EXISTS core_pitch_type_idx
    ON core.pitches (pitch_type);

CREATE INDEX IF NOT EXISTS core_player_team_season_season_idx
    ON core.player_team_season (season, team_id);

COMMIT;