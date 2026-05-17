BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mlb_platform_admin') THEN
        CREATE ROLE mlb_platform_admin NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mlb_app_user') THEN
        CREATE ROLE mlb_app_user NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mlb_readonly') THEN
        CREATE ROLE mlb_readonly NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mlb_worker') THEN
        CREATE ROLE mlb_worker NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mlb_api') THEN
        CREATE ROLE mlb_api NOLOGIN;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA meta, ref, raw_retrosheet, raw_chadwick, raw_lahman, raw_statcast, raw_mlbapi,
                     raw_fangraphs, raw_bref, raw_espn, raw_odds, stg, core, mart, util, ml, ops, auth
TO mlb_platform_admin, mlb_app_user, mlb_readonly, mlb_worker, mlb_api;

GRANT SELECT ON ALL TABLES IN SCHEMA meta, ref, stg, core, mart
TO mlb_platform_admin, mlb_readonly, mlb_api, mlb_app_user, mlb_worker;

GRANT SELECT ON ALL TABLES IN SCHEMA raw_retrosheet, raw_chadwick, raw_lahman, raw_statcast, raw_mlbapi,
                                  raw_fangraphs, raw_bref, raw_espn, raw_odds
TO mlb_platform_admin, mlb_worker, mlb_api;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA ml, ops, auth
TO mlb_platform_admin, mlb_app_user, mlb_worker, mlb_api;

GRANT SELECT ON ALL TABLES IN SCHEMA ml, ops, auth
TO mlb_readonly;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA meta, ref, raw_retrosheet, raw_chadwick, raw_lahman,
                                           raw_statcast, raw_mlbapi, raw_fangraphs, raw_bref, raw_espn,
                                           raw_odds, stg, core, mart, ml, ops, auth
TO mlb_platform_admin, mlb_app_user, mlb_worker, mlb_api, mlb_readonly;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA util
TO mlb_platform_admin, mlb_app_user, mlb_worker, mlb_api, mlb_readonly;

ALTER DEFAULT PRIVILEGES IN SCHEMA meta, ref, stg, core, mart
GRANT SELECT ON TABLES TO mlb_platform_admin, mlb_readonly, mlb_api, mlb_app_user, mlb_worker;

ALTER DEFAULT PRIVILEGES IN SCHEMA raw_retrosheet, raw_chadwick, raw_lahman, raw_statcast, raw_mlbapi,
                                  raw_fangraphs, raw_bref, raw_espn, raw_odds
GRANT SELECT ON TABLES TO mlb_platform_admin, mlb_worker, mlb_api;

ALTER DEFAULT PRIVILEGES IN SCHEMA ml, ops, auth
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO mlb_platform_admin, mlb_app_user, mlb_worker, mlb_api;

ALTER DEFAULT PRIVILEGES IN SCHEMA ml, ops, auth
GRANT SELECT ON TABLES TO mlb_readonly;

ALTER DEFAULT PRIVILEGES IN SCHEMA meta, ref, raw_retrosheet, raw_chadwick, raw_lahman,
                                  raw_statcast, raw_mlbapi, raw_fangraphs, raw_bref, raw_espn,
                                  raw_odds, stg, core, mart, ml, ops, auth
GRANT USAGE, SELECT ON SEQUENCES TO mlb_platform_admin, mlb_app_user, mlb_worker, mlb_api, mlb_readonly;

ALTER DEFAULT PRIVILEGES IN SCHEMA util
GRANT EXECUTE ON FUNCTIONS TO mlb_platform_admin, mlb_app_user, mlb_worker, mlb_api, mlb_readonly;

COMMIT;