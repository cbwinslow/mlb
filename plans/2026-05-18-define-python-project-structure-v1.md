# Define Python Project Structure for Ingestion Workers and API Service

## Objective

Define the Python package structure for the `baseball` application layer to support ingestion workers, model orchestration, operations, and future API service. This aligns with the immediate next steps from the README: defining the Python project structure for ingestion workers and API service, mapping worker responsibilities to `ops` and `meta` contracts, and defining the FastAPI service boundary.

## Implementation Plan

- [ ] Create subpackage directories under `baseball/`: `db`, `ingestion`, `ml`, `ops`, `api`
  - Rationale: Organize the codebase according to the planned architecture outlined in `docs/python-app-layer.md`, separating concerns for database connectivity, ingestion workflows, machine learning operations, operational job handling, and API services.

- [ ] Define responsibilities and initial contents for each subpackage
  - `baseball/db`: Async SQLAlchemy engine/session management, workspace-aware connection setup for RLS.
  - `baseball/ingestion`: Wrappers around `meta.ingest_run`, `ops.sourceloaderspec`, `ops.jobqueue`, and utility functions for starting/finishing ingest runs.
  - `baseball/ml`: Helpers for registering problems, featuresets, models, launching training/prediction runs, and storing outputs.
  - `baseball/ops`: Job queue and live polling helpers around `ops.jobqueue`, `ops.jobdeadletter`, `ops.livegamepoller`, and materialized view refresh logs.
  - `baseball/api`: Future FastAPI app that exposes safe operations to agents and external services.

- [ ] Create `__init__.py` files in each subpackage to mark them as Python packages
  - Rationale: Ensures Python recognizes the directories as packages and allows for clean imports.

- [ ] Update `baseball/settings.py` if needed to accommodate new subpackage configurations
  - Rationale: As the application grows, settings may need to be extended for specific subpackages (e.g., API-specific settings).

- [ ] Document the responsibilities and interfaces of each subpackage in `docs/python-app-layer.md`
  - Rationale: Keep the documentation in sync with the codebase structure and provide guidance for developers.

## Verification Criteria

- [ ] The `baseball` package contains the subdirectories `db`, `ingestion`, `ml`, `ops`, and `api` each with an `__init__.py` file.
- [ ] The `docs/python-app-layer.md` document is updated to reflect the responsibilities of each subpackage.
- [ ] No circular dependencies are introduced between subpackages (to be verified by manual review or dependency checking tools).
- [ ] The existing `baseball/cli.py` and `baseball/settings.py` remain functional and can import from the new subpackages as needed.

## Potential Risks and Mitigations

1. **Risk**: Over-engineering the subpackage structure before clear requirements are defined.
   Mitigation: Start with minimal viable implementations in each subpackage, focusing on the interfaces defined in the SQL contracts (`meta`, `ops`, etc.) and expand as needed.

2. **Risk**: Inconsistent documentation leading to confusion about subpackage responsibilities.
   Mitigation: Update `docs/python-app-layer.md` concurrently with code changes and treat it as the single source of truth for the application layer architecture.

3. **Risk**: Difficulty in maintaining workspace-aware RLS settings across subpackages.
   Mitigation: Centralize workspace-related logic in `baseball/db` and provide utilities or context managers for other subpackages to use.

## Alternative Approaches

1. **Alternative**: Keep all application layer code in a single `baseball` package without subpackages.
   Trade-offs: Simpler initial structure but risks becoming monolithic and harder to maintain as the project grows. Not aligned with the documented planned structure.

2. **Alternative**: Define subpackages only for `ingestion` and `ops` initially, deferring `db`, `ml`, and `api` until later.
   Trade-offs: Allows faster delivery of ingestion capabilities but may require restructuring later. However, it aligns with the immediate need to define ingestion workers and API service (though API is deferred).

3. **Alternative**: Use a different package name or structure (e.g., `app/` directory as mentioned in `docs/project-summary.md`).
   Trade-offs: Deviates from the current implementation where the Python package is `baseball` at the repository root. Would require renaming and updating imports, causing unnecessary disruption.