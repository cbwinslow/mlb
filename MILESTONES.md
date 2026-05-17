# GitHub Milestones Reference

This document tracks all GitHub Milestones for the `cbwinslow/mlb` project. Milestones are managed in GitHub Issues → Milestones.

## Milestone 1 — Foundation & Scaffolding
- **Due Date:** May 31, 2026
- **Goal:** Get the Python package, CLI, settings, and basic project infrastructure in place.
- **Key Issues:** #1 (PR: Python app layer)

## Milestone 2 — Database Schema & Migrations
- **Due Date:** June 30, 2026  
- **Goal:** Full PostgreSQL schema DDL, Alembic migrations, Docker Compose for local dev.
- **Key Issues:** Schema tables, migration runner, docker-compose.yml

## Milestone 3 — Data Ingestion Pipeline
- **Due Date:** July 31, 2026
- **Goal:** Working ingesters for Retrosheet, MLBAM API, and Statcast. Idempotent upserts.
- **Key Issues:** Retrosheet ingester, StatsAPI ingester, Statcast ingester, CLI `ingest` command

## Milestone 4 — MCP Server
- **Due Date:** August 31, 2026
- **Goal:** MCP server with read tools for AI-assisted querying of the baseball database.
- **Key Issues:** MCP server scaffold, query tools, auth, Docker container

## Milestone 5 — Web Application
- **Due Date:** December 31, 2026
- **Goal:** FastAPI backend + frontend dashboard for data exploration.
- **Key Issues:** FastAPI app, REST API, frontend, deployment
