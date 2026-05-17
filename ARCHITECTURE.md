# MLB Analytics Platform — Architecture

## System Overview

```
┌─────────────────────────────┐
│   External Data Sources       │
│  Retrosheet | MLBAM | Statcast │
└─────────────┬───────────────┘
                 │
                 ▼
┌─────────────────────────────┐
│   Ingestion Pipeline           │
│  baseball ingest [source]      │
│  Idempotent upserts via        │
│  SQLAlchemy async              │
└─────────────┬───────────────┘
                 │
                 ▼
┌─────────────────────────────┐
│   PostgreSQL Database          │
│  Teams | Players | Games       │
│  Stats | Statcast | Logs       │
└───────┬──────────────┬────────┘
        │              │
        ▼              ▼
┌─────────────┐ ┌───────────────┐
│ MCP Server   │ │  FastAPI       │
│ AI Query     │ │  REST API      │
│ Tools        │ │  Web Frontend  │
└─────────────┘ └───────────────┘
```

## Directory Structure

```
mlb/
├── baseball/              # Python package (settings, CLI, ingestion)
├── sql/                   # PostgreSQL DDL (migrations)
│   ├── 010_extensions/
│   ├── 020_schemas/
│   ├── 030_tables/
│   ├── 040_views/
│   ├── 050_functions/
│   ├── 060_triggers/
│   ├── 070_seeds/
│   └── 090_constraints_indexes/
├── tests/                 # Test suite
│   └── sql/               # SQL smoke tests
├── docs/                  # Extended documentation
├── mcp/                   # MCP server (Milestone 4)
├── app/                   # Web app (Milestone 5)
├── docker-compose.yml     # Local dev environment
├── pyproject.toml
├── .env.example
├── ROADMAP.md
├── ARCHITECTURE.md
├── MILESTONES.md
├── CONTRIBUTING.md
└── README.md
```

## Data Flow

1. **Ingestion**: CLI command `baseball ingest [source]` fetches raw data, validates, and upserts into PostgreSQL using async SQLAlchemy.
2. **Storage**: PostgreSQL 16 with schemas for raw, staging, and analytics layers.
3. **MCP Access**: MCP server reads from the analytics schema and exposes typed query tools for AI assistants.
4. **API/App**: FastAPI reads from the same database and serves a REST API consumed by the frontend.

## Key Design Decisions

- **Async first**: All database access uses `asyncpg` + `SQLAlchemy` async engine.
- **Idempotent ingestion**: Every ingest operation uses `INSERT ... ON CONFLICT DO UPDATE` so re-runs are safe.
- **Schema-first**: DDL is source-controlled in `sql/` and applied via the CLI migration runner.
- **MCP before app**: The MCP server is built before the web app so AI tools can query the data immediately.
- **pydantic-settings**: All configuration flows through `AppSettings` — no hardcoded values anywhere.
