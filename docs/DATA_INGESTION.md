# Data Ingestion Guide

This document describes the data ingestion architecture and available sources for the MLB Analytics Platform.

## Ingestion Priority (Phase 1)

1. **MLBAM StatsAPI** — Schedule, teams, players, boxscores (free, JSON)
2. **Retrosheet** — Historical game logs, event files (free, CSV/text)
3. **Statcast via pybaseball** — Pitch-by-pitch data (free, CSV via Baseball Savant)
4. **Baseball Reference** — Season stats tables (scraping, use sparingly)

## Folder Structure

```
baseball/
└── ingest/
    ├── __init__.py
    ├── base.py           # BaseIngester ABC
    ├── mlbam.py          # MLBAM StatsAPI ingester
    ├── retrosheet.py     # Retrosheet file ingester
    ├── statcast.py       # Statcast / pybaseball ingester
    └── models.py         # Pydantic models for raw data validation
```

## MLBAM StatsAPI

Base URL: `https://statsapi.mlb.com/api/v1/`

Key endpoints:
- `/teams` — all MLB teams
- `/people/{personId}` — player details
- `/schedule?sportId=1&date=YYYY-MM-DD` — daily schedule
- `/game/{gamePk}/boxscore` — full boxscore

No API key required for public endpoints.

## Retrosheet

Download game log files from https://www.retrosheet.org/gamelogs/index.html.

Files are fixed-width CSVs. Place them in `data/retrosheet/` and run:
```bash
baseball ingest retrosheet --year 2023
```

## Statcast

Uses `pybaseball` package:
```python
from pybaseball import statcast
data = statcast(start_dt="2023-04-01", end_dt="2023-04-07")
```

Rate-limit: ~1 request/second to be respectful.

## Ingestion CLI (Planned)

```bash
# Ingest all sources for a season
baseball ingest all --year 2023

# Ingest specific source
baseball ingest mlbam --year 2023
baseball ingest retrosheet --year 2023
baseball ingest statcast --start 2023-04-01 --end 2023-10-01

# Check ingestion status
baseball ingest status
```

## MCP Server Tools (Milestone 4)

Once the MCP server is built, AI assistants will be able to query the database using tools like:

- `query_players(name, team, season)` — find players
- `query_games(date, home_team, away_team)` — find games
- `query_batting_stats(player_id, season)` — get batting stats
- `query_statcast(player_id, pitch_type, date_range)` — Statcast data
- `query_standings(season, division)` — team standings
