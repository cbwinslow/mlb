# End-to-End Guide: Unifying Retrosheet, Statcast, and MLB IDs

This document is written for an AI agent (or automation script) that needs to:

- Download authoritative cross‑reference data for MLB players and other entities.
- Load that data into a PostgreSQL database.
- Create normalized cross‑reference tables for players, teams, parks, and staff.
- Link Retrosheet, Statcast, and MLB (Stats API / MLBAM) data through those tables.

The goal is to make **MLBAM ID** (the integer used by Statcast and the MLB Stats API) the canonical key for all modern data, while still supporting Retrosheet and other historical ID systems.[web:70][web:76]

---

## 1. Core Concepts and Canonical ID Choice

### 1.1 ID systems in scope

The agent must be aware of the main identifier systems:

- **Retrosheet**
  - Players: 8‑character string, e.g. `ruthb101`.[web:75][web:77]
  - Teams: 3‑letter team IDs, e.g. `NYA`, `BOS`.[web:63]
  - Parks: park codes, e.g. `NYC01`.

- **MLBAM / Statcast / MLB Stats API**
  - Players: integer MLBAM ID, e.g. `592450` (used in Statcast CSVs and the Stats API).[web:70]
  - Games: `game_pk` integer.
  - Teams: integer team IDs, plus short names; Stats API also uses UUIDs in some contexts.[web:65]
  - Venues: integer venue IDs.[web:65]

- **Other ecosystems (optional but supported)**
  - Baseball‑Reference, FanGraphs, Lahman, Yahoo, ESPN, etc., all have their own IDs; public maps exist to cross‑link them.[web:57][web:62][web:80]

### 1.2 Canonical key strategy

The recommended strategy:

- Use **MLBAM player ID** as the primary key for the `players` dimension table, because it is shared by Statcast and the MLB Stats API and is present in many public datasets.[web:70][web:78]
- Use **Retrosheet player ID** as an alternate key to link directly to Retrosheet event and roster files.[web:75][web:77]
- Use small xref tables (or columns on dimension tables) to store Baseball‑Reference, FanGraphs, Lahman, and other IDs, leveraging community resources like the **Chadwick Bureau Register** and SmartFantasyBaseball’s **Player ID Map**.[web:71][web:69][web:80]

---

## 2. Data Sources the Agent Must Use

### 2.1 Chadwick Baseball Bureau Register (people)

The **Chadwick Register** is an authoritative CSV-based registry of baseball people, including cross‑references across multiple ID systems.[web:71][web:76]

Key facts:

- Repository: `https://github.com/chadwickbureau/register`.[web:71]
- It contains CSVs under `data/` (e.g., `people.csv` or split variants) with columns like:
  - `key_retro` – Retrosheet player ID.
  - `key_mlbam` – MLBAM ID.
  - `key_bbref` – Baseball‑Reference ID.
  - `key_fangraphs` – FanGraphs ID.
  - `key_lahman` – Lahman ID.
  - Name and biographical info.

The agent must:

1. Fetch the latest `people` CSV from the repo (handle cases where `people.csv` is split).[web:71][web:67]
2. Parse it and keep only rows where `key_mlbam` or `key_retro` is present.
3. Use it as the **source of truth** for player ID cross‑references.

### 2.2 Retrosheet CSVs

Retrosheet provides:[web:66]

- Event files and CSVs with player IDs and game events.[web:77]
- Biographical CSV (`biofile.csv`) with Retrosheet IDs and names.[web:75]
- Team logs and team ID documentation for 3‑letter team codes.[web:63]

The agent must download the relevant CSV packages from `https://www.retrosheet.org/` and unpack them locally for ingestion.[web:66]

### 2.3 Statcast / Baseball Savant CSVs

Statcast data from Baseball Savant includes:[web:70]

- `game_date`, `game_pk`, and many play‑level fields.
- `pitcher`, `batter`, and Fielder columns (`fielder_2`–`fielder_9`) that store **MLB Player Id** (MLBAM) per play.[web:70]

The agent should either:

- Use existing local Statcast CSV exports, or
- Query Baseball Savant programmatically (e.g., via `pybaseball` or a custom HTTP client) and save results as CSV.[web:79]

### 2.4 Optional: SmartFantasyBaseball Player ID Map

The **SFBB Player ID Map** is an Excel/CSV resource with mappings between many fantasy-relevant ID systems (MLB, Retrosheet, Baseball‑Reference, FanGraphs, etc.).[web:57][web:69][web:80]

Use cases for the agent:

- As a secondary source to validate mappings from Chadwick.
- To fill in missing IDs (especially for fantasy platforms).

---

## 3. Database Schema Design (PostgreSQL)

The agent should assume PostgreSQL as the target and create a dedicated schema (e.g. `baseball`). Adjust the schema name if the user provides something different.

### 3.1 Players cross‑reference table

Create a central `players_xref` table. Use `mlbam_id` as the primary key.

```sql
CREATE SCHEMA IF NOT EXISTS baseball;

CREATE TABLE IF NOT EXISTS baseball.players_xref (
    mlbam_id        INTEGER PRIMARY KEY,          -- canonical
    retrosheet_id   VARCHAR(12),                  -- key_retro
    bbref_id        VARCHAR(16),                  -- key_bbref
    fangraphs_id    INTEGER,
    lahman_id       VARCHAR(16),

    -- useful descriptive fields for debugging
    first_name      TEXT,
    last_name       TEXT,
    full_name       TEXT,
    birth_date      DATE,
    bats            CHAR(1),                      -- L/R/S
    throws          CHAR(1),                      -- L/R/S

    created_at      TIMESTAMP DEFAULT now(),
    updated_at      TIMESTAMP DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_players_xref_retro
    ON baseball.players_xref(retrosheet_id)
    WHERE retrosheet_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_players_xref_bbref
    ON baseball.players_xref(bbref_id)
    WHERE bbref_id IS NOT NULL;
```

### 3.2 Teams cross‑reference table

Retrosheet’s 3‑letter team codes must be mapped to MLB’s integer team IDs.[web:63][web:65]

```sql
CREATE TABLE IF NOT EXISTS baseball.teams_xref (
    team_mlb_id     INTEGER PRIMARY KEY,
    team_retro_id   VARCHAR(3) NOT NULL,   -- e.g. NYA
    team_abbr       VARCHAR(5),            -- e.g. NYY
    team_name       TEXT,
    season_start    INTEGER,
    season_end      INTEGER
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_teams_xref_retro
    ON baseball.teams_xref(team_retro_id, season_start);
```

Populate this table manually or from trusted CSVs; there are only a few dozen modern teams, so manual curation is feasible.[web:57]

### 3.3 Parks / stadiums cross‑reference table

Retrosheet park codes must be mapped to MLB venue IDs.[web:77][web:65]

```sql
CREATE TABLE IF NOT EXISTS baseball.parks_xref (
    park_mlb_id     INTEGER PRIMARY KEY,      -- Stats API venue id
    park_retro_id   VARCHAR(8),              -- Retrosheet park code
    name            TEXT,
    city            TEXT,
    state           TEXT,
    country         TEXT,
    opened          DATE,
    closed          DATE
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_parks_retro
    ON baseball.parks_xref(park_retro_id)
    WHERE park_retro_id IS NOT NULL;
```

The Stats API `/api/v1/venues` endpoint exposes MLB venue IDs, while Retrosheet’s park files provide the park codes and metadata.[web:65][web:77]

### 3.4 Linking fact tables to xref tables

The primary fact tables (Retrosheet events, Statcast plays, etc.) should **not** be modified to change their IDs. Instead, they should join to `*_xref` tables:

- Retrosheet event fact tables keep `retrosheet_id` columns for players, teams, and parks, joined to `players_xref`, `teams_xref`, and `parks_xref`.
- Statcast fact tables keep `mlbam_id` columns (`batter`, `pitcher`, fielder columns) and join directly to `players_xref` via `mlbam_id`.[web:70]

This allows queries like: “All Statcast batted balls for a player whose Retrosheet ID is `troutm001`” by joining through `players_xref`.

---

## 4. Agent Workflow: Fetch and Load the Chadwick Register

### 4.1 Download the `people` CSV

The agent should:

1. Query `https://api.github.com/repos/chadwickbureau/register/contents/data` to discover the files under `data/`.[web:71]
2. Select the latest `people` CSV (it may be named `people.csv` or split, e.g., `people_0.csv`, `people_1.csv`).[web:67]
3. Download these files via their `download_url` and save them locally (e.g., `data/chadwick_people.csv` or a merged file).

If multiple parts exist, the agent must vertically concatenate them into one table.[web:67]

### 4.2 Parse and transform

The agent should perform the following steps in Python (or another language with CSV support):

1. Read all `people` CSV files into a single DataFrame.
2. Normalize column names to lower case.
3. Filter to rows where at least one of `key_mlbam` or `key_retro` is not null.
4. Cast `key_mlbam` to integer where possible.
5. Construct `full_name = name_first || ' ' || name_last`.

Pseudocode in Python:

```python
import pandas as pd
from sqlalchemy import create_engine

# 1. Load CSV(s)
paths = ["data/people.csv"]  # or discovered list
frames = [pd.read_csv(p, low_memory=False) for p in paths]
people = pd.concat(frames, ignore_index=True)

# 2. Normalize columns
people.columns = [c.lower() for c in people.columns]

# 3. Filter relevant rows
mask = people["key_mlbam"].notna() | people["key_retro"].notna()
people = people[mask].copy()

# 4. Cast and build full_name
people["key_mlbam"] = pd.to_numeric(people["key_mlbam"], errors="coerce").astype("Int64")
people["full_name"] = people["name_first"].fillna("") + " " + people["name_last"].fillna("")

# 5. Select columns for xref
xref = people[[
    "key_mlbam", "key_retro", "key_bbref", "key_fangraphs", "key_lahman",
    "name_first", "name_last", "full_name", "birth_date", "bats", "throws"
]].copy()
```

### 4.3 Load into PostgreSQL

The agent then writes `xref` into `baseball.players_xref`.

```python
engine = create_engine("postgresql://USER:PASS@HOST:PORT/DBNAME")

# Write to a staging table first
xref.to_sql("players_xref_stage", engine, schema="baseball", if_exists="replace", index=False)

# Upsert into the main table
with engine.begin() as conn:
    conn.execute("""
        INSERT INTO baseball.players_xref AS t (
            mlbam_id, retrosheet_id, bbref_id, fangraphs_id, lahman_id,
            first_name, last_name, full_name, birth_date, bats, throws
        )
        SELECT
            key_mlbam::INTEGER,
            key_retro,
            key_bbref,
            key_fangraphs::INTEGER,
            key_lahman,
            name_first,
            name_last,
            full_name,
            birth_date::DATE,
            bats,
            throws
        FROM baseball.players_xref_stage s
        WHERE key_mlbam IS NOT NULL
        ON CONFLICT (mlbam_id) DO UPDATE
        SET retrosheet_id = COALESCE(EXCLUDED.retrosheet_id, t.retrosheet_id),
            bbref_id      = COALESCE(EXCLUDED.bbref_id, t.bbref_id),
            fangraphs_id  = COALESCE(EXCLUDED.fangraphs_id, t.fangraphs_id),
            lahman_id     = COALESCE(EXCLUDED.lahman_id, t.lahman_id),
            first_name    = COALESCE(EXCLUDED.first_name, t.first_name),
            last_name     = COALESCE(EXCLUDED.last_name, t.last_name),
            full_name     = COALESCE(EXCLUDED.full_name, t.full_name),
            birth_date    = COALESCE(EXCLUDED.birth_date, t.birth_date),
            bats          = COALESCE(EXCLUDED.bats, t.bats),
            throws        = COALESCE(EXCLUDED.throws, t.throws),
            updated_at    = now();
    """)
```

The agent should log row counts before and after to verify successful ingestion.

---

## 5. Agent Workflow: Ingest Retrosheet Data and Link to Xref

### 5.1 Download Retrosheet CSV packages

The agent must:

1. Navigate to `https://www.retrosheet.org/` and identify the CSV downloads for:[web:66]
   - Event files.
   - Game logs.
   - Biographical data (`biofile.csv`).[web:75]
2. Download the ZIP files and unzip them into a local `data/retrosheet/` directory.

### 5.2 Load Retrosheet biographical data

`biofile.csv` includes `PLAYERID` (Retrosheet ID) plus name and birth info.[web:75]

The agent should:

1. Read `biofile.csv`.
2. Normalize column names.
3. Either:
   - Load into a dedicated `baseball.retrosheet_bio` table, or
   - Join directly to `players_xref` on `retrosheet_id` to enrich missing names.

Example table:

```sql
CREATE TABLE IF NOT EXISTS baseball.retrosheet_bio (
    retrosheet_id   VARCHAR(12) PRIMARY KEY,
    last_name       TEXT,
    first_name      TEXT,
    full_name       TEXT,
    birth_date      DATE,
    birth_city      TEXT,
    birth_state     TEXT,
    birth_country   TEXT
);
```

### 5.3 Load Retrosheet events

Event CSVs contain Retrosheet player IDs in `player_id` or similar columns.[web:77]

The agent’s tasks:

1. Parse event CSVs into one or more fact tables, e.g. `baseball.retro_events`.
2. Ensure player columns use `retrosheet_id` as text.
3. Add foreign keys to `players_xref` where feasible (optionally deferred for performance).

Example simplified schema:

```sql
CREATE TABLE IF NOT EXISTS baseball.retro_events (
    game_id         VARCHAR(20),   -- e.g. NYA201804050
    event_id        INTEGER,
    inning          INTEGER,
    batting_team    VARCHAR(3),    -- retrosheet team id
    fielding_team   VARCHAR(3),
    batter_retro_id VARCHAR(12),
    pitcher_retro_id VARCHAR(12),
    park_retro_id   VARCHAR(8),
    -- many more event columns...
    PRIMARY KEY (game_id, event_id)
);
```

### 5.4 Linking Retrosheet events to MLBAM IDs

Use `players_xref` to resolve MLBAM IDs for batters and pitchers.

```sql
CREATE OR REPLACE VIEW baseball.retro_events_resolved AS
SELECT
    e.*,
    pb.mlbam_id AS batter_mlbam_id,
    pp.mlbam_id AS pitcher_mlbam_id
FROM baseball.retro_events e
LEFT JOIN baseball.players_xref pb
    ON pb.retrosheet_id = e.batter_retro_id
LEFT JOIN baseball.players_xref pp
    ON pp.retrosheet_id = e.pitcher_retro_id;
```

The agent can use this view to join Retrosheet events directly to Statcast data on MLBAM ID.

---

## 6. Agent Workflow: Ingest Statcast Data and Link to Xref

### 6.1 Obtaining Statcast CSVs

The agent has two main options:

1. Use an external library such as `pybaseball` to download Statcast data and write it to CSV.[web:79]
2. Use Baseball Savant’s web interface, export CSVs, and place them in a known directory.[web:70]

Statcast CSV documentation notes that columns like `batter`, `pitcher`, and `fielder_2` through `fielder_9` store **MLB Player Ids**.[web:70]

### 6.2 Load Statcast CSVs

Define a canonical `statcast_events` table:

```sql
CREATE TABLE IF NOT EXISTS baseball.statcast_events (
    game_pk        INTEGER,
    at_bat_number  INTEGER,
    pitch_number   INTEGER,
    batter_mlbam   INTEGER,
    pitcher_mlbam  INTEGER,
    home_team_id   INTEGER,
    away_team_id   INTEGER,
    venue_id       INTEGER,
    -- additional Statcast columns...
    PRIMARY KEY (game_pk, at_bat_number, pitch_number)
);
```

The agent must:

1. Read each Statcast CSV.
2. Cast `batter`, `pitcher`, and team/venue columns to integers.
3. Insert into `statcast_events` using bulk COPY or batched inserts.

### 6.3 Linking Statcast to players, teams, and parks

Because Statcast already uses MLBAM IDs, linking is straightforward:

```sql
CREATE OR REPLACE VIEW baseball.statcast_events_resolved AS
SELECT
    s.*,
    p_b.full_name AS batter_name,
    p_p.full_name AS pitcher_name,
    t_home.team_retro_id AS home_team_retro,
    t_away.team_retro_id AS away_team_retro,
    pk.park_retro_id
FROM baseball.statcast_events s
LEFT JOIN baseball.players_xref p_b
    ON p_b.mlbam_id = s.batter_mlbam
LEFT JOIN baseball.players_xref p_p
    ON p_p.mlbam_id = s.pitcher_mlbam
LEFT JOIN baseball.teams_xref t_home
    ON t_home.team_mlb_id = s.home_team_id
LEFT JOIN baseball.teams_xref t_away
    ON t_away.team_mlb_id = s.away_team_id
LEFT JOIN baseball.parks_xref pk
    ON pk.park_mlb_id = s.venue_id;
```

This view exposes Retrosheet‑style identifiers alongside Statcast data, enabling unified queries.

---

## 7. Agent Workflow: Teams and Parks Mapping

### 7.1 Teams mapping

The agent should:

1. Either load a prebuilt team mapping file (SmartFantasyBaseball’s Player ID Map or similar) that already lists Retrosheet and MLB team IDs.[web:57][web:69]
2. Or construct one manually by combining:
   - Retrosheet team logs documentation for team IDs.[web:63]
   - MLB Stats API `/api/v1/teams` for MLB team IDs.[web:65]

For automated mapping:

- Fetch `/api/v1/teams?sportId=1` from the Stats API to get all MLB teams with `id` and `abbreviation`.[web:65]
- Compare abbreviations and names against a curated Retrosheet mapping file.

The agent must not assume one‑to‑one mapping purely on string equality; instead, maintain a small mapping CSV, e.g.:

```csv
team_retro_id,team_mlb_id,team_abbr,team_name,season_start,season_end
NYA,147,NYY,New York Yankees,1903,9999
BOS,111,BOS,Boston Red Sox,1901,9999
...
```

Then load this CSV into `baseball.teams_xref`.

### 7.2 Parks mapping

The agent should:

1. Download Retrosheet park information (e.g., `parkcode.txt` or similar) listing park codes, names, and cities.[web:77]
2. Query MLB Stats API `/api/v1/venues` to get `id`, `name`, and location fields for venues.[web:65]
3. Use fuzzy or manual matching on `(name, city, state)` to align Retrosheet park codes with MLB venue IDs.

Because the number of active parks is small, a partially manual mapping file is acceptable and can be stored as CSV and loaded into `parks_xref`.

---

## 8. How the Agent Should Link Everything in Practice

### 8.1 Example: join Retrosheet and Statcast for a single player

Goal: given a Retrosheet player ID, return all Statcast events for that player.

Steps for the agent:

1. Accept input `retrosheet_id` (e.g. `troutm001`).
2. Look up `mlbam_id`:

```sql
SELECT mlbam_id
FROM baseball.players_xref
WHERE retrosheet_id = :retrosheet_id;
```

3. Use `mlbam_id` to query Statcast events:

```sql
SELECT *
FROM baseball.statcast_events
WHERE batter_mlbam = :mlbam_id
   OR pitcher_mlbam = :mlbam_id;
```

4. Optionally join to the `*_resolved` views for names and team context.

### 8.2 Example: join team‑level Retrosheet and Statcast

1. Input: Retrosheet team ID `NYA`.
2. Resolve MLB team ID:

```sql
SELECT team_mlb_id
FROM baseball.teams_xref
WHERE team_retro_id = 'NYA'
  AND season_start <= :season
  AND season_end >= :season;
```

3. Use `team_mlb_id` to query Statcast data where `home_team_id` or `away_team_id` matches.

### 8.3 Example: park‑level queries

1. Input: Retrosheet park ID `NYC01`.
2. Resolve MLB venue ID:

```sql
SELECT park_mlb_id
FROM baseball.parks_xref
WHERE park_retro_id = 'NYC01';
```

3. Use `park_mlb_id` to query Statcast events where `venue_id = park_mlb_id`.

---

## 9. Maintenance and Quality Checks for the Agent

The agent should implement recurring tasks to keep mappings accurate.

### 9.1 Periodic refresh

- Schedule a job (e.g., weekly or monthly) to re-download the Chadwick Register and re-run the ingestion pipeline.[web:71][web:79]
- When the register schema changes (column additions or splits), the agent must adjust column selection logic accordingly.[web:67]

### 9.2 Consistency validations

For each refresh, the agent should:

- Compare counts of unique `mlbam_id` between `players_xref_stage` and `players_xref`.
- Log the number of new and updated players.
- Run sample queries to ensure that a few known players (e.g., high‑profile star players) have consistent mappings across Retrosheet, Statcast, and Stats API sources.[web:76][web:78]

### 9.3 Handling missing IDs

Some historical players will not have MLBAM IDs (e.g., 19th‑century players). For such rows, the agent must:

- Keep `mlbam_id` null.
- Still store and use Retrosheet and other IDs for Retrosheet‑only analyses.

The agent must never fabricate IDs; all IDs must be sourced from authoritative data.[web:71][web:76]

---

## 10. Summary of Agent Responsibilities

For clarity, the agent’s tasks can be summarized as a reproducible pipeline:

1. **Download and parse the Chadwick Register** into a local CSV/DataFrame and then into `baseball.players_xref`.[web:71][web:76]
2. **Download and ingest Retrosheet data** (events, bios, team logs, parks) into normalized tables keyed by Retrosheet IDs.[web:66][web:75][web:77]
3. **Ingest Statcast CSVs** into `baseball.statcast_events`, preserving MLBAM IDs.[web:70]
4. **Maintain `teams_xref` and `parks_xref`** tables linking Retrosheet IDs to MLB team and venue IDs, pulled from Stats API and curated mapping files.[web:63][web:65]
5. **Expose resolved views** (`retro_events_resolved`, `statcast_events_resolved`) that join fact tables through the xref dimensions.
6. **Provide query patterns** that accept any ID type (Retrosheet, MLBAM, etc.) and translate it into the canonical keys via the xref tables.

Executed correctly, this setup allows any downstream tool or AI agent to treat MLB data as if there were a single unified ID system, while still preserving all of the nuance and history from Retrosheet and other sources.[web:71][web:69][web:79]