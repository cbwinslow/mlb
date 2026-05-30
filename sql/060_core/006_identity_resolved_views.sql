BEGIN;

-- ============================================================================
-- Resolved Views: Join raw source data through identity bridges
-- 
-- These views expose Retrosheet, MLBAM, and other IDs side-by-side, enabling
-- queries like: "All Statcast events for a player whose Retrosheet ID is X"
-- ============================================================================

-- Player identity resolved: All sources side-by-side
CREATE OR REPLACE VIEW core.v_player_identity_resolved AS
SELECT
    pi.player_identity_id,
    pi.mlbam_player_id,
    pi.retrosheet_player_id,
    pi.bbref_player_id,
    pi.fangraphs_player_id,
    pi.lahman_player_id,
    pi.full_name,
    pi.first_name,
    pi.last_name,
    pi.bats,
    pi.throws,
    pi.birth_date,
    pi.mlb_debut_date,
    pi.is_active,
    pi.identity_confidence_score
FROM stg.player_identity pi;

COMMENT ON VIEW core.v_player_identity_resolved IS
    'All player identity IDs side-by-side for cross-source lookups. '
    'Query by any ID type to find the canonical player_identity_id.';

-- Team identity resolved: All sources side-by-side
CREATE OR REPLACE VIEW core.v_team_identity_resolved AS
SELECT
    ti.team_identity_id,
    ti.mlbam_team_id,
    ti.retrosheet_team_id,
    ti.bbref_team_id,
    ti.fangraphs_team_id,
    ti.lahman_team_id,
    ti.franchise_id,
    ti.team_name,
    ti.city_name,
    ti.nickname,
    ti.league_code,
    ti.first_year,
    ti.last_year
FROM stg.team_identity ti;

COMMENT ON VIEW core.v_team_identity_resolved IS
    'All team identity IDs side-by-side for cross-source lookups. '
    'Query by any ID type to find the canonical team_identity_id.';

-- Statcast events resolved: Link through player_identity bridge
CREATE OR REPLACE VIEW core.v_statcast_events_resolved AS
SELECT
    p.batter,
    p.pitcher,
    p.fielder_2,
    p.fielder_3,
    batter_pi.player_identity_id AS batter_identity_id,
    batter_pi.retrosheet_player_id AS batter_retro_id,
    batter_pi.bbref_player_id AS batter_bbref_id,
    pitcher_pi.player_identity_id AS pitcher_identity_id,
    pitcher_pi.retrosheet_player_id AS pitcher_retro_id,
    pitcher_pi.bbref_player_id AS pitcher_bbref_id,
    p.game_pk,
    p.game_date,
    p.home_team,
    p.away_team,
    -- Team codes from Statcast use MLB abbreviations (NYY, LAD, etc.)
    -- Statcast team_id maps to statcast_team_id in the identity bridge
    home_ti.team_identity_id AS home_team_identity_id,
    away_ti.team_identity_id AS away_team_identity_id,
    p.events,
    p.pitch_type,
    p.release_speed,
    p.release_spin_rate,
    p.plate_x,
    p.plate_z,
    p.description,
    p.game_year
FROM raw_statcast.pitch p
LEFT JOIN stg.player_identity batter_pi ON batter_pi.mlbam_player_id = p.batter
LEFT JOIN stg.player_identity pitcher_pi ON pitcher_pi.mlbam_player_id = p.pitcher
LEFT JOIN stg.team_identity home_ti ON home_ti.statcast_team_id = p.home_team
LEFT JOIN stg.team_identity away_ti ON away_ti.statcast_team_id = p.away_team;

COMMENT ON VIEW core.v_statcast_events_resolved IS
    'Statcast events with resolved player and team identity IDs. '
    'Enables queries like: Find all Statcast events for a Retrosheet player ID.';

COMMIT;