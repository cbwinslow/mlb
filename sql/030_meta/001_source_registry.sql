BEGIN;

CREATE TABLE IF NOT EXISTS meta.source_system (
    source_system_id SMALLSERIAL PRIMARY KEY,
    source_code TEXT NOT NULL UNIQUE,
    source_name TEXT NOT NULL,
    source_kind TEXT NOT NULL,
    base_url TEXT,
    documentation_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT source_system_source_code_chk
        CHECK (source_code = lower(source_code))
);

COMMENT ON TABLE meta.source_system IS
    'Registry of upstream baseball data sources such as Retrosheet, Statcast, MLB StatsAPI, Lahman, and odds providers.';

COMMENT ON COLUMN meta.source_system.source_kind IS
    'High-level source category such as files, api, csv, cli, or web.';

CREATE TABLE IF NOT EXISTS meta.source_endpoint (
    source_endpoint_id BIGSERIAL PRIMARY KEY,
    source_system_id SMALLINT NOT NULL
        REFERENCES meta.source_system(source_system_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    endpoint_code TEXT NOT NULL,
    endpoint_name TEXT NOT NULL,
    endpoint_group TEXT,
    http_method TEXT,
    relative_path TEXT,
    notes TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT source_endpoint_code_chk
        CHECK (endpoint_code = lower(endpoint_code)),
    CONSTRAINT source_endpoint_method_chk
        CHECK (
            http_method IS NULL
            OR http_method IN ('GET', 'POST', 'PUT', 'PATCH', 'DELETE')
        ),
    CONSTRAINT source_endpoint_unique
        UNIQUE (source_system_id, endpoint_code)
);

COMMENT ON TABLE meta.source_endpoint IS
    'Registry of endpoint families, file groups, or logical extraction units for each source system.';

CREATE INDEX IF NOT EXISTS source_endpoint_source_system_id_idx
    ON meta.source_endpoint (source_system_id);

CREATE INDEX IF NOT EXISTS source_endpoint_group_idx
    ON meta.source_endpoint (endpoint_group);

INSERT INTO meta.source_system (
    source_code,
    source_name,
    source_kind,
    base_url,
    documentation_url
)
VALUES
    (
        'retrosheet',
        'Retrosheet',
        'files',
        'https://www.retrosheet.org',
        'https://www.retrosheet.org/eventfile.htm'
    ),
    (
        'chadwick',
        'Chadwick',
        'cli',
        'https://chadwick.sourceforge.net',
        'https://chadwick.sourceforge.net/doc/cwevent.html'
    ),
    (
        'lahman',
        'Lahman Baseball Database',
        'files',
        'https://cran.r-project.org/package=Lahman',
        'https://rdrr.io/cran/Lahman/man/Lahman-package.html'
    ),
    (
        'statcast',
        'Baseball Savant Statcast',
        'csv',
        'https://baseballsavant.mlb.com',
        'https://baseballsavant.mlb.com/csv-docs'
    ),
    (
        'mlbapi',
        'MLB StatsAPI',
        'api',
        'https://statsapi.mlb.com/api/v1',
        'https://github.com/toddrob99/MLB-StatsAPI/wiki/Endpoints'
    ),
    (
        'fangraphs',
        'FanGraphs',
        'web',
        'https://www.fangraphs.com',
        'https://github.com/jldbc/pybaseball/blob/master/docs/fangraphs.md'
    ),
    (
        'bref',
        'Baseball Reference',
        'web',
        'https://www.baseball-reference.com',
        'https://www.baseball-reference.com'
    ),
    (
        'espn',
        'ESPN',
        'web',
        'https://www.espn.com/mlb',
        'https://www.espn.com/mlb'
    ),
    (
        'odds',
        'Odds Providers',
        'api',
        NULL,
        NULL
    )
ON CONFLICT (source_code) DO UPDATE
SET
    source_name = EXCLUDED.source_name,
    source_kind = EXCLUDED.source_kind,
    base_url = EXCLUDED.base_url,
    documentation_url = EXCLUDED.documentation_url,
    updated_at = NOW();

INSERT INTO meta.source_endpoint (
    source_system_id,
    endpoint_code,
    endpoint_name,
    endpoint_group,
    http_method,
    relative_path,
    notes
)
SELECT
    ss.source_system_id,
    v.endpoint_code,
    v.endpoint_name,
    v.endpoint_group,
    v.http_method,
    v.relative_path,
    v.notes
FROM meta.source_system ss
JOIN (
    VALUES
        ('mlbapi', 'schedule', 'Schedule', 'games', 'GET', '/schedule', 'Primary game calendar endpoint.'),
        ('mlbapi', 'game', 'Game', 'games', 'GET', '/game/{gamePk}', 'Game-level endpoint family.'),
        ('mlbapi', 'game_live_feed', 'Game Live Feed', 'games', 'GET', '/game/{gamePk}/feed/live', 'Live game state and plays.'),
        ('mlbapi', 'people', 'People', 'people', 'GET', '/people/{personIds}', 'Player/person records.'),
        ('mlbapi', 'teams', 'Teams', 'teams', 'GET', '/teams', 'Teams and team detail records.'),
        ('mlbapi', 'stats', 'Stats', 'stats', 'GET', '/stats', 'Stats endpoint family.'),
        ('mlbapi', 'meta', 'Meta', 'reference', 'GET', '/meta/{type}', 'Reference/meta values such as gameTypes and eventTypes.'),
        ('retrosheet', 'event_files', 'Event Files', 'files', NULL, NULL, 'Season/team event files.'),
        ('retrosheet', 'parsed_plays', 'Parsed Plays', 'files', NULL, NULL, 'Pre-parsed play-by-play downloads where used.'),
        ('chadwick', 'cwevent', 'cwevent', 'cli', NULL, NULL, 'Expanded event extractor output.'),
        ('lahman', 'core_tables', 'Core Tables', 'files', NULL, NULL, 'Published Lahman relational tables.'),
        ('statcast', 'search_csv', 'Statcast Search CSV', 'csv', 'GET', '/statcast_search', 'Baseball Savant Statcast CSV export/search results.')
) AS v(source_code, endpoint_code, endpoint_name, endpoint_group, http_method, relative_path, notes)
    ON v.source_code = ss.source_code
ON CONFLICT (source_system_id, endpoint_code) DO UPDATE
SET
    endpoint_name = EXCLUDED.endpoint_name,
    endpoint_group = EXCLUDED.endpoint_group,
    http_method = EXCLUDED.http_method,
    relative_path = EXCLUDED.relative_path,
    notes = EXCLUDED.notes,
    updated_at = NOW();

COMMIT;