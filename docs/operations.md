# MLB Analytics Platform Operations

## Purpose

This document defines the operational design for the MLB analytics platform. Unlike the architecture document, which describes the overall system shape, unlike the data dictionary, which catalogs object families, unlike the security document, which defines access control, unlike the ingestion document, which explains how data enters the platform, and unlike the modeling document, which explains predictive workflows, this file is about how recurring work is scheduled, executed, retried, monitored, and recovered.

The operations layer is what makes the rest of the platform dependable. Without a clear operational design, ingestion becomes fragile, model refreshes become ad hoc, live polling becomes difficult to trust, and background workflows become difficult to inspect or recover.

## Operations goals

The operations design is meant to support these goals:

- Represent scheduled and ad hoc work explicitly.
- Coordinate multiple workers safely.
- Support retries, backoff, and dead-letter handling.
- Track live polling state durably.
- Record refresh history for serving objects.
- Make failure modes inspectable instead of opaque.
- Allow platform and workspace workflows to coexist.
- Provide a stable operational contract for workers, APIs, and agents.

## Operational scope

The operations layer is responsible for more than one kind of job.

### Ingestion operations

Examples:
- historical backfill jobs,
- incremental source pulls,
- live API polling,
- file acquisition workflows,
- replay of failed ingest windows.

### Data refresh operations

Examples:
- materialized view refresh,
- mart rebuild workflows,
- derived feature refresh,
- source-status summary refresh.

### Modeling operations

Examples:
- scheduled scoring runs,
- training execution triggers,
- backtest execution,
- simulation workloads,
- evaluation refresh jobs.

### Service and alerting operations

Examples:
- alert evaluation,
- webhook delivery retry,
- usage rollup refresh,
- API-related maintenance jobs.

## Core operational objects

The `ops` schema should be thought of as an operational ledger. Its objects describe planned work, claimed work, failed work, live state, and maintenance state.

### Scheduled jobs

A scheduled job defines a recurring or planned task. It is the durable representation of intent.

Typical scheduled jobs include:
- nightly Retrosheet backfill checks,
- hourly source-status refresh,
- pregame model scoring,
- periodic alert evaluation,
- rolling feature refresh.

### Job runs

A job run records one execution attempt for a scheduled job. It captures the history of what actually happened, not just what was supposed to happen.

### Job types

A job type classifies work into understandable families such as:
- source ingest,
- live poll,
- mart refresh,
- feature build,
- model train,
- model score,
- backtest run,
- alert evaluation.

### Job dependencies

Some jobs should not run until other jobs complete successfully. Dependency tracking should be explicit so the platform does not rely on timing assumptions or undocumented cron ordering.

## Queue model

The queue system is the heart of the operational design. It should support multiple concurrent workers without losing control of ownership or retry state.

### Queue item responsibilities

A queue item should answer these questions:
- What work needs to be done?
- When is it eligible to run?
- What type of work is it?
- Which worker currently owns it?
- How many attempts have been made?
- When does the claim expire?
- What was the last error?
- Did it succeed, fail for retry, or dead-letter?

### Important queue fields

The queue design relies on fields like:
- `run_at`,
- `job_status`,
- `claimed_at`,
- `claimed_by`,
- `claim_token`,
- `lease_expires_at`,
- `attempts`,
- `max_attempts`,
- `last_error`,
- `completed_at`.

These fields are important because they allow workers to coordinate through the database rather than through fragile shared memory or process-local assumptions.

## Claim and lease behavior

Workers should claim jobs explicitly, and a claimed job should have a lease. If a worker dies, the lease should eventually expire so the job can be recovered.

This means the platform needs operational support for:
- safe claim selection,
- lease duration,
- stale-claim recovery,
- safe completion,
- safe retry transition,
- rejection of invalid completion attempts through claim tokens.

Claim tokens are especially useful because they prevent a stale or duplicated worker from completing the wrong job instance.

## Retry behavior

Retries should be intentional and bounded. The system should support:
- max attempts,
- base retry delay,
- exponential backoff,
- jitter,
- separate handling for terminal failures.

This is important because external systems are noisy. APIs time out, files fail to download, parsers break, and live polling can encounter transient network issues.

## Dead-letter handling

Some jobs should stop retrying. When a job exceeds retry policy or fails in a terminal way, it should move into a dead-letter state and have a durable dead-letter record.

The dead-letter record should make it possible to answer:
- what failed,
- why it failed,
- how many attempts were made,
- when it was moved,
- what follow-up action is needed.

Dead-letter handling is important because permanent failures should become visible operational work items rather than silent background churn.

## Live polling operations

Live game polling is one of the most operationally sensitive workflows in the platform. It is long-running, repetitive, and sensitive to stale workers, no-change loops, or endpoint instability.

### Live polling concerns

A live polling system should track:
- game identity,
- source endpoint mode,
- current claim owner,
- current lease,
- polling interval,
- no-change counter,
- last successful change timestamp,
- termination conditions.

### Poll rules

Polling should stop because a rule says to stop, not because a worker guessed it was done. The system therefore benefits from explicit live poll rules that encode which game states should terminate polling.

## Materialized view operations

Materialized views are part of operations because they require explicit refresh behavior and can fail independently of ingestion or modeling. The system should log refreshes so operators can see:
- which view was refreshed,
- when it ran,
- whether it used concurrent refresh,
- whether it succeeded,
- what error occurred if it failed.

This is especially useful when dashboards or APIs depend on fresh serving-layer objects.

## Workspace-aware operations

Some operations are global platform work and some are workspace-specific. The operations model should support both.

### Global examples

- source availability refresh,
- canonical data maintenance,
- global mart refresh,
- provider-wide backfill work.

### Workspace examples

- scoring a workspace-owned model,
- refreshing a workspace-specific feature set,
- running a private backtest,
- retrying a workspace-specific webhook delivery.

This distinction matters because authorization, observability, and user-facing status all depend on knowing whether a job is global or workspace-scoped.

## Operational observability

Operations should be queryable. The platform should make it easy to inspect:
- pending jobs,
- claimed jobs,
- stale claims,
- dead letters,
- live pollers,
- recent refresh failures,
- high-error sources,
- retry-heavy workflows.

This is one of the reasons the operational model lives in SQL tables rather than existing only inside worker logs.

## Failure recovery philosophy

Operational failure should be recoverable, not mysterious. A healthy operational model should make it possible to:
- recover a stuck queue item,
- replay a failed ingest window,
- rerun a refresh,
- inspect a poison job,
- requeue after manual correction,
- disable a source before it causes cascading failures.

A system that only works when nothing goes wrong is not operationally mature enough for live baseball workflows.

## Relationship to workers and services

The operations tables are not just bookkeeping. They are the shared contract between:
- ingestion workers,
- model workers,
- FastAPI or service endpoints,
- future alerting systems,
- future agent tools.

That means a job created by an API or agent should still be visible to workers in the same durable queue model.

## Immediate next operations tasks

The next operations-focused implementation tasks should be:

1. finalize the `ops` table inventory,
2. define worker claim/recovery rules clearly,
3. decide which jobs are global vs workspace-owned,
4. define live poll stop-state logic,
5. define dead-letter replay policy,
6. define refresh-job conventions for materialized views.