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

### Lahman

Lahman ingestion is comparatively straightforward. It is a relational historical source and is primarily useful for broad baseball history coverage and identity support. It should still be tracked like any other source, but it does not require the same live or queue-heavy behavior as StatsAPI.

### MLB StatsAPI

MLB StatsAPI should be treated as the primary live-aware API source. It supports schedule-oriented pulls, game detail pulls, and live-feed style workflows. The ingestion system should be able to support multiple runtime patterns for this source:

- scheduled historical pulls,
- periodic incremental refresh,
- live polling for in-progress games,
- endpoint-specific refresh strategies.

Because live games create the highest operational pressure, MLB StatsAPI ingestion needs the strongest operational tracking around retries, leases, stop conditions, and stale worker recovery.

### Statcast

Statcast ingestion should assume chunked query windows from the start. Rather than depending on oversized one-shot pulls, the system should create bounded date-range or parameter-range chunks so retries are tractable and partial failures are easier to isolate.

Statcast should be considered a high-value but operationally sensitive source because large pulls can be slow, brittle, or cumbersome.

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
6. decide which ingestion flows should be queue-driven immediately.