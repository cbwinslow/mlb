# MLB Analytics Platform Ingestion

## Purpose

This document defines the ingestion design for the MLB analytics platform. Unlike the architecture document, which explains the whole system shape, unlike the data dictionary, which explains where tables live, and unlike the security document, which explains control and access boundaries, this file is specifically about how external baseball and betting data enters the platform, how it is tracked, and how ingestion workflows should behave.

The platform depends on many sources that do not behave the same way. Some are historical file drops, some are structured API endpoints, some are live-game feeds, and some are web or odds captures. The ingestion design exists to make those differences explicit instead of hiding them in ad hoc scripts.

## Ingestion goals

The ingestion layer is designed to satisfy these goals:

- Preserve source fidelity on first landing.
- Support both historical backfill and incremental refresh.
- Keep ingest state inspectable in the database.
- Allow retries, backoff, and dead-letter handling.
- Separate source acquisition from canonical transformation.
- Support both batch and near-real-time workflows.
- Make source-specific behavior explicit through loader specifications.
- Allow source disablement without schema redesign.

## Source categories

The platform uses multiple source categories, and each one needs a different ingestion pattern.

### Historical event-file sources

These are bulk historical sources that arrive as files and are typically processed in large backfill windows.

Examples:
- Retrosheet event files,
- Lahman historical tables,
- archived file bundles from other sources.

### CLI-assisted transformation sources

Some workflows depend on external tooling to convert source files into more structured extract outputs.

Example:
- Chadwick extraction via tools such as `cwevent`, `cwgame`, and `cwsub`.

### API pull sources

These are sources where the ingestion worker makes parameterized requests and receives JSON or CSV back.

Examples:
- MLB StatsAPI,
- Statcast search/export workflows,
- some odds or provider APIs.

### Web-capture or scrape-oriented sources

These are sources where request metadata, raw pages, or semi-structured payloads may be the most stable first landing format.

Examples:
- FanGraphs capture workflows,
- Baseball Reference capture workflows,
- ESPN or odds page capture workflows.

## Source-specific ingestion patterns

### Retrosheet

Retrosheet should be handled as a source-faithful batch-file workflow. The primary ingestion concern is downloading, registering, extracting, and loading the event-file content without losing record semantics. The platform should preserve game headers, `info`, `start`, `play`, `sub`, `comment`, and other record families in raw form before attempting canonical normalization.

Retrosheet ingestion is primarily historical and backfill-oriented, though incremental updates may still occur when new seasons or corrections are published.

### Chadwick

Chadwick should be modeled as a dependent extraction stage rather than as a totally separate provider. It consumes event-compatible baseball data and produces structured outputs that are easier to query and load later. The ingestion system should therefore track Chadwick-produced files as part of the broader ingestion workflow, with clear lineage back to the input source.

**Chadwick Register as identity seed:** In addition to the event-file extraction role, the Chadwick Bureau Register (`data/people.csv`) is the primary seed source for `stg.player_identity`. This is a separate concern from the event-file extraction workflow. See the Player Identity Integration section below and `docs/external-tools.md` for the full seeding procedure.

### Lahman

Lahman ingestion is comparatively straightforward. It is a relational historical source and is primarily useful for broad baseball history coverage and identity support. It should still be tracked like any other source, but it does not require the same live or queue-heavy behavior as StatsAPI.

### MLB StatsAPI

MLB StatsAPI should be treated as the primary live-aware API source. It supports schedule-oriented pulls, game detail pulls, and live-feed style workflows. The ingestion system should be able to support multiple runtime patterns for this source:

- scheduled historical pulls,
- periodic incremental refresh,
- live polling for in-progress games,
- endpoint-specific refresh strategies.

Because live games create the highest operational pressure, MLB StatsAPI ingestion needs the strongest operational tracking around retries, leases, stop conditions, and stale worker recovery.

**Identity implication:** MLB StatsAPI is the authoritative modern player identity source. When a player debuts in a live game, their MLBAM `personId` is the first stable ID the system will have. The StatsAPI `people/{id}?hydrate=xrefIds` endpoint is the first enrichment call the identity worker makes for any placeholder with `identity_confidence_score = 0`. See the Player Identity Integration section below.

### Statcast

Statcast ingestion should assume chunked query windows from the start. Rather than depending on oversized one-shot pulls, the system should create bounded date-range or parameter-range chunks so retries are tractable and partial failures are easier to isolate.

Statcast should be considered a high-value but operationally sensitive source because large pulls can be slow, brittle, or cumbersome.

**Identity implication:** Every Statcast pitch row carries `batter` and `pitcher` MLBAM IDs. An `AFTER INSERT` trigger on `raw_statcast.pitch` automatically inserts placeholder rows into `stg.player_identity` for any unseen MLBAM ID. This means Statcast ingest can never produce an orphaned pitch — but it can produce low-confidence identity placeholders that require downstream enrichment. See the Player Identity Integration section below.

### FanGraphs, Baseball Reference, ESPN, and odds sources

These should be treated as raw-first acquisition sources until the business value and long-term source stability are clearer. Request context, fetch timing, page or payload identity, and parsing status should all be tracked so reprocessing can happen later without pretending the initial parse is perfect.

## Ingestion lifecycle

A normal ingestion lifecycle should follow these stages:

1. **Registration**: the source and, if needed, the endpoint are defined in metadata.
2. **Planning**: a worker or scheduler determines what should be pulled.
3. **Run creation**: an ingest run is created to represent the unit of work.
4. **Acquisition**: a file is downloaded or an endpoint is called.
5. **Payload registration**: payload identity, hash, and file metadata are recorded.
6. **Raw landing**: source data is stored in the relevant raw schema.
7. **Error handling**: failures are recorded structurally.
8. **Binding**: the ingest run is linked to its loader spec, file manifest, or endpoint profile.
9. **Downstream handoff**: conformance or canonical loaders can consume the landed data.

This lifecycle is intended to keep ingestion rerunnable and auditable.

## Control tables and what they mean

### `meta.source_system`

Defines the source family and provides the root identity for ingestion governance.

### `meta.source_endpoint`

Defines endpoint-level identities for API-driven sources that need parameterized call control.

### `meta.ingest_run`

Represents one ingestion execution or unit of work.

### `meta.source_file`

Tracks file-level source artifacts.

### `meta.raw_payload_registry`

Stores payload identity and deduplication metadata.

### `meta.ingest_error`

Stores structured ingest failures.

### `ops.ingest_profile`

Defines retry, timeout, and profile defaults for ingestion behavior.

### `ops.source_loader_spec`

Defines how a source should be ingested at a high level.

### `ops.source_endpoint_profile`

Defines endpoint-specific parameter and behavior profiles.

### `ops.source_chunking_policy`

Defines how large pull windows should be divided.

### `ops.file_acquisition_manifest`

Tracks files that should be downloaded, have been downloaded, or have already been loaded.

### `ops.loader_run_binding`

Links an ingest run to its source-specific loader configuration.

### `ops.live_endpoint_strategy`

Defines how live endpoint selection should work for sources that support multiple modes.

## File-based ingestion design

File-based ingestion should assume that files are first-class operational objects. That means the platform should track:
- remote URI,
- local relative path,
- file kind,
- compression type,
- checksum,
- download status,
- extract status,
- load status.

This is especially important for Retrosheet and Chadwick workflows, where file lineage matters.

## API-based ingestion design

API-based ingestion should be controlled through endpoint profiles instead of hardcoded scattered request behavior. An endpoint profile should define:
- endpoint path or route identity,
- parameter schema,
- default parameters,
- timeout expectations,
- polling interval if relevant,
- whether timestamps or diff-patch behavior is supported.

This makes workers more generic and makes source behavior easier to audit and change.

## Chunking strategy

Chunking exists to reduce operational risk. Large windows are harder to retry and harder to inspect when they fail. The chunking policy layer should make it possible to define ingestion windows by:
- date range,
- season,
- game,
- endpoint page,
- any other source-appropriate boundary.

Statcast is the clearest case where chunking should be assumed rather than added later.

## Live ingestion model

Live ingestion is a special case because the worker is not just loading static data; it is participating in a running loop of observation.

The live-ingestion design should support:
- worker claim/lease behavior,
- endpoint mode selection,
- per-game polling state,
- stop conditions,
- no-change counters,
- stale claim recovery,
- retry with backoff when a live pull fails.

This is where the `live_game_poller`, `live_poll_rule`, and `live_endpoint_strategy` tables become especially important.

## Error handling and retries

Ingestion should assume failure is normal. Sources time out, pages change, APIs throttle, and payloads break. The system should therefore support:
- structured error logging,
- bounded retries,
- backoff with jitter,
- dead-letter transitions,
- stale-claim recovery,
- replayable runs.

This is one of the main reasons operational queue state is stored in the database rather than left entirely to worker processes.

## Player identity integration

Ingestion and player identity are closely coupled. Every source that carries player-level data creates either a resolved identity or an identity obligation. This section explains how ingest interacts with the identity layer so neither the raw store nor the staging layer ever has unresolvable orphans.

### The non-blocking ingest contract (DEC-003)

Raw ingest must never fail because the identity layer is not ready. This is achieved by keeping the database trigger extremely cheap: it only writes a zero-confidence placeholder and an audit log row. No external calls, no locks, no blocking. The enrichment work happens outside the ingest path.

### Identity states after ingest

After a Statcast chunk lands in `raw_statcast.pitch`, every `batter` and `pitcher` MLBAM ID is guaranteed to exist in `stg.player_identity` in one of three states:

| State | `identity_confidence_score` | Meaning |
|---|---|---|
| **New placeholder** | 0.00 | Trigger just created this; not yet enriched |
| **Partially enriched** | 0.50–0.89 | Enrichment ran but cross-source IDs are incomplete |
| **Fully resolved** | 0.90–1.00 | Chadwick + secondary source confirmed; safe to promote |

### Chadwick register seed (run before first Statcast ingest)

Before loading any Statcast data for the first time, seed `stg.player_identity` from the Chadwick Register. This ensures the vast majority of historical players already have fully resolved identities before any trigger fires.

```bash
# Download and seed
python scripts/enrich_player_identity.py --mode=seed-chadwick

# Verify — should show near-zero pending_enrichment count for historical players
psql $DATABASE_URL -c "SELECT * FROM stg.v_identity_validation_dashboard;"
```

### How a new player debut propagates

When a player appears in live Statcast data for the first time (a debut or a data source that got ahead of the Chadwick weekly update):

1. `raw_statcast.pitch` INSERT fires trigger `trg_statcast_pitch_player_resolve`.
2. Trigger calls `stg.fn_auto_resolve_statcast_player()` — writes placeholder with `identity_confidence_score = 0`.
3. Trigger writes audit row to `stg.player_identity_resolution_log`.
4. `stg.v_players_pending_enrichment` now includes the new MLBAM ID.
5. Enrichment worker (scheduled or on-demand) calls MLB StatsAPI `people/{id}?hydrate=xrefIds` — first resolver.
6. If StatsAPI returns `xrefIds`, confidence rises to 0.75–0.90.
7. Chadwick weekly refresh confirms or flags the mapping — confidence rises to 0.95–1.00.
8. `stg.fn_reconcile_candidates()` promotes the row to `core.player`.

### Live data vs. historical ID lag

MLB Stats API assigns a `personId` (MLBAM ID) immediately when a player is added to a roster. Historical cross-source IDs (Retrosheet, Lahman, Baseball Reference) are only assigned in post-season data releases. This means a player who debuted in-season will have:

- `key_mlbam` — available immediately from Statcast / StatsAPI
- `key_bbref`, `key_retro`, `key_lahman` — `NULL` until year-end releases or Chadwick weekly update

This is expected behavior, not a bug. The confidence score communicates this state. Do not block fact-table loading on cross-source ID completeness; instead run `fn_cross_validate_identities()` after each Chadwick refresh and Lahman annual release to back-fill the missing IDs.

### Identity validation after each ingest run

After any significant ingest run (bulk backfill, season load, or live debut window), run:

```sql
-- Should always return zero rows
SELECT * FROM stg.fn_detect_orphaned_pitches();

-- Check confidence distribution
SELECT
    CASE
        WHEN identity_confidence_score = 0    THEN 'placeholder'
        WHEN identity_confidence_score < 0.75 THEN 'low confidence'
        WHEN identity_confidence_score < 0.90 THEN 'partial'
        ELSE 'resolved'
    END AS state,
    COUNT(*)
FROM stg.player_identity
GROUP BY 1
ORDER BY 1;
```

For the full validation and maintenance procedure see `docs/external-tools.md` → Weekly Maintenance Checklist and `docs/player_identity_design.md`.

## Relationship to downstream layers

Ingestion is not the same thing as conformance, canonical loading, or modeling. Its job is to acquire and land trustworthy source data with enough metadata that later stages can operate safely.

A successful ingest run does not necessarily mean the source data is fully modeled. It only means the source material has been captured and tracked correctly enough for the next layer to process it.

## Immediate next ingestion tasks

The next ingestion-focused implementation tasks should be:

1. finalize loader specs for each current source,
2. define file manifest behavior for Retrosheet and Chadwick,
3. define endpoint profiles for MLB StatsAPI,
4. define chunking defaults for Statcast,
5. map worker responsibilities to `meta` and `ops` tables,
6. decide which ingestion flows should be queue-driven immediately,
7. run Chadwick Register seed before first Statcast historical backfill.
