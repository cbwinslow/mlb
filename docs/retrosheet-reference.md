# Retrosheet — Complete Reference & PostgreSQL Ingestion Guide

> **Project context:** This document covers everything needed to understand the Retrosheet data ecosystem, its available file types, all supporting tools and GitHub repositories, and a complete PostgreSQL DDL for the `raw_retrosheet` schema. This is the authoritative reference for the MLB analytics pipeline.

***

## Table of Contents

1. [What Is Retrosheet?](#what-is-retrosheet)
2. [Coverage & Scale](#coverage--scale)
3. [Data Offered by Retrosheet](#data-offered-by-retrosheet)
   - [Event Files (Play-by-Play)](#event-files-play-by-play)
   - [Box Score Event Files](#box-score-event-files)
   - [Game Logs](#game-logs)
   - [CSV Download Package](#csv-download-package)
   - [Biographical / Reference Files](#biographical--reference-files)
   - [Schedules & Rosters](#schedules--rosters)
   - [Miscellaneous / Supplemental](#miscellaneous--supplemental)
4. [The Raw File Format Problem](#the-raw-file-format-problem)
5. [Tools & Repos Ecosystem](#tools--repos-ecosystem)
   - [Chadwick Bureau Tools (cwevent / cwgame)](#chadwick-bureau-tools-cwevent--cwgame)
   - [chadwickbureau/retrosheet (GitHub Mirror)](#chadwickbureauretrosheet-github-mirror)
   - [wellsoliver/py-retrosheet](#wellsoliverpy-retrosheet)
   - [calestini/retrosheet](#calestiniretrosheet)
   - [pyretrosheet (PyPI)](#pyretrosheet-pypi)
   - [davidbmitchell/Baseball-PostgreSQL](#davidbmitchellbaseball-postgresql)
   - [sdiehl28/baseball-analytics](#sdiehl28baseball-analytics)
6. [Recommended Ingestion Process Flow](#recommended-ingestion-process-flow)
7. [PostgreSQL DDL — raw_retrosheet Schema](#postgresql-ddl--raw_retrosheet-schema)
   - [Schema Setup](#schema-setup)
   - [game_info](#game_info)
   - [events (play-by-play)](#events-play-by-play)
   - [game_log](#game_log)
   - [batting](#batting)
   - [pitching](#pitching)
   - [fielding](#fielding)
   - [team_stats](#team_stats)
   - [players](#players)
   - [rosters](#rosters)
   - [bio_people](#bio_people)
   - [ballparks](#ballparks)
   - [teams](#teams)
   - [umpires](#umpires)
   - [managers](#managers)
   - [coaches](#coaches)
   - [relatives](#relatives)
   - [schedules](#schedules)
8. [Loading Data with COPY](#loading-data-with-copy)
9. [Important Notes & Gotchas](#important-notes--gotchas)
10. [License & Attribution](#license--attribution)

***

## What Is Retrosheet?

Retrosheet is a nonprofit, all-volunteer organization founded to computerize play-by-play accounts of as many historical Major League Baseball games as possible. It is the gold standard for free historical MLB data. The organization collects, verifies, and publishes granular game data going back to the 1800s, with full play-by-play detail available from 1910 onward for most seasons.

The data is free to use for any purpose (including commercial) with a required attribution statement. Retrosheet is headquartered in Newark, DE and can be contacted at `tthress@retrosheet.org`.

**Website:** https://www.retrosheet.org  
**Discussion group:** https://groups.io/g/RetroList

***

## Coverage & Scale

| Metric | Value |
|---|---|
| Total games covered (any data) | 224,877 |
| Games with box scores | 221,443 |
| Games with full play-by-play event files | 205,886 |
| Deduced play-by-play games included in above | 5,186 |
| Total individual plays across all event files | 16,538,512 |
| Earliest season with any data | 1871 |
| Earliest season with full play-by-play | 1910 (most seasons) |
| Most recent season | 2025 |
| Coverage includes | Regular season, All-Star, Postseason, Negro League |

***

## Data Offered by Retrosheet

### Event Files (Play-by-Play)

The core Retrosheet product. Each event file encodes a full play-by-play account of a game using the Retrosheet scoring notation. Each file covers one team's home games for one season.

**File naming convention:** `[YEAR][TEAM].EVA` (AL teams) or `[YEAR][TEAM].EVN` (NL teams)

**Download URL pattern:** `https://www.retrosheet.org/events/[YEAR]eve.zip`

**Download by decade:** `https://www.retrosheet.org/events/[DECADE]seve.zip`  
Example: `https://www.retrosheet.org/events/2010seve.zip`

**Available seasons:** 1910–2025 (individual), plus 1910-1919 through 2020-2025 as decade bundles

**Internal record types per game file:**

| Record Type | Description |
|---|---|
| `id` | Unique game identifier (e.g., `NYA202104010`) |
| `version` | Format version number |
| `info` | Game metadata — date, site, teams, umpires, attendance, etc. |
| `start` | Starting lineup entries |
| `sub` | Substitution entries |
| `play` | Individual play records — the primary data rows |
| `data` | Earned run data |
| `com` | Comments |
| `badj` | Batting order adjustment |
| `padj` | Pitching adjustment |
| `ladj` | Lineup adjustment |

**The `play` record** is the most important row type. Its fields encode:

| Field | Description |
|---|---|
| Inning | Inning number |
| Team flag | 0 = visiting, 1 = home |
| Player ID | Retrosheet player ID of the batter |
| Count | Ball-strike count when event occurred |
| Pitches | Pitch-by-pitch sequence string |
| Event | Play description in Retrosheet scoring notation |

> **Important:** Raw event files cannot be loaded directly into a database. They require Chadwick tools (`cwevent`) or a parsing library to be converted to flat CSV. See the process flow section.

***

### Box Score Event Files

Where full play-by-play data does not exist (primarily pre-1910 and some gaps), Retrosheet has box score event files. These provide game-level box score summaries derived from newspaper accounts rather than full pitch-by-pitch detail. They use the same `.EV*` format but with limited record types.

**Available:** 1871–2025 (coverage is sparser for older seasons)  
**Download URL pattern:** `https://www.retrosheet.org/events/[YEAR]box.zip`

Also available as decade bundles: `https://www.retrosheet.org/events/[DECADE]sbox.zip`

**Special game collections:**
- All-Star games: `https://www.retrosheet.org/events/allas.zip` (individual years also available)
- Postseason games: `https://www.retrosheet.org/events/allpost.zip`
- Negro League event files: `https://www.retrosheet.org/events/allevr.zip`
- Negro League box score files: `https://www.retrosheet.org/events/allebr.zip`
- All All-Star + Postseason combined: `https://www.retrosheet.org/events/allebe.zip`

***

### Game Logs

Game logs are pre-summarized per-game files covering a large number of box-score fields (161 columns) for every game. They are much easier to ingest than event files because they are already structured as delimited text — no Chadwick tools required.

**Download:** `https://www.retrosheet.org/gamelogs/index.html` (individual years or decade bundles)

**Coverage:** 1871–2025

**Key game log fields (selected):**

| Field | Description |
|---|---|
| Date | Game date (YYYYMMDD) |
| GameNum | Doubleheader number (0=single, 1=first game, 2=second) |
| VisTeam | Visiting team code |
| HmTeam | Home team code |
| ParkID | Park identifier |
| VisScore | Visiting team score |
| HmScore | Home team score |
| Length_Outs | Length in outs (27 = complete 9-inning game) |
| TimeOfGame | Duration in minutes |
| DayNight | D/N flag |
| Attendance | Paid attendance |
| VisStartPitcher | Retrosheet ID of visiting starter |
| HmStartPitcher | Retrosheet ID of home starter |
| VisAB, VisH, VisD, VisT, VisHR, VisRBI | Visiting batting line |
| HmAB, HmH, HmD, HmT, HmHR, HmRBI | Home batting line |
| ... and 130+ additional columns | See `game_log_header.csv` on the Retrosheet site |

***

### CSV Download Package

Retrosheet also provides a pre-processed, labeled CSV package that eliminates the need to run Chadwick tools. This is the recommended quick-start data source.

**Main CSV download:** `https://www.retrosheet.org/downloads/csvdownloads.zip` (~330 MB)  
**Simplified CSV (stattype = 'value' only):** `https://www.retrosheet.org/downloads/basiccsvs.zip`

**Contains seven master CSV files:**

| File | Description | Grain |
|---|---|---|
| `allplayers.csv` | Basic info on all players, divided by team-season | Player × Team × Season |
| `gameinfo.csv` | Game-level metadata: teams, attendance, umpires, weather, etc. | Game |
| `teamstats.csv` | Team-level stats: line scores, lineups, batting/pitching/fielding | Team × Game |
| `batting.csv` | Batting statistics | Player × Game |
| `pitching.csv` | Pitching statistics | Player × Game |
| `fielding.csv` | Fielding statistics by position | Player × Position × Game |
| `plays.csv` | Parsed play-by-play for all games with event files (including deduced) | Play |

> **Coverage note:** These files cover all 224,877 games from 1898–2025, including Negro League, All-Star, and postseason games.

**The `stattype` column** appears in all stat tables and takes one of four values:

| Value | Meaning |
|---|---|
| `value` | Retrosheet's best estimate of actual totals |
| `lower` | Lower bound (used for some Negro League records with uncertainty) |
| `upper` | Upper bound (same use case) |
| `official` | Official league totals where they differ from Retrosheet's estimate |

***

### Biographical / Reference Files

**Biographical download:** `https://www.retrosheet.org/downloads/biodata.zip`

Contains seven CSV files:

| File | Description |
|---|---|
| `biofile0.csv` | Biographical info on all people: players, coaches, managers, umpires |
| `ballparks0.csv` | All ballparks appearing in the database |
| `teams0.csv` | All teams in the database |
| `managers0.csv` | All in-game managers per game |
| `coaches0.csv` | Coaches by team-season |
| `umpires0.csv` | All umpires per game |
| `relatives.csv` | Relationships between people in biofile |

For ballparks, managers, teams, and umpires, each entry includes `first_g` and `last_g` (format: `YYYYMMDD`) indicating the chronological first and last appearance in the database.

***

### Schedules & Rosters

These are separate reference downloads available on the Retrosheet event file page:

| Resource | URL | Description |
|---|---|---|
| Annual Rosters (1871–2025) | `https://www.retrosheet.org/rosters.zip` | Per-team, per-season roster files in `.ROS` format |
| Ballpark codes | `https://www.retrosheet.org/ballparks.zip` | Park code lookup |
| Franchise/Team IDs | `https://www.retrosheet.org/teams.zip` | Team code lookup |
| Player/Manager/Coach/Umpire IDs | `https://www.retrosheet.org/biofile.zip` | All people IDs |
| Schedule files | Per-season on `retrosheet.org/schedule/` | Pre-season schedules |

**Roster file format (`.ROS`):** CSV-like with fields: `playerID, lastName, firstName, bats, throws, teamID, position`

***

### Miscellaneous / Supplemental

- **Discrepancy files:** Where Retrosheet's totals disagree with official league records, decade-by-decade files document the discrepancies. Available: 1898–1986.
- **CSV data subsets:** Retrosheet offers smaller subsets for specific eras or leagues. Described at `https://www.retrosheet.org/downloads/othercsvs.html`.
- **Daily team/player logs (CSV):** A summary CSV covering daily stats at the team and player level. Download described at `https://www.retrosheet.org/downloads/csvdownloads.html`.

***

## The Raw File Format Problem

This is the source of most pain. The raw Retrosheet event files (`.EVA`, `.EVN`) are **not** tabular. They use a custom Retrosheet scoring notation where each game is encoded as a series of typed records. You cannot `COPY` them directly into Postgres.

**To get tabular data from raw event files, you have two options:**

1. **Run Chadwick tools** (`cwevent`, `cwgame`, `cwsub`) against the `.EVA`/`.EVN` files to produce flat CSVs, then `COPY` those CSVs into Postgres staging tables.
2. **Download the pre-processed CSV package** from `retrosheet.org/downloads/csvdownloads.zip` — this is already flat and labeled, and is the fastest path to a populated database.

> **Recommendation:** For this project's ingestion pipeline, use the pre-processed CSV package as the primary source. Use raw event files + Chadwick only if you need custom field-level control or are extending to fields the CSV package doesn't include.

***

## Tools & Repos Ecosystem

### Chadwick Bureau Tools (cwevent / cwgame)

The authoritative C-based parser for Retrosheet event files. Part of the Chadwick Baseball Bureau open-source project.

- **Repo:** https://github.com/chadwickbureau/chadwick
- **Key binaries:** `cwevent` (play-by-play), `cwgame` (game-level), `cwsub` (substitution), `cwbox` (box score)
- **Usage:** `cwevent -y 2023 -f 0-96 2023NYA.EVA 2023NYN.EVN > events_2023.csv`
- **Output:** Flat CSV with 96 columns per play (cwevent) or 161 columns per game (cwgame)
- **Install:** Available via package managers on Linux, or build from source

**This is the official parser.** All Python libraries that parse event files ultimately wrap or replicate what Chadwick does.

***

### chadwickbureau/retrosheet (GitHub Mirror)

- **URL:** https://github.com/chadwickbureau/retrosheet
- **What it is:** A maintained GitHub mirror of all Retrosheet source data files. Not a parser or database loader — it is the raw data.
- **Branches:**
  - `official` — Direct copy of upstream Retrosheet files
  - `master` — Augmented with Chadwick Bureau errata and additional metadata
- **Contents:** Organized into top-level folders including `gamelog/`, `reference/`, `seasons/`
- **Use case:** Clone this repo and you have a versionable, git-managed copy of all Retrosheet source files without scripting a custom downloader. You can then write straightforward ingestion scripts that read from the local clone.
- **Verdict:** ✅ Clone this as your raw data source. Skip building a custom downloader entirely.

```bash
git clone https://github.com/chadwickbureau/retrosheet.git
```

***

### wellsoliver/py-retrosheet

- **URL:** https://github.com/wellsoliver/py-retrosheet
- **What it is:** Python scripts for downloading Retrosheet data and parsing it into a SQL database
- **Key scripts:**
  - `scripts/download.py` — Downloads event files (configurable via `config.ini`, supports `-y YYYY` year flag)
  - `parse.py` — Parses event files and ingests into a database via SQLAlchemy
- **Database support:** PostgreSQL (via `psycopg2`), MySQL, SQLite
- **Schema:** Ships with a `.postgres.sql` schema file — **this is a usable starting point for your DDL**
- **Requirements:** Python 3.8+, Chadwick tools installed (it shells out to `cwevent`)
- **Verdict:** ⚠️ Usable but older; relies on Chadwick being installed separately. Good for schema reference.

***

### calestini/retrosheet

- **URL:** https://github.com/calestini/retrosheet
- **What it is:** Pure Python library to download and parse Retrosheet data into CSVs
- **Usage:**
  ```python
  from retrosheet import Retrosheet
  rs = Retrosheet()
  rs.batch_parse(yearFrom=1921, yearTo=2017, batchsize=10)
  ```
- **Output CSVs:** `plays.csv`, `teams.csv`, `rosters.csv`, `lineup.csv`, `pitching.csv`, `fielding.csv`, `batting.csv`, `running.csv`, `info.csv`
- **Verdict:** ✅ Good for bulk CSV generation; output files can be loaded into Postgres with COPY

***

### pyretrosheet (PyPI)

- **PyPI:** https://pypi.org/project/pyretrosheet/
- **Install:** `pip install pyretrosheet`
- **What it is:** A Python-native library (no C dependencies) that downloads, parses, and enriches Retrosheet MLB data using Python object representations
- **Strengths:** Clean Pythonic API; no need to install Chadwick separately; includes data enrichment utilities
- **Best for:** Python-first workflows where you want to work with play objects directly rather than raw CSVs
- **Verdict:** ✅ Best option for Python-native access without Chadwick dependency

***

### davidbmitchell/Baseball-PostgreSQL

- **URL:** https://github.com/davidbmitchell/Baseball-PostgreSQL
- **What it is:** A PostgreSQL schema and loader script project specifically designed for Retrosheet + Lahman data
- **Key files:**
  - `retrosheet/ddl/schema.sql` — Table definitions for a Retrosheet Postgres database
  - `retrosheet/ddl/copy_events.sql` — `COPY` commands for event data
  - `retrosheet/ddl/copy_games.sql` — `COPY` commands for game-level data
  - `retrosheet/ddl/copy_misc.sql` — `COPY` commands for reference tables
  - `retrosheet/ddl/indices.sql` — Index creation script
- **Verdict:** ✅ Best DDL reference repo; use this for table definitions and adapt to your schema naming conventions

***

### sdiehl28/baseball-analytics

- **URL:** https://github.com/sdiehl28/baseball-analytics
- **What it is:** End-to-end Python project that downloads, parses, and wrangles both Lahman and Retrosheet data into tidy CSVs for analysis
- **Strengths:** Covers the full pipeline from download to tidy output; good reference for wrangling logic
- **Verdict:** 📖 Best reference for understanding the full ETL logic even if you don't adopt it wholesale

***

## Recommended Ingestion Process Flow

This is the recommended architecture for getting Retrosheet data into PostgreSQL cleanly and repeatably.

```
┌──────────────────────────────────────────────────────────────────┐
│  STEP 1: Acquire Source Data                                     │
│                                                                  │
│  Option A (fastest): Download Retrosheet CSV package             │
│    curl -O https://www.retrosheet.org/downloads/csvdownloads.zip │
│    unzip csvdownloads.zip -d data/retrosheet/csv/                │
│                                                                  │
│  Option B (versioned): Clone Chadwick mirror                     │
│    git clone https://github.com/chadwickbureau/retrosheet.git    │
│    → then run Chadwick tools to produce CSVs from .EV* files     │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  STEP 2 (only if using raw event files): Run Chadwick            │
│                                                                  │
│  for year in $(seq 1910 2025); do                                │
│    cwevent -y $year -f 0-96 data/${year}*.EV* >> events_all.csv  │
│    cwgame  -y $year -f 0-83 data/${year}*.EV* >> games_all.csv   │
│  done                                                            │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  STEP 3: Create raw_retrosheet schema in PostgreSQL              │
│                                                                  │
│  psql -U postgres -d mlb -f ddl/raw_retrosheet_schema.sql        │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  STEP 4: Load CSVs with COPY                                     │
│                                                                  │
│  \COPY raw_retrosheet.game_info FROM 'gameinfo.csv'              │
│       WITH (FORMAT CSV, HEADER TRUE, NULL '');                   │
│  \COPY raw_retrosheet.batting   FROM 'batting.csv'               │
│       WITH (FORMAT CSV, HEADER TRUE, NULL '');                   │
│  ... repeat for all tables                                       │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  STEP 5: Build analytical schema on top of raw                   │
│                                                                  │
│  CREATE TABLE analytics.batting AS                               │
│  SELECT ... FROM raw_retrosheet.batting                          │
│  WHERE stattype = 'value';                                       │
└──────────────────────────────────────────────────────────────────┘
```

**Key principle:** Keep `raw_retrosheet` as a faithful landing zone — minimal transformations, nullable everything. Build your clean analytical tables in a separate schema (e.g., `analytics` or `baseball`).

***

## PostgreSQL DDL — raw_retrosheet Schema

The following DDL is derived from the Retrosheet CSV file structure, `davidbmitchell/Baseball-PostgreSQL`, `wellsoliver/py-retrosheet`, and the official Retrosheet file format documentation. Column names match Retrosheet's CSV export headers where applicable.

### Schema Setup

```sql
-- Create the raw landing schema
CREATE SCHEMA IF NOT EXISTS raw_retrosheet;
```

***

### game_info

Game-level metadata from `gameinfo.csv`. One row per game.

```sql
CREATE TABLE raw_retrosheet.game_info (
    game_id          VARCHAR(20)  NOT NULL,  -- e.g. NYA202304010
    game_dt          DATE,                   -- game date
    game_seq         SMALLINT,               -- doubleheader sequence (0/1/2)
    home_team        CHAR(3),
    away_team        CHAR(3),
    park_id          VARCHAR(10),
    home_team_league CHAR(1),                -- A/N
    away_team_league CHAR(1),
    ump_home         VARCHAR(10),            -- Retrosheet ID of home plate ump
    ump_1b           VARCHAR(10),
    ump_2b           VARCHAR(10),
    ump_3b           VARCHAR(10),
    ump_lf           VARCHAR(10),
    ump_rf           VARCHAR(10),
    away_score       SMALLINT,
    home_score       SMALLINT,
    innings          SMALLINT,               -- number of innings played
    day_night        CHAR(1),                -- D/N
    field_cond       VARCHAR(15),            -- drizzle, dry, wet, etc.
    precip           VARCHAR(15),
    sky              VARCHAR(15),
    temp             SMALLINT,               -- temperature in F
    wind_dir         VARCHAR(15),
    wind_speed       SMALLINT,               -- mph
    attendance       INTEGER,
    game_minutes     SMALLINT,               -- duration in minutes
    away_line_score  VARCHAR(30),
    home_line_score  VARCHAR(30),
    winning_pitcher  VARCHAR(10),
    losing_pitcher   VARCHAR(10),
    save_pitcher     VARCHAR(10),
    gwinrbi          VARCHAR(10),            -- game-winning RBI player ID
    game_type        VARCHAR(10),            -- regular/postseason/allstar/negro
    completion       VARCHAR(30),            -- completion game info if applicable
    forfeit          CHAR(1),
    protest          CHAR(1),
    CONSTRAINT pk_game_info PRIMARY KEY (game_id)
);

CREATE INDEX idx_game_info_dt     ON raw_retrosheet.game_info (game_dt);
CREATE INDEX idx_game_info_home   ON raw_retrosheet.game_info (home_team);
CREATE INDEX idx_game_info_away   ON raw_retrosheet.game_info (away_team);
```

***

### events (play-by-play)

Loaded from `plays.csv` (pre-processed) or from `cwevent` output. One row per play. This is the largest table (~16.5 million rows).

```sql
CREATE TABLE raw_retrosheet.events (
    game_id              VARCHAR(20)  NOT NULL,
    event_id             INTEGER      NOT NULL,  -- sequential within game
    inning               SMALLINT,
    batting_team         SMALLINT,               -- 0=visitor, 1=home
    batter               VARCHAR(10),            -- Retrosheet player ID
    batter_hand          CHAR(1),                -- L/R
    res_batter           VARCHAR(10),
    res_batter_hand      CHAR(1),
    pitcher              VARCHAR(10),
    pitcher_hand         CHAR(1),
    res_pitcher          VARCHAR(10),
    res_pitcher_hand     CHAR(1),
    catcher              VARCHAR(10),
    first_base           VARCHAR(10),
    second_base          VARCHAR(10),
    third_base           VARCHAR(10),
    shortstop            VARCHAR(10),
    left_field           VARCHAR(10),
    center_field         VARCHAR(10),
    right_field          VARCHAR(10),
    first_runner         VARCHAR(10),            -- runner on 1B before play
    second_runner        VARCHAR(10),
    third_runner         VARCHAR(10),
    event_text           VARCHAR(50),            -- raw scoring notation
    leadoff_fl           BOOLEAN,
    ph_fl                BOOLEAN,                -- pinch-hit flag
    bat_fielder_pos      SMALLINT,               -- defensive position of batter
    event_cd             SMALLINT,               -- Chadwick event code
    bat_event_fl         BOOLEAN,                -- batter involved in event
    ab_fl                BOOLEAN,                -- at-bat flag
    h_fl                 SMALLINT,               -- hit flag
    sh_fl                BOOLEAN,                -- sacrifice hit
    sf_fl                BOOLEAN,                -- sacrifice fly
    outs_ct              SMALLINT,               -- outs before the play
    ball_ct              SMALLINT,
    strike_ct            SMALLINT,
    pitch_seq            VARCHAR(40),            -- full pitch sequence string
    away_score_ct        SMALLINT,
    home_score_ct        SMALLINT,
    runs_ct              SMALLINT,               -- runs scored on this play
    rbi_ct               SMALLINT,
    wp_fl                BOOLEAN,                -- wild pitch
    pb_fl                BOOLEAN,                -- passed ball
    field_cd             SMALLINT,
    battedball_cd        CHAR(1),                -- G/L/F/P
    bunt_fl              BOOLEAN,
    foul_fl              BOOLEAN,
    battedball_loc_tx    VARCHAR(10),            -- hit location code
    err_ct               SMALLINT,
    err1_fld_cd          SMALLINT,
    err1_cd              CHAR(1),
    err2_fld_cd          SMALLINT,
    err2_cd              CHAR(1),
    err3_fld_cd          SMALLINT,
    err3_cd              CHAR(1),
    bat_dest_id          SMALLINT,               -- batter destination (base)
    run1_dest_id         SMALLINT,
    run2_dest_id         SMALLINT,
    run3_dest_id         SMALLINT,
    run1_src_event_id    INTEGER,
    run2_src_event_id    INTEGER,
    run3_src_event_id    INTEGER,
    run1_resp_pit        VARCHAR(10),            -- pitcher responsible for runner on 1B
    run2_resp_pit        VARCHAR(10),
    run3_resp_pit        VARCHAR(10),
    game_new_fl          BOOLEAN,                -- first event of game
    game_end_fl          BOOLEAN,                -- last event of game
    pr_run1_fl           BOOLEAN,                -- pinch runner flag
    pr_run2_fl           BOOLEAN,
    pr_run3_fl           BOOLEAN,
    removed_batter       VARCHAR(10),
    removed_batter_pos   SMALLINT,
    removed_pitcher      VARCHAR(10),
    removed_runner1      VARCHAR(10),
    removed_runner2      VARCHAR(10),
    removed_runner3      VARCHAR(10),
    fielder2             VARCHAR(10),
    fielder3             VARCHAR(10),
    fielder4             VARCHAR(10),
    fielder5             VARCHAR(10),
    fielder6             VARCHAR(10),
    fielder7             VARCHAR(10),
    fielder8             VARCHAR(10),
    fielder9             VARCHAR(10),
    CONSTRAINT pk_events PRIMARY KEY (game_id, event_id)
);

CREATE INDEX idx_events_game       ON raw_retrosheet.events (game_id);
CREATE INDEX idx_events_batter     ON raw_retrosheet.events (batter);
CREATE INDEX idx_events_pitcher    ON raw_retrosheet.events (pitcher);
CREATE INDEX idx_events_event_cd   ON raw_retrosheet.events (event_cd);
```

***

### game_log

From Retrosheet game log files (GL*.TXT). 161 columns — a pre-computed per-game summary. One row per game.

```sql
CREATE TABLE raw_retrosheet.game_log (
    game_id              VARCHAR(20),
    date                 DATE         NOT NULL,
    game_num             SMALLINT,               -- 0=single, 1=first DH, 2=second DH
    day_of_week          CHAR(3),
    away_team            CHAR(3)      NOT NULL,
    away_league          CHAR(1),
    away_game_num        SMALLINT,
    home_team            CHAR(3)      NOT NULL,
    home_league          CHAR(1),
    home_game_num        SMALLINT,
    away_score           SMALLINT,
    home_score           SMALLINT,
    num_outs             SMALLINT,               -- length in outs (27=9 full innings)
    day_night            CHAR(1),
    completion_info      VARCHAR(30),
    forfeit_info         CHAR(1),
    protest_info         CHAR(1),
    park_id              VARCHAR(10),
    attendance           INTEGER,
    game_minutes         SMALLINT,
    away_line_score      VARCHAR(30),
    home_line_score      VARCHAR(30),
    away_ab              SMALLINT,
    away_h               SMALLINT,
    away_2b              SMALLINT,
    away_3b              SMALLINT,
    away_hr              SMALLINT,
    away_rbi             SMALLINT,
    away_sh              SMALLINT,
    away_sf              SMALLINT,
    away_hbp             SMALLINT,
    away_bb              SMALLINT,
    away_ibb             SMALLINT,
    away_so              SMALLINT,
    away_sb              SMALLINT,
    away_cs              SMALLINT,
    away_gdp             SMALLINT,
    away_ci              SMALLINT,
    away_lob             SMALLINT,
    away_pitchers_used   SMALLINT,
    away_er              SMALLINT,
    away_ter             SMALLINT,
    away_wp              SMALLINT,
    away_balk            SMALLINT,
    away_po              SMALLINT,
    away_assists         SMALLINT,
    away_errors          SMALLINT,
    away_pb              SMALLINT,
    away_dp              SMALLINT,
    away_tp              SMALLINT,
    home_ab              SMALLINT,
    home_h               SMALLINT,
    home_2b              SMALLINT,
    home_3b              SMALLINT,
    home_hr              SMALLINT,
    home_rbi             SMALLINT,
    home_sh              SMALLINT,
    home_sf              SMALLINT,
    home_hbp             SMALLINT,
    home_bb              SMALLINT,
    home_ibb             SMALLINT,
    home_so              SMALLINT,
    home_sb              SMALLINT,
    home_cs              SMALLINT,
    home_gdp             SMALLINT,
    home_ci              SMALLINT,
    home_lob             SMALLINT,
    home_pitchers_used   SMALLINT,
    home_er              SMALLINT,
    home_ter             SMALLINT,
    home_wp              SMALLINT,
    home_balk            SMALLINT,
    home_po              SMALLINT,
    home_assists         SMALLINT,
    home_errors          SMALLINT,
    home_pb              SMALLINT,
    home_dp              SMALLINT,
    home_tp              SMALLINT,
    ump_home_id          VARCHAR(10),
    ump_home_name        VARCHAR(40),
    ump_1b_id            VARCHAR(10),
    ump_1b_name          VARCHAR(40),
    ump_2b_id            VARCHAR(10),
    ump_2b_name          VARCHAR(40),
    ump_3b_id            VARCHAR(10),
    ump_3b_name          VARCHAR(40),
    ump_lf_id            VARCHAR(10),
    ump_lf_name          VARCHAR(40),
    ump_rf_id            VARCHAR(10),
    ump_rf_name          VARCHAR(40),
    away_manager_id      VARCHAR(10),
    away_manager_name    VARCHAR(40),
    home_manager_id      VARCHAR(10),
    home_manager_name    VARCHAR(40),
    winning_pitcher_id   VARCHAR(10),
    winning_pitcher_name VARCHAR(40),
    losing_pitcher_id    VARCHAR(10),
    losing_pitcher_name  VARCHAR(40),
    saving_pitcher_id    VARCHAR(10),
    saving_pitcher_name  VARCHAR(40),
    gwinrbi_id           VARCHAR(10),
    gwinrbi_name         VARCHAR(40),
    away_lineup_1_id     VARCHAR(10),
    away_lineup_1_name   VARCHAR(40),
    away_lineup_1_pos    SMALLINT,
    away_lineup_2_id     VARCHAR(10),
    away_lineup_2_name   VARCHAR(40),
    away_lineup_2_pos    SMALLINT,
    away_lineup_3_id     VARCHAR(10),
    away_lineup_3_name   VARCHAR(40),
    away_lineup_3_pos    SMALLINT,
    away_lineup_4_id     VARCHAR(10),
    away_lineup_4_name   VARCHAR(40),
    away_lineup_4_pos    SMALLINT,
    away_lineup_5_id     VARCHAR(10),
    away_lineup_5_name   VARCHAR(40),
    away_lineup_5_pos    SMALLINT,
    away_lineup_6_id     VARCHAR(10),
    away_lineup_6_name   VARCHAR(40),
    away_lineup_6_pos    SMALLINT,
    away_lineup_7_id     VARCHAR(10),
    away_lineup_7_name   VARCHAR(40),
    away_lineup_7_pos    SMALLINT,
    away_lineup_8_id     VARCHAR(10),
    away_lineup_8_name   VARCHAR(40),
    away_lineup_8_pos    SMALLINT,
    away_lineup_9_id     VARCHAR(10),
    away_lineup_9_name   VARCHAR(40),
    away_lineup_9_pos    SMALLINT,
    home_lineup_1_id     VARCHAR(10),
    home_lineup_1_name   VARCHAR(40),
    home_lineup_1_pos    SMALLINT,
    home_lineup_2_id     VARCHAR(10),
    home_lineup_2_name   VARCHAR(40),
    home_lineup_2_pos    SMALLINT,
    home_lineup_3_id     VARCHAR(10),
    home_lineup_3_name   VARCHAR(40),
    home_lineup_3_pos    SMALLINT,
    home_lineup_4_id     VARCHAR(10),
    home_lineup_4_name   VARCHAR(40),
    home_lineup_4_pos    SMALLINT,
    home_lineup_5_id     VARCHAR(10),
    home_lineup_5_name   VARCHAR(40),
    home_lineup_5_pos    SMALLINT,
    home_lineup_6_id     VARCHAR(10),
    home_lineup_6_name   VARCHAR(40),
    home_lineup_6_pos    SMALLINT,
    home_lineup_7_id     VARCHAR(10),
    home_lineup_7_name   VARCHAR(40),
    home_lineup_7_pos    SMALLINT,
    home_lineup_8_id     VARCHAR(10),
    home_lineup_8_name   VARCHAR(40),
    home_lineup_8_pos    SMALLINT,
    home_lineup_9_id     VARCHAR(10),
    home_lineup_9_name   VARCHAR(40),
    home_lineup_9_pos    SMALLINT,
    additional_info      VARCHAR(80),
    acquisition_info     CHAR(1),
    CONSTRAINT pk_game_log PRIMARY KEY (date, home_team, game_num)
);

CREATE INDEX idx_game_log_date      ON raw_retrosheet.game_log (date);
CREATE INDEX idx_game_log_away      ON raw_retrosheet.game_log (away_team);
CREATE INDEX idx_game_log_home      ON raw_retrosheet.game_log (home_team);
CREATE INDEX idx_game_log_park      ON raw_retrosheet.game_log (park_id);
```

***

### batting

Per-player, per-game batting statistics from `batting.csv`. One row per player per game (may have multiple rows per player/game if `stattype` varies).

```sql
CREATE TABLE raw_retrosheet.batting (
    game_id    VARCHAR(20)  NOT NULL,
    player_id  VARCHAR(10)  NOT NULL,
    team       CHAR(3),
    stattype   VARCHAR(10),                 -- value/lower/upper/official
    b_seq      SMALLINT,                    -- batting order position (1-9)
    ab         SMALLINT,
    r          SMALLINT,
    h          SMALLINT,
    tb         SMALLINT,
    h2b        SMALLINT,
    h3b        SMALLINT,
    hr         SMALLINT,
    rbi        SMALLINT,
    bb         SMALLINT,
    ibb        SMALLINT,
    so         SMALLINT,
    gdp        SMALLINT,
    hp         SMALLINT,                    -- hit by pitch
    sh         SMALLINT,                    -- sacrifice hits
    sf         SMALLINT,                    -- sacrifice flies
    sb         SMALLINT,
    cs         SMALLINT,
    xi         SMALLINT,                    -- catcher interference
    CONSTRAINT pk_batting PRIMARY KEY (game_id, player_id, stattype)
);

CREATE INDEX idx_batting_player  ON raw_retrosheet.batting (player_id);
CREATE INDEX idx_batting_game    ON raw_retrosheet.batting (game_id);
CREATE INDEX idx_batting_team    ON raw_retrosheet.batting (team);
```

***

### pitching

Per-player, per-game pitching statistics from `pitching.csv`.

```sql
CREATE TABLE raw_retrosheet.pitching (
    game_id    VARCHAR(20)  NOT NULL,
    player_id  VARCHAR(10)  NOT NULL,
    team       CHAR(3),
    stattype   VARCHAR(10),
    outs       SMALLINT,                    -- outs recorded (3 = 1 full IP)
    bfp        SMALLINT,                    -- batters faced
    ab         SMALLINT,
    r          SMALLINT,
    er         SMALLINT,
    h          SMALLINT,
    tb         SMALLINT,
    h2b        SMALLINT,
    h3b        SMALLINT,
    hr         SMALLINT,
    bb         SMALLINT,
    ibb        SMALLINT,
    so         SMALLINT,
    gdp        SMALLINT,
    hp         SMALLINT,
    sh         SMALLINT,
    sf         SMALLINT,
    sb         SMALLINT,
    cs         SMALLINT,
    wp         SMALLINT,
    bk         SMALLINT,
    pk         SMALLINT,                    -- pickoffs
    xi         SMALLINT,
    game_seq   SMALLINT,                    -- appearance order within game
    win_fl     BOOLEAN,
    loss_fl    BOOLEAN,
    save_fl    BOOLEAN,
    finish_fl  BOOLEAN,                     -- game finishing pitcher flag
    CONSTRAINT pk_pitching PRIMARY KEY (game_id, player_id, stattype)
);

CREATE INDEX idx_pitching_player ON raw_retrosheet.pitching (player_id);
CREATE INDEX idx_pitching_game   ON raw_retrosheet.pitching (game_id);
CREATE INDEX idx_pitching_team   ON raw_retrosheet.pitching (team);
```

***

### fielding

Per-player, per-position, per-game fielding statistics from `fielding.csv`.

```sql
CREATE TABLE raw_retrosheet.fielding (
    game_id    VARCHAR(20)  NOT NULL,
    player_id  VARCHAR(10)  NOT NULL,
    team       CHAR(3),
    pos        SMALLINT     NOT NULL,       -- 1=P, 2=C, 3=1B, ... 9=RF, 10=DH
    stattype   VARCHAR(10),
    outs       SMALLINT,                    -- outs played at this position
    tc         SMALLINT,                    -- total chances
    po         SMALLINT,                    -- putouts
    a          SMALLINT,                    -- assists
    e          SMALLINT,                    -- errors
    dp         SMALLINT,
    tp         SMALLINT,
    pb         SMALLINT,                    -- passed balls (catchers only)
    xi         SMALLINT,                    -- catcher interference
    CONSTRAINT pk_fielding PRIMARY KEY (game_id, player_id, pos, stattype)
);

CREATE INDEX idx_fielding_player ON raw_retrosheet.fielding (player_id);
CREATE INDEX idx_fielding_game   ON raw_retrosheet.fielding (game_id);
```

***

### team_stats

Per-team, per-game statistics from `teamstats.csv`. Includes team batting, pitching, and fielding totals for each game.

```sql
CREATE TABLE raw_retrosheet.team_stats (
    game_id        VARCHAR(20)  NOT NULL,
    team           CHAR(3)      NOT NULL,
    team_flag      CHAR(1),                 -- H=home, V=visitor
    stattype       VARCHAR(10),
    score          SMALLINT,
    -- Batting
    ab             SMALLINT,
    r              SMALLINT,
    h              SMALLINT,
    tb             SMALLINT,
    h2b            SMALLINT,
    h3b            SMALLINT,
    hr             SMALLINT,
    rbi            SMALLINT,
    bb             SMALLINT,
    ibb            SMALLINT,
    so             SMALLINT,
    gdp            SMALLINT,
    hp             SMALLINT,
    sh             SMALLINT,
    sf             SMALLINT,
    sb             SMALLINT,
    cs             SMALLINT,
    xi             SMALLINT,
    lob            SMALLINT,
    -- Pitching
    er             SMALLINT,
    wp             SMALLINT,
    bk             SMALLINT,
    -- Fielding
    e              SMALLINT,
    dp             SMALLINT,
    tp             SMALLINT,
    pb             SMALLINT,
    CONSTRAINT pk_team_stats PRIMARY KEY (game_id, team, stattype)
);

CREATE INDEX idx_team_stats_game ON raw_retrosheet.team_stats (game_id);
CREATE INDEX idx_team_stats_team ON raw_retrosheet.team_stats (team);
```

***

### players

Basic player information from `allplayers.csv`. One row per player per team-season.

```sql
CREATE TABLE raw_retrosheet.players (
    player_id     VARCHAR(10)  NOT NULL,
    team          CHAR(3)      NOT NULL,
    season        SMALLINT     NOT NULL,
    last_name     VARCHAR(40),
    first_name    VARCHAR(40),
    bats          CHAR(1),                  -- L/R/B/S (switch)
    throws        CHAR(1),                  -- L/R/S
    position      VARCHAR(5),               -- primary position
    game_type     VARCHAR(10),              -- regular/postseason/allstar/negro
    CONSTRAINT pk_players PRIMARY KEY (player_id, team, season)
);

CREATE INDEX idx_players_id     ON raw_retrosheet.players (player_id);
CREATE INDEX idx_players_team   ON raw_retrosheet.players (team, season);
```

***

### rosters

From `.ROS` roster files downloaded separately. One row per player per team-season.

```sql
CREATE TABLE raw_retrosheet.rosters (
    player_id   VARCHAR(10)  NOT NULL,
    last_name   VARCHAR(40),
    first_name  VARCHAR(40),
    bats        CHAR(1),
    throws      CHAR(1),
    team_id     CHAR(3)      NOT NULL,
    position    VARCHAR(5),
    season      SMALLINT     NOT NULL,
    CONSTRAINT pk_rosters PRIMARY KEY (player_id, team_id, season)
);

CREATE INDEX idx_rosters_player ON raw_retrosheet.rosters (player_id);
CREATE INDEX idx_rosters_team   ON raw_retrosheet.rosters (team_id, season);
```

***

### bio_people

Biographical file from `biofile0.csv`. One row per person (players, managers, coaches, umpires).

```sql
CREATE TABLE raw_retrosheet.bio_people (
    retro_id       VARCHAR(10)  NOT NULL,   -- Retrosheet universal ID
    last_name      VARCHAR(40),
    first_name     VARCHAR(40),
    birth_year     SMALLINT,
    birth_month    SMALLINT,
    birth_day      SMALLINT,
    birth_country  VARCHAR(30),
    birth_state    VARCHAR(30),
    birth_city     VARCHAR(40),
    death_year     SMALLINT,
    death_month    SMALLINT,
    death_day      SMALLINT,
    death_country  VARCHAR(30),
    death_state    VARCHAR(30),
    death_city     VARCHAR(40),
    bats           CHAR(1),
    throws         CHAR(1),
    debut          DATE,
    final_game     DATE,
    lahman_id      VARCHAR(10),             -- crosswalk to Lahman database
    bbref_id       VARCHAR(15),             -- crosswalk to Baseball-Reference
    CONSTRAINT pk_bio_people PRIMARY KEY (retro_id)
);

CREATE INDEX idx_bio_lahman ON raw_retrosheet.bio_people (lahman_id);
CREATE INDEX idx_bio_bbref  ON raw_retrosheet.bio_people (bbref_id);
```

***

### ballparks

From `ballparks0.csv`.

```sql
CREATE TABLE raw_retrosheet.ballparks (
    park_id     VARCHAR(10)  NOT NULL,
    park_name   VARCHAR(80),
    park_alias  VARCHAR(80),
    city        VARCHAR(40),
    state       VARCHAR(30),
    country     VARCHAR(30),
    first_g     CHAR(8),                    -- first game YYYYMMDD
    last_g      CHAR(8),                    -- last game YYYYMMDD
    CONSTRAINT pk_ballparks PRIMARY KEY (park_id)
);
```

***

### teams

From `teams0.csv`.

```sql
CREATE TABLE raw_retrosheet.teams (
    team_id     CHAR(3)      NOT NULL,
    league      CHAR(1),
    division    CHAR(1),
    location    VARCHAR(40),
    nickname    VARCHAR(40),
    alt_names   VARCHAR(80),
    first_g     CHAR(8),
    last_g      CHAR(8),
    CONSTRAINT pk_teams PRIMARY KEY (team_id)
);
```

***

### umpires

From `umpires0.csv`.

```sql
CREATE TABLE raw_retrosheet.umpires (
    ump_id      VARCHAR(10)  NOT NULL,
    last_name   VARCHAR(40),
    first_name  VARCHAR(40),
    first_g     CHAR(8),
    last_g      CHAR(8),
    CONSTRAINT pk_umpires PRIMARY KEY (ump_id)
);
```

***

### managers

From `managers0.csv`.

```sql
CREATE TABLE raw_retrosheet.managers (
    game_id     VARCHAR(20),
    manager_id  VARCHAR(10),
    team        CHAR(3),
    seq         SMALLINT,                   -- order managed during game
    CONSTRAINT pk_managers PRIMARY KEY (game_id, manager_id)
);

CREATE INDEX idx_managers_id ON raw_retrosheet.managers (manager_id);
```

***

### coaches

From `coaches0.csv`.

```sql
CREATE TABLE raw_retrosheet.coaches (
    coach_id   VARCHAR(10)  NOT NULL,
    last_name  VARCHAR(40),
    first_name VARCHAR(40),
    team_id    CHAR(3),
    season     SMALLINT,
    position   VARCHAR(20),
    first_g    CHAR(8),
    last_g     CHAR(8)
);

CREATE INDEX idx_coaches_id   ON raw_retrosheet.coaches (coach_id);
CREATE INDEX idx_coaches_team ON raw_retrosheet.coaches (team_id, season);
```

***

### relatives

From `relatives.csv`. Tracks family relationships between people in the bio file.

```sql
CREATE TABLE raw_retrosheet.relatives (
    person_id_1   VARCHAR(10),
    person_id_2   VARCHAR(10),
    relationship  VARCHAR(20)               -- father/son, brothers, etc.
);
```

***

### schedules

From per-season schedule files downloaded from Retrosheet.

```sql
CREATE TABLE raw_retrosheet.schedules (
    game_dt       DATE         NOT NULL,
    game_num      SMALLINT     DEFAULT 0,
    day_of_week   CHAR(3),
    away_team     CHAR(3)      NOT NULL,
    away_league   CHAR(1),
    away_game_num SMALLINT,
    home_team     CHAR(3)      NOT NULL,
    home_league   CHAR(1),
    home_game_num SMALLINT,
    day_night     CHAR(1),
    postponed     VARCHAR(30),
    makeup_date   DATE
);

CREATE INDEX idx_schedules_dt   ON raw_retrosheet.schedules (game_dt);
CREATE INDEX idx_schedules_home ON raw_retrosheet.schedules (home_team);
CREATE INDEX idx_schedules_away ON raw_retrosheet.schedules (away_team);
```

***

## Loading Data with COPY

Use `\COPY` from `psql` (client-side) or `COPY` from within a server session. The CSV package files all include headers.

```sql
-- From psql shell:
\COPY raw_retrosheet.game_info    FROM '/data/retrosheet/csv/gameinfo.csv'  WITH (FORMAT CSV, HEADER TRUE, NULL '');
\COPY raw_retrosheet.batting      FROM '/data/retrosheet/csv/batting.csv'   WITH (FORMAT CSV, HEADER TRUE, NULL '');
\COPY raw_retrosheet.pitching     FROM '/data/retrosheet/csv/pitching.csv'  WITH (FORMAT CSV, HEADER TRUE, NULL '');
\COPY raw_retrosheet.fielding     FROM '/data/retrosheet/csv/fielding.csv'  WITH (FORMAT CSV, HEADER TRUE, NULL '');
\COPY raw_retrosheet.team_stats   FROM '/data/retrosheet/csv/teamstats.csv' WITH (FORMAT CSV, HEADER TRUE, NULL '');
\COPY raw_retrosheet.players      FROM '/data/retrosheet/csv/allplayers.csv' WITH (FORMAT CSV, HEADER TRUE, NULL '');
\COPY raw_retrosheet.events       FROM '/data/retrosheet/csv/plays.csv'     WITH (FORMAT CSV, HEADER TRUE, NULL '');

-- Biographical files:
\COPY raw_retrosheet.bio_people   FROM '/data/retrosheet/bio/biofile0.csv'  WITH (FORMAT CSV, HEADER TRUE, NULL '');
\COPY raw_retrosheet.ballparks    FROM '/data/retrosheet/bio/ballparks0.csv' WITH (FORMAT CSV, HEADER TRUE, NULL '');
\COPY raw_retrosheet.teams        FROM '/data/retrosheet/bio/teams0.csv'    WITH (FORMAT CSV, HEADER TRUE, NULL '');
\COPY raw_retrosheet.umpires      FROM '/data/retrosheet/bio/umpires0.csv'  WITH (FORMAT CSV, HEADER TRUE, NULL '');
\COPY raw_retrosheet.coaches      FROM '/data/retrosheet/bio/coaches0.csv'  WITH (FORMAT CSV, HEADER TRUE, NULL '');
\COPY raw_retrosheet.relatives    FROM '/data/retrosheet/bio/relatives.csv' WITH (FORMAT CSV, HEADER TRUE, NULL '');
```

For Python-based ingestion (e.g., in a pipeline script):

```python
import psycopg2
import os

TABLES = [
    ("raw_retrosheet.game_info",  "gameinfo.csv"),
    ("raw_retrosheet.batting",    "batting.csv"),
    ("raw_retrosheet.pitching",   "pitching.csv"),
    ("raw_retrosheet.fielding",   "fielding.csv"),
    ("raw_retrosheet.team_stats", "teamstats.csv"),
    ("raw_retrosheet.players",    "allplayers.csv"),
    ("raw_retrosheet.events",     "plays.csv"),
]

conn = psycopg2.connect(os.environ["DATABASE_URL"])
cur  = conn.cursor()

data_dir = "/data/retrosheet/csv"

for table, filename in TABLES:
    filepath = os.path.join(data_dir, filename)
    with open(filepath, "r") as f:
        print(f"Loading {table}...")
        cur.copy_expert(
            f"COPY {table} FROM STDIN WITH (FORMAT CSV, HEADER TRUE, NULL '')",
            f
        )
    conn.commit()
    print(f"  ✓ {table} loaded")

cur.close()
conn.close()
```

***

## Important Notes & Gotchas

- **`plays.csv` is very large.** At ~16.5 million rows, loading it without indexes first is faster; add indexes after `COPY` completes.
- **Deduced event files** are included in the CSV package. These are reconstructed games where the original play-by-play no longer exists. Quality is high but not identical to games sourced from original scoresheets.
- **`stattype` filtering:** For most analytical work, filter to `stattype = 'value'`. The `lower`, `upper`, and `official` rows are present only for records with uncertainty or official discrepancies.
- **`game_id` format:** `[TEAMID][YYYYMMDD][GAMENUM]` — e.g., `NYA20230601` for the Yankees' first game on June 1, 2023, or `NYA202306012` for the second game of a doubleheader.
- **Retrosheet player IDs** are in the format `[LAST4][FIRST1][SEQNUM]` — e.g., `ruthb101` for Babe Ruth. These IDs appear consistently across all Retrosheet files and serve as the join key between tables.
- **Date formats vary** across file types. The CSV package uses `YYYYMMDD` strings in bio files and ISO date strings in the main CSVs. Cast explicitly in your ingestion queries.
- **Negro League data has wider uncertainty bounds.** Many pre-1920 and all Negro League records may have `lower`/`upper` rows in batting/pitching/fielding tables.
- **The `chadwickbureau/retrosheet` master branch** differs from the `official` branch in that Chadwick has added corrections and errata. For production use, prefer `master`.
- **Retrosheet adds new data regularly.** The Fall 2025 release added 230 games across seasons 1921–2024. Implement an incremental refresh strategy rather than full reload every time.

***

## License & Attribution

All data is copyright 1996–2026 by Retrosheet. The following attribution statement must appear prominently in any work that uses Retrosheet data:

> *The information used here was obtained free of charge from and is copyrighted by Retrosheet. Interested parties may contact Retrosheet at 20 Sunset Rd., Newark, DE 19711.*

Retrosheet data is free to redistribute, sell, or incorporate into commercial products — **with the above statement included**. No other license restrictions apply.