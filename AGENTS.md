# MLB Analytics Platform - AI Agent Context

Read this file before making ANY changes to this codebase.
All AI agents (Kilo, OpenCode, Aider, Gemini CLI, Copilot) must follow these rules.

## What This Is

PostgreSQL analytics platform for MLB baseball data.
Sources: Statcast, Retrosheet, Chadwick, Lahman, MLB StatsAPI, FanGraphs, BBRef, ESPN, odds feeds.

## Data Layer Architecture

```
raw.*     <- Append-only source-faithful landing. NEVER UPDATE or DELETE.
stg.*     <- Conformance and identity bridge logic.
core.*    <- Canonical normalized baseball truth model.
mart.*    <- Serving layer for queries, APIs, ML features.
ml.*      <- Model registry, feature store, training/scoring/backtest.
ops.*     <- Job queues, live polling, scheduled jobs.
auth.*    <- Multi-tenant security: workspace_id, API keys, RLS.
meta.*    <- Source registry, ingest audit, payload deduplication.
```

## Hard Rules - Never Violate

1. No hardcoded secrets - use environment variables only
2. Never log or print DATABASE_URL
3. workspace_id required on every INSERT into multi-tenant tables
4. Raw schema is append-only - no UPDATE or DELETE on raw.*
5. Specific exceptions only - never bare except: or except Exception without re-raise
6. Ingestion separation - source acquisition must not mix with canonical transformation
7. Parameterized queries only - no f-string SQL, no .format() SQL
8. psycopg3 for all new database code

## Stack

- Python 3.12, PostgreSQL 16, psycopg3, SQLAlchemy 2.x, ruff, pytest
- GitHub Actions + self-hosted runner (cbwdellr720, labels: self-hosted linux homelab)
- All CI jobs have: if: github.repository_owner == 'cbwinslow'

## SQL File Naming Convention

sql/010extensions/ - PostgreSQL extensions
sql/020schemas/    - Schema and role creation
sql/030meta/       - Source registry, ingest audit
sql/040raw/        - Raw source landing tables
sql/050staging/    - Identity bridges, conformance
sql/060core/       - Canonical baseball entities
sql/070mlops/      - ML registry, feature store, ops
sql/080functions/  - Utility and trigger functions
sql/090constraints - Indexes and constraints

## When Making Changes

1. Schema changes: write a new SQL migration file in sql/0XX*/
2. Python: run ruff check . && ruff format . before committing
3. New ingestion sources: raw schema first, never skip to canonical
4. New ML features: register in ml.feature_definition before using
5. Never remove workspace_id from any existing table
