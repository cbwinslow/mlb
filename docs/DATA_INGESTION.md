# Data Ingestion Guide

This document is a quick-start reference for ingestion CLI usage and source endpoints.
For the full ingestion architecture — lifecycle stages, control tables, chunking strategy, live ingestion model, and player identity integration — see [`docs/ingestion.md`](ingestion.md).

## Ingestion Priority (Phase 1)

1. **MLBAM StatsAPI** — Schedule, teams, players, boxscores (free, JSON)
2. **Retrosheet** — Historical game logs, event files (free, CSV/text)
3. **Statcast via pybaseball** — Pitch-by-pitch data (free, CSV via Baseball Savant)
4. **Baseball Reference** — Season stats tables (scraping, use sparingly)

## Before First Statcast Ingest — Seed Player Identities

Before loading any Statcast data, seed `stg.player_identity` from the Chadwick Bureau Register. This pre-resolves historical player identities so the auto-insert trigger only needs to handle genuine new debuts:

```bash
python scripts/enrich_player_identity.py --mode=seed-chadwick
```

See [`docs/external-tools.md`](external-tools.md) for the full weekly maintenance checklist and [`docs/player_identity_design.md`](player_identity_design.md) for the complete identity pipeline design.

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
- `/people/{personId}?hydrate=xrefIds` — player + cross-source IDs (Retrosheet, Lahman, etc.)
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

**Note:** Every Statcast pitch row carries `batter` and `pitcher` MLBAM IDs. A database trigger automatically creates identity placeholders for any unseen player. Run the enrichment worker after bulk loads to resolve those placeholders.

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
