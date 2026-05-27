# MLB Analytics Platform — Project Roadmap

This document defines the high-level product roadmap for the `cbwinslow/mlb` project. The goal is to build a production-grade MLB analytics PostgreSQL platform with Python ingestion pipelines, MCP server integration, and a web application layer.

---

## Vision

Build a comprehensive MLB analytics data platform that:
1. Ingests data from public sources (Retrosheet, Baseball Reference, Statcast, MLBAM API)
2. Stores it in a normalized PostgreSQL schema
3. Exposes data via MCP servers for AI-assisted querying
4. Provides a web application for exploration and visualization

---

## Milestones

### Milestone 1 — Foundation & Scaffolding (COMPLETED)
> **Status:** Completed | **Target:** May 2026

- [x] Repository structure established
- [x] Python package scaffolding (`baseball/` package, CLI, settings)
- [x] `pyproject.toml` with dependency management
- [x] `.env.example` template
- [x] Merge PR #1 (Python app layer)
- [x] PostgreSQL schema DDL (extensions, tables, indexes, constraints)
- [x] Database migration runner wired to `baseball db-init`
- [x] GitHub Issues, Milestones, and Labels configured

---

### Milestone 1.5 — Schema Refactor (COMPLETED)
> **Status:** Completed | **Target:** May 2026

- [x] Decoupled plate appearances from pitch telemetry
- [x] Introduced `core.games` table with UUID primary key
- [x] Added `stg.game_identity_bridge` for canonical game ID mapping
- [x] Updated `core.v_unified_plate_appearances` view with `has_pitch_telemetry` flag
- [x] Fixed UUID consistency across core and ML ops tables
- [x] Verified bootstrap and test suite (410/410 tests pass)

---

### Milestone 2 — Database Setup & Schema
> **Status:** Completed | **Target:** June 2026

- [x] Full PostgreSQL schema for core MLB entities:
  - `teams`, `players`, `seasons`, `games`, `game_logs`
  - `batting_stats`, `pitching_stats`, `fielding_stats`
  - `statcast_pitches`, `statcast_events`
- [x] SQL migration scripts organized under `sql/` folder
- [x] Alembic integration for schema versioning
- [x] Test database setup (`tests/sql/`)
- [ ] Docker Compose for local PostgreSQL
- [ ] Schema documentation (`docs/schema.md`)

---

### Milestone 3 — Data Ingestion Pipeline
> **Status:** Completed | **Target:** July 2026

- [x] Retrosheet event file ingester
- [x] Baseball Reference scraper / CSV ingester
- [x] MLBAM StatsAPI ingester (schedule, boxscores, player data)
- [x] Statcast pitch-by-pitch ingester via `pybaseball`
- [x] `baseball ingest` CLI command with source selection
- [x] Idempotent upsert logic (no duplicate rows on re-run)
- [x] Ingestion progress tracking table
- [ ] Scheduled ingestion (cron / APScheduler)
- [ ] Data validation and quality checks

---

### Milestone 4 — MCP Server Integration
> **Status:** Planned | **Target:** August 2026

- [ ] MCP server exposing read-only SQL query tools
- [ ] MCP tools: `query_players`, `query_games`, `query_stats`, `query_statcast`
- [ ] MCP resource endpoints for schema introspection
- [ ] Authentication / API key management
- [ ] Docker container for MCP server
- [ ] Integration tests for MCP tools
- [ ] Documentation for MCP server usage

---

### Milestone 5 — Web Application
> **Status:** Planned | **Target:** Q4 2026

- [ ] FastAPI backend with async SQLAlchemy
- [ ] REST API for player, game, and stats queries
- [ ] React or Streamlit frontend for data exploration
- [ ] Plotly/Altair charting for batting/pitching dashboards
- [ ] Player comparison tool
- [ ] Game log search and filter
- [ ] Deployment (Docker Compose / Railway / Render)

---

## Technology Stack

| Layer | Technology |
|---|---|
| Language | Python 3.12+ |
| Database | PostgreSQL 16 |
| Vector DB | Qdrant, pgvector |
| ORM | SQLAlchemy 2.0 (async) |
| Migrations | Alembic |
| CLI | Typer + Rich |
| Settings | pydantic-settings |
| MCP | Model Context Protocol SDK |
| Vector Framework | Haystack AI |
| Web API | FastAPI |
| Frontend | Streamlit or React |
| Testing | pytest + pytest-asyncio |
| CI | GitHub Actions |
| Packaging | Hatch |

---

## Priority: Database First

We are following a **data-first** approach:
1. Get the database schema right
2. Build reliable ingestion pipelines
3. Expose via MCP
4. Build the app on top of clean data

This ensures the app layer always has high-quality, queryable data to work with.
