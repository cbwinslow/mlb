# MLB Analytics Platform Data Dictionary

## Purpose

This document is a schema-level and table-family reference for the MLB analytics platform. Unlike the architecture document, this file is not about system layers or deployment strategy. Its purpose is to explain what database objects exist, what role each schema plays, and what kinds of records each table family is expected to store.

This is not yet a full column-by-column data dictionary. It is the controlled intermediate step between a high-level architecture document and a future exhaustive table/column catalog.

## How to use this document

Use this file when the question is one of these:

- What schema should a new table live in?
- Is this table raw, conformed, canonical, operational, or serving?
- Where should a worker or API read from?
- Which schema owns a particular class of data?
- What is the conceptual difference between two table families?

If the question is about deployment shape, service boundaries, or runtime components, the architecture document is the better reference. If the question is about specific columns, constraints, or indexes, a later table-spec document should handle that.

## Schema inventory

| Schema | Primary role | Data type |
|---|---|---|
| `meta` | Ingestion control plane and audit metadata | Operational metadata |
| `ref` | Stable lookup and enumeration tables | Reference data |
| `raw_retrosheet` | Retrosheet event-file storage | Raw source data |
| `raw_chadwick` | Chadwick extraction outputs | Raw/parsed source data |
| `raw_lahman` | Lahman dataset tables | Raw historical relational data |
| `raw_mlbapi` | MLB StatsAPI request/payload/game data | Raw API data |
| `raw_statcast` | Statcast search exports and pitch data | Raw query/export data |
| `raw_fangraphs` | FanGraphs request and payload captures | Raw web/API data |
| `raw_bref` | Baseball Reference captures | Raw web data |
| `raw_espn` | ESPN captures | Raw web/API data |
| `raw_odds` | Sportsbook and odds-source payloads | Raw market data |
| `stg` | Source reconciliation and identity conformance | Conformed bridge data |
| `core` | Canonical baseball entities and facts | Canonical warehouse data |
| `ml` | Modeling, datasets, runs, predictions, simulations | ML metadata and results |
| `ops` | Scheduling, queueing, polling, refresh, loader control | Operational workflow data |
| `auth` | Users, workspaces, service identities, entitlements | Security and ownership data |
| `api` | API contracts, plans, usage, idempotency, webhooks | Service-layer data |
| `mart` | Read-optimized serving views and summaries | Serving data |
| `util` | Shared helper functions and triggers | Utility logic |

## `meta` schema

The `meta` schema stores ingestion control-plane records. These are the tables that describe where data came from, what was attempted, and what happened during ingestion.

### Main table families

| Table or family | Meaning |
|---|---|
| `source_system` | One row per external source family or provider. |
| `source_endpoint` | Endpoint-level definitions for API-oriented sources. |
| `ingest_run` | One tracked ingestion attempt or execution window. |
| `source_file` | File-level metadata for downloaded or imported files. |
| `raw_payload_registry` | Deduplication and identity tracking for payload bodies. |
| `ingest_error` | Structured errors associated with ingest activity. |

### What belongs here

Examples of records that belong in `meta`:
- a row saying an MLB StatsAPI schedule pull started at a given time,
- a file registry entry for a downloaded Retrosheet ZIP,
- an error log row for a failed Statcast chunk,
- a payload hash used to prevent duplicate raw inserts.

### What does not belong here

The actual source rows do not belong here. `meta` is about ingestion metadata, not baseball facts and not raw payload expansion tables.

## `ref` schema

The `ref` schema stores slow-changing lookup data, controlled vocabularies, and reusable standardized values.

### Likely table families

| Table family | Meaning |
|---|---|
| status/reference lookups | Standardized labels used across schemas. |
| enumerations | Controlled values for categories, types, or states. |
| code mappings | Canonical code/value translations. |

This schema should remain small and low-volatility.

## Raw-source schemas

The raw-source schemas are intentionally separated by provider or source family. This is important because each source has different semantics, legal constraints, refresh patterns, and parsing logic.

### `raw_retrosheet`

Stores source-faithful Retrosheet event-file content.

#### Representative table families

| Table or family | Meaning |
|---|---|
| event file registry | One row per imported Retrosheet event file. |
| game header records | One row per game within an event file. |
| `info` records | Game metadata key/value records. |
| `start` records | Starting lineup records. |
| `play` records | Event-level play descriptions. |
| `sub` records | Substitution records. |
| `comment` records | Free-text comment records. |
| `data`/adjustment records | Supplemental event file records. |

This schema should preserve Retrosheet semantics even when the downstream model later normalizes them.

### `raw_chadwick`

Stores structured extract outputs generated through Chadwick tooling.

#### Representative table families

| Table or family | Meaning |
|---|---|
| `cwevent_file` | File-level registry for `cwevent` outputs. |
| `cwevent` | Expanded event rows from Chadwick. |
| `cwgame_file` | File-level registry for `cwgame` outputs. |
| `cwgame` | Structured game-level extract rows. |
| `cwsub_file` | File-level registry for `cwsub` outputs. |
| `cwsub` | Structured substitution rows. |

This schema exists because Chadwick output is structurally different from native Retrosheet records and deserves its own storage contract.

### `raw_lahman`

Stores Lahman tables in a near-source relational form.

#### Representative table families

| Table or family | Meaning |
|---|---|
| `people` | Historical player/person records. |
| `teams` | Team season records. |
| `batting` | Batting stats. |
| `pitching` | Pitching stats. |
| `fielding` | Fielding stats. |

### `raw_mlbapi`

Stores request-level and expanded response-level MLB StatsAPI data.

#### Representative table families

| Table or family | Meaning |
|---|---|
| request log tables | Raw request metadata for API calls. |
| payload tables | Stored raw or semi-raw responses. |
| schedule tables | Date and game schedule structures. |
| live feed tables | In-progress game state and play/pitch structures. |
| lookup tables | Teams, people, venues, and metadata lookups from API calls. |

### `raw_statcast`

Stores Statcast search exports and pitch-level records.

#### Representative table families

| Table or family | Meaning |
|---|---|
| search file registry | One row per Statcast pull or export file. |
| pitch/event rows | Exported Statcast result rows. |
| lookup observations | Lookup/support rows associated with a pull. |

### `raw_fangraphs`, `raw_bref`, `raw_espn`, `raw_odds`

These schemas store request/page/payload captures for secondary baseball and betting sources. They should generally remain raw-first until source stability and long-term business value are clear.

## `stg` schema

The `stg` schema contains conformance and bridge logic. It is where source-specific records are translated into shared canonical identity.

### Table families

| Table family | Meaning |
|---|---|
| player identity bridges | Cross-source player identifier mappings. |
| team identity bridges | Cross-source team identifier mappings. |
| venue identity bridges | Cross-source venue identifier mappings. |
| game identity bridges | Cross-source game mappings. |
| conformance tables | Standardized transformed records used before canonical load. |

### Purpose of staging

This schema absorbs ambiguity. If a player has multiple source IDs or a game key differs across providers, the mismatch should be made explicit here rather than buried in worker code.

## `core` schema

The `core` schema stores the normalized baseball truth model.

### Entity tables

| Table | Meaning |
|---|---|
| `player` | Canonical player entity. |
| `team` | Canonical team entity. |
| `venue` | Canonical venue entity. |
| `game` | Canonical game entity. |

### Gameplay tables

| Table | Meaning |
|---|---|
| `roster_assignment` | Assignment of players to teams/games/roles. |
| `plate_appearance` | Canonical plate appearance grain. |
| `pitch` | Canonical pitch grain. |
| `game_official` | Official-role associations for games. |
| `player_team_season` | Player/team/season relationships and summaries. |

### Source lineage tables

| Table | Meaning |
|---|---|
| `game_source_map` | Links canonical games to source records. |
| `plate_appearance_source_map` | Links canonical PAs to source rows. |
| `pitch_source_map` | Links canonical pitches to source rows. |

## `ml` schema

The `ml` schema stores modeling metadata, run history, outputs, and supporting definitions.

### Definition tables

| Table | Meaning |
|---|---|
| `problem_definition` | Named prediction problem or task. |
| `feature_set` | Logical collection of features. |
| `feature_definition` | Definition metadata for one feature. |
| `dataset_definition` | Reusable dataset recipe. |
| `model_family` | Registry of algorithm families. |
| `model_definition` | One specific model version/record. |

### Run/output tables

| Table | Meaning |
|---|---|
| `feature_snapshot` | Point-in-time feature vector storage. |
| `dataset_split` | Train/validation/test/backtest split definitions. |
| `training_run` | One training execution. |
| `backtest_run` | One backtest execution. |
| `prediction_run` | One scoring execution. |
| `prediction_output` | Row-level scoring results. |
| `prediction_evaluation` | Realized evaluation and metrics. |
| `simulation_run` | Scenario or Monte Carlo execution. |

## `ops` schema

The `ops` schema stores operational workflow state.

### Scheduling tables

| Table | Meaning |
|---|---|
| `scheduled_job` | Recurring or planned job definition. |
| `job_run` | One execution record for a scheduled job. |
| `job_type` | Registry of job categories. |
| `job_dependency` | Dependency edges between scheduled jobs. |

### Queue tables

| Table | Meaning |
|---|---|
| `job_queue` | Durable queue items. |
| `job_dead_letter` | Failed queue items beyond retry policy. |

### Ingestion-control tables

| Table | Meaning |
|---|---|
| `ingest_profile` | Retry/timeout/profile defaults for ingestion work. |
| `source_loader_spec` | Source-specific loader contract. |
| `source_endpoint_profile` | Endpoint-level parameter and behavior profile. |
| `source_chunking_policy` | Chunking/window rules for pull-based sources. |
| `file_acquisition_manifest` | File acquisition and status ledger. |
| `loader_run_binding` | Link between ingest run and loader policy objects. |
| `live_endpoint_strategy` | Rules for live endpoint mode selection. |

### Live and refresh tables

| Table | Meaning |
|---|---|
| `live_game_poller` | Live polling state per game/workflow. |
| `live_poll_rule` | Stop/continue polling rules. |
| `materialized_view_refresh_log` | Refresh audit for serving objects. |

## `auth` schema

The `auth` schema stores security, ownership, identity, and entitlement data.

### Main tables

| Table | Meaning |
|---|---|
| `app_user` | Human user identity. |
| `organization` | Optional grouping for workspaces. |
| `workspace` | Main ownership boundary. |
| `workspace_membership` | User membership and role within workspace. |
| `service_account` | Non-human identity for services/workers. |
| `api_key` | API secret metadata. |
| `data_source_control` | Global enable/disable or hold controls for sources. |
| `workspace_source_entitlement` | Workspace permission over sources/capabilities. |

## `api` schema

The `api` schema stores service-facing and monetization-adjacent tables.

### Client and plan tables

| Table | Meaning |
|---|---|
| `client_application` | Registered client/app consumer. |
| `plan_definition` | Plan and quota definition. |
| `workspace_plan` | Workspace-to-plan assignment. |
| `rate_limit_policy` | Rate limit rule definition. |
| `api_key_policy` | Policy attached to an API key. |

### Request/usage tables

| Table | Meaning |
|---|---|
| `request_idempotency` | Retry-safe request key ledger. |
| `request_log` | API request/response metadata. |
| `usage_rollup_hourly` | Aggregated request usage metrics. |

### Webhook tables

| Table | Meaning |
|---|---|
| `webhook_endpoint` | Subscriber endpoint definition. |
| `webhook_delivery` | Delivery attempts and results. |

## `mart` schema

The `mart` schema stores serving views and materialized views optimized for application and reporting reads.

### Typical object families

| Object family | Meaning |
|---|---|
| workspace model catalog views | Fast browsing of models and ownership context. |
| recent prediction views | Fast access to latest scoring outputs. |
| backtest summary views | Condensed evaluation surfaces. |
| source status views | Operational visibility for ingestion and source availability. |

## `util` schema

The `util` schema stores helper functions, shared trigger functions, refresh helpers, queue helpers, retry calculators, and other reusable database logic.

## Future expansion

This document should later be expanded into:
- a full table inventory,
- column-level specifications,
- PK/FK maps,
- index maps,
- lineage maps between raw, staged, and canonical objects.