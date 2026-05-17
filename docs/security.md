# MLB Analytics Platform Security

## Purpose

This document defines the security model for the MLB analytics platform. Unlike the architecture document, which explains system layers, and unlike the data dictionary, which explains where data lives, this file explains how access is controlled, how ownership is represented, how shared-database isolation should work, and how operational and API identities should be managed.

The current platform is being designed for a homelab-first environment that can later grow into a shared internal or hosted multi-user system. Because of that, the security model needs to work in a simple single-user deployment without blocking a future transition to workspaces, row-level isolation, API plans, service accounts, and auditable automation.

## Security goals

The security design is based on these goals:

- Support a simple single-user deployment without redesign later.
- Support shared-database multi-user deployment safely.
- Keep canonical baseball data globally reusable.
- Restrict user-created workflow objects by workspace ownership.
- Separate human access from service and worker access.
- Make source-level legal and quality controls enforceable.
- Keep the future API boundary enforceable through database-backed contracts.
- Preserve auditability for sensitive operational and service actions.

## Security layers

The platform security model has several layers that work together.

### 1. Database roles

PostgreSQL roles are the broad capability boundary. These should define what a class of actors can generally do in the system.

Expected role families include:
- `mlb_platform_admin`
- `mlb_app_user`
- `mlb_readonly`
- `mlb_worker`
- `mlb_api`

These are group roles, not necessarily direct login identities. The normal pattern is to grant these to real login roles or service principals depending on the deployment model.

### 2. Workspace ownership

Many records in `ml`, `ops`, `api`, and parts of `auth` should be workspace-owned. This means that one workspace can have its own models, runs, predictions, jobs, API clients, plans, or service artifacts without exposing them to another workspace.

The platform is intentionally not designed as one database per user. Instead, it uses shared global data plus scoped workflow ownership. That is the correct fit for a baseball analytics platform where the source facts are mostly universal but the models, jobs, and outputs may be private.

### 3. Row Level Security

Row Level Security is the table-level isolation mechanism for shared tables. Where enabled, policies should rely on request/session context such as:
- current workspace,
- current user,
- current admin flag,
- possibly current service identity.

This allows the application layer to set request context while PostgreSQL enforces row visibility and row mutation rules.

### 4. Source controls

Not every source should always be available for ingest or serving. Some sources may need to be disabled because of:
- legal restrictions,
- licensing changes,
- quality concerns,
- incomplete backfills,
- operational incidents.

The design therefore includes source control tables so source usage can be turned on, turned off, or restricted without schema surgery.

### 5. API and service identity

The future application and automation stack should not rely on shared human credentials. Workers, services, and external apps need their own identities through service accounts and API keys. That makes actions traceable and reduces the temptation to over-privilege human users.

## Security domains

### Global canonical domain

Canonical baseball entities and facts in `core` are generally global. These objects are not expected to be private per workspace. The system should therefore protect them primarily through grants, service boundaries, and source governance rather than per-row workspace filtering.

### Workspace-private domain

Objects that represent user or team work should normally be private to a workspace unless explicitly shared. This includes things like:
- feature sets,
- dataset definitions,
- models,
- training runs,
- backtests,
- prediction runs,
- queue jobs created on behalf of a workspace,
- API clients and usage artifacts.

### Administrative control domain

Some objects are platform-wide control objects and should be writable only by administrators or tightly scoped automation. This includes:
- source registry data,
- source control flags,
- plan definitions,
- rate-limit policy definitions,
- role and grant administration,
- some operational override tables.

## Schema-by-schema security posture

### `meta`

The `meta` schema contains sensitive operational metadata and ingest audit history. It should generally be writable by workers and trusted services, readable by admins and debugging tools, and only selectively exposed to end-user applications.

### Raw schemas

Raw schemas may contain messy, duplicated, legally sensitive, or source-licensed data. They should be treated as more restricted than curated marts. Direct user-facing access should generally be avoided.

### `stg`

The staging schema is an internal transformation area. It is mainly for loaders, reconciliation routines, and developers doing controlled inspection.

### `core`

The canonical warehouse is broadly useful but should still usually be consumed through a service boundary or read-only role. Write access should be tightly limited.

### `ml`

The `ml` schema is highly workspace-sensitive because it contains models, datasets, runs, and results. This is one of the main places where row ownership and Row Level Security should be expected.

### `ops`

The `ops` schema contains operational control data and should be tightly write-scoped. Some rows may also be workspace-sensitive, especially queue items or jobs created on behalf of a user workspace.

### `auth`

The `auth` schema is among the most sensitive parts of the platform because it contains users, service identities, memberships, API key records, and entitlements. It should be highly restricted and carefully audited.

### `api`

The `api` schema contains request logs, rate-limit policies, idempotency records, and webhook metadata. It should be writable by the service layer and visible in a limited way to administrative or analytics tooling.

### `mart`

The `mart` schema is the most likely place for controlled end-user read access, because it is designed as a serving layer rather than a raw or control plane layer.

## Workspace security model

The intended security model is:

- universal baseball data is shared,
- user/team workflow data is workspace-owned,
- platform control data is admin-scoped.

This model avoids the cost and complexity of per-user databases while still giving you a path to hosted multi-user isolation.

### Benefits

- single-user installs still work cleanly,
- multi-user growth does not require replatforming,
- canonical data stays reusable,
- private models and experiments remain isolatable,
- operational and service boundaries stay consistent.

## Row Level Security guidance

RLS should be used selectively and intentionally.

### Good candidates for RLS

- `ml.model_definition`
- `ml.training_run`
- `ml.backtest_run`
- `ml.prediction_run`
- `ml.simulation_run`
- `ops.job_queue` when tied to a workspace
- `api.client_application`
- `api.workspace_plan`
- `api.request_log` when exposed through user tools
- `auth.workspace_membership`

### Poor candidates for RLS

- small global reference tables,
- universal canonical baseball entities,
- internal-only tables that no end-user path will touch.

RLS is powerful, but it should not be sprayed everywhere just because it exists. It adds policy complexity, so it should be reserved for shared tables where ownership actually matters.

## Source governance

Source governance is part of security, not just operations. A source may need to be disabled for ingest, disabled for serving, or placed under legal hold. The database design includes source control tables specifically so the platform can respond to those cases without deleting data or rewriting downstream tables.

This is also important for commercialization. Some workspaces may eventually have access to some source-backed capabilities but not others.

## Human users vs service accounts

The platform should distinguish clearly between:
- human users,
- service accounts,
- API clients.

A worker that ingests live MLB data should not run under a human user. An API integration should not borrow a developer login. A web app backend should not use a superuser. This separation is necessary for least privilege and clean audit trails.

## API security model

The future API should enforce:
- authentication,
- authorization,
- request logging,
- rate limiting,
- idempotency,
- plan enforcement,
- webhook signature verification.

These controls already have corresponding contract tables in the `api` schema, which is one reason the database design includes service concepts before the FastAPI code is written.

## Secret handling

Secrets should never be stored in the repo in plain text. The system should assume:
- environment or secret-manager injection for database credentials,
- hashed storage for API keys or signing secrets where appropriate,
- rotation support for service keys and webhook secrets,
- distinct credentials for dev, test, and production-like environments.

## Audit and observability

Security without observability is weak. The platform should support:
- request logging at the API layer,
- job and worker identity logging in operational tables,
- ingest error tracking,
- database auditing through pgAudit or equivalent statement/object audit support,
- optional higher-granularity history for especially sensitive control tables.

## Recommended security posture by phase

### Homelab phase

- keep direct DB access limited to trusted operators,
- use non-superuser app accounts where possible,
- separate worker credentials from manual admin credentials,
- start using workspace ownership fields even if only one workspace exists.

### Shared internal phase

- add Row Level Security on workspace-sensitive tables,
- formalize service accounts,
- restrict raw schema access,
- enforce app/API access through a service layer.

### Hosted phase

- require full service-mediated access,
- enforce plan, quota, and idempotency behavior,
- treat `auth` and `api` as highly sensitive control domains,
- expand auditing and operational alerting.

## Immediate next security tasks

The next security-focused implementation tasks should be:

1. finalize the role/grant matrix,
2. define which tables will carry `workspace_id`,
3. identify the first set of RLS-protected tables,
4. define session-context conventions for the app layer,
5. document source control state meanings,
6. decide how API keys and signing secrets are stored and rotated.