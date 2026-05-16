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

CREATE UNIQUE INDEX IF NOT EXISTS core_game_mlbam_uidx
    ON core.game (mlbam_game_pk)
    WHERE mlbam_game_pk IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS core_game_retrosheet_uidx
    ON core.game (retrosheet_game_id)
    WHERE retrosheet_game_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS core_game_date_idx
    ON core.game (game_date, season);

CREATE INDEX IF NOT EXISTS core_game_home_away_idx
    ON core.game (home_team_id, away_team_id, game_date);

CREATE INDEX IF NOT EXISTS core_roster_assignment_game_team_idx
    ON core.roster_assignment (game_id, team_id);

CREATE INDEX IF NOT EXISTS core_roster_assignment_player_idx
    ON core.roster_assignment (player_id, game_id);

CREATE INDEX IF NOT EXISTS core_pa_game_idx
    ON core.plate_appearance (game_id, inning, inning_half, plate_appearance_number);

CREATE INDEX IF NOT EXISTS core_pa_batter_idx
    ON core.plate_appearance (batter_id, game_id);

CREATE INDEX IF NOT EXISTS core_pa_pitcher_idx
    ON core.plate_appearance (pitcher_id, game_id);

CREATE INDEX IF NOT EXISTS core_pa_result_group_idx
    ON core.plate_appearance (pa_result_group);

CREATE INDEX IF NOT EXISTS core_pitch_game_idx
    ON core.pitch (game_id, inning, inning_half, plate_appearance_number, pitch_number);

CREATE INDEX IF NOT EXISTS core_pitch_batter_idx
    ON core.pitch (batter_id, game_id);

CREATE INDEX IF NOT EXISTS core_pitch_pitcher_idx
    ON core.pitch (pitcher_id, game_id);

CREATE INDEX IF NOT EXISTS core_pitch_type_idx
    ON core.pitch (pitch_type_code);

CREATE INDEX IF NOT EXISTS core_player_team_season_season_idx
    ON core.player_team_season (season, team_id);

COMMIT;