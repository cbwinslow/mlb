BEGIN;

CREATE INDEX IF NOT EXISTS raw_lahman_people_player_id_idx
    ON raw_lahman.people (player_id);

CREATE INDEX IF NOT EXISTS raw_lahman_people_retro_id_idx
    ON raw_lahman.people (retro_id);

CREATE INDEX IF NOT EXISTS raw_lahman_people_bbref_id_idx
    ON raw_lahman.people (bbref_id);

CREATE INDEX IF NOT EXISTS raw_lahman_batting_player_year_idx
    ON raw_lahman.batting (player_id, year_id);

CREATE INDEX IF NOT EXISTS raw_lahman_pitching_player_year_idx
    ON raw_lahman.pitching (player_id, year_id);

CREATE INDEX IF NOT EXISTS raw_lahman_fielding_player_year_idx
    ON raw_lahman.fielding (player_id, year_id);

CREATE INDEX IF NOT EXISTS raw_lahman_teams_year_team_idx
    ON raw_lahman.teams (year_id, team_id);

CREATE INDEX IF NOT EXISTS raw_fangraphs_payload_season_idx
    ON raw_fangraphs.payload (season, leaderboard_name);

CREATE INDEX IF NOT EXISTS raw_fangraphs_payload_natural_key_idx
    ON raw_fangraphs.payload (natural_key);

CREATE INDEX IF NOT EXISTS raw_bref_page_type_entity_idx
    ON raw_bref.page (page_type, entity_key, season);

CREATE INDEX IF NOT EXISTS raw_bref_page_natural_key_idx
    ON raw_bref.page (natural_key);

CREATE INDEX IF NOT EXISTS raw_espn_page_type_entity_idx
    ON raw_espn.page (page_type, entity_key, season);

CREATE INDEX IF NOT EXISTS raw_espn_page_natural_key_idx
    ON raw_espn.page (natural_key);

CREATE INDEX IF NOT EXISTS raw_odds_provider_payload_event_market_idx
    ON raw_odds.provider_payload (provider_code, event_key, market_key);

CREATE INDEX IF NOT EXISTS raw_odds_provider_payload_natural_key_idx
    ON raw_odds.provider_payload (natural_key);

COMMIT;