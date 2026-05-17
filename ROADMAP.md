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

### Milestone 1 — Foundation & Scaffolding (CURRENT)
> **Status:** In Progress | **Target:** May 2026

- [x] Repository structure established
- [x] Python package scaffolding (`baseball/` package, CLI, settings)
- [x] `pyproject.toml` with dependency management
- [x] `.env.example` template
- [ ] Merge PR #1 (Python app layer)
- [ ] PostgreSQL schema DDL (extensions, tables, indexes, constraints)
- [ ] Database migration runner wired to `baseball db-init`
- [ ] GitHub Issues, Milestones, and Labels configured

---

### Milestone 2 — Database Setup & Schema
> **Status:** Planned | **Target:** June 2026

- [ ] Full PostgreSQL schema for core MLB entities:
  - `teams`, `players`, `seasons`, `games`, `game_logs`
  - `batting_stats`, `pitching_stats`, `fielding_stats`
  - `statcast_pitches`, `statcast_events`
- [ ] SQL migration scripts organized under `sql/` folder
- [ ] Alembic integration for schema versioning
- [ ] Test database setup (`tests/sql/`)
- [ ] Docker Compose for local PostgreSQL
- [ ] Schema documentation (`docs/schema.md`)

---

### Milestone 3 — Data Ingestion Pipeline
> **Status:** Planned | **Target:** July 2026

- [ ] Retrosheet event file ingester
- [ ] Baseball Reference scraper / CSV ingester
- [ ] MLBAM StatsAPI ingester (schedule, boxscores, player data)
- [ ] Statcast pitch-by-pitch ingester via `pybaseball`
- [ ] `baseball ingest` CLI command with source selection
- [ ] Idempotent upsert logic (no duplicate rows on re-run)
- [ ] Ingestion progress tracking table
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
| ORM | SQLAlchemy 2.0 (async) |
| Migrations | Alembic |
| CLI | Typer + Rich |
| Settings | pydantic-settings |
| MCP | Model Context Protocol SDK |
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
