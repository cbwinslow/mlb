BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS stg_player_identity_mlbam_uidx
    ON stg.player_identity (mlbam_player_id)
    WHERE mlbam_player_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS stg_player_identity_retrosheet_uidx
    ON stg.player_identity (retrosheet_player_id)
    WHERE retrosheet_player_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS stg_player_identity_lahman_uidx
    ON stg.player_identity (lahman_player_id)
    WHERE lahman_player_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS stg_player_identity_name_birth_idx
    ON stg.player_identity (last_name, first_name, birth_date);

CREATE UNIQUE INDEX IF NOT EXISTS stg_team_identity_mlbam_uidx
    ON stg.team_identity (mlbam_team_id)
    WHERE mlbam_team_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS stg_team_identity_retro_year_idx
    ON stg.team_identity (retrosheet_team_id, first_year, last_year);

CREATE UNIQUE INDEX IF NOT EXISTS stg_venue_identity_mlbam_uidx
    ON stg.venue_identity (mlbam_venue_id)
    WHERE mlbam_venue_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS stg_venue_identity_retro_uidx
    ON stg.venue_identity (retrosheet_park_id)
    WHERE retrosheet_park_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS stg_game_identity_mlbam_uidx
    ON stg.game_identity (mlbam_game_pk)
    WHERE mlbam_game_pk IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS stg_game_identity_retrosheet_uidx
    ON stg.game_identity (retrosheet_game_id)
    WHERE retrosheet_game_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS stg_game_identity_date_teams_idx
    ON stg.game_identity (game_date, home_team_identity_id, away_team_identity_id);

CREATE INDEX IF NOT EXISTS stg_player_candidate_score_idx
    ON stg.player_identity_candidate (candidate_score DESC);

CREATE INDEX IF NOT EXISTS stg_game_candidate_score_idx
    ON stg.game_identity_candidate (candidate_score DESC);

COMMIT;