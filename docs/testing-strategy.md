# MLB Platform: Comprehensive Testing Strategy

> **Last updated:** 2026-05-27
> **Goal:** 100% test coverage with hundreds of tests across Python, SQL, and integration layers

**Current Status:** 266 tests passing

---

## Executive Summary

This document outlines the comprehensive testing strategy for the MLB analytics platform. The strategy follows industry best practices with a focus on:

1. **Unit Testing** - Pure function testing with mocked dependencies
2. **Integration Testing** - Database operations with test containers
3. **SQL Testing** - Schema validation, constraint testing, function testing
4. **Property-Based Testing** - Edge case discovery with hypothesis
5. **Contract Testing** - API and data format validation

---

## Test Coverage Targets

| Layer | Target Coverage | Current Tests | Priority |
|-------|-----------------|---------------|----------|
| Python Unit Tests | 100% | 266+ | High |
| SQL Schema Tests | 100% | - | High |
| SQL Function Tests | 100% | - | High |
| Integration Tests | 90%+ | - | Medium |
| Property-Based Tests | 80%+ | - | Medium |
| **Total** | **100%** | **266+** | - |

---

## Test Categories & Implementation Plan

### 1. Python Unit Tests

#### 1.1 Settings Module (`baseball/settings.py`)
**Current Status:** 50+ tests exist, needs expansion

**Tests to Add:**
- [ ] Environment variable precedence testing
- [ ] Nested settings validation with `env_nested_delimiter`
- [ ] Settings serialization/deserialization
- [ ] Cache invalidation edge cases
- [ ] Invalid type coercion scenarios
- [ ] Missing required field combinations

**Estimated Tests:** 30 additional tests

#### 1.2 CLI Module (`baseball/cli.py`)
**Current Status:** 70+ tests exist, needs expansion

**Tests to Add:**
- [ ] Error handling for missing database URL
- [ ] Concurrent command execution
- [ ] Output format validation (JSON, table)
- [ ] Environment-specific behavior differences
- [ ] SQL file discovery and ordering
- [ ] Transaction rollback scenarios

**Estimated Tests:** 25 additional tests

#### 1.3 Player Identity Enrichment (`baseball/ingestion/enrich_player_identity.py`)
**Current Status:** 0 tests exist

**Tests to Add:**

##### Dataclasses (PendingPlayer, ResolvedIds, WorkerStats)
- [ ] PendingPlayer creation with all fields
- [ ] PendingPlayer with NULL optional fields
- [ ] PendingPlayer field validation
- [ ] ResolvedIds confidence score boundaries
- [ ] ResolvedIds source tracking
- [ ] WorkerStats elapsed_seconds calculation
- [ ] WorkerStats property calculations

##### Resolution Functions
- [ ] `_resolve_via_statsapi` - success path
- [ ] `_resolve_via_statsapi` - player not found
- [ ] `_resolve_via_statsapi` - API error handling
- [ ] `_resolve_via_chadwick_cache` - cache hit
- [ ] `_resolve_via_chadwick_cache` - cache miss
- [ ] `_resolve_via_pybaseball` - exact match
- [ ] `_resolve_via_pybaseball` - fuzzy match
- [ ] `_resolve_via_pybaseball` - no match
- [ ] `_resolve_via_chadwick_name` - single candidate
- [ ] `_resolve_via_chadwick_name` - multiple candidates
- [ ] `_resolve_via_chadwick_name` - no candidates

##### Main Pipeline
- [ ] `resolve_player` - full pipeline success
- [ ] `resolve_player` - all strategies fail
- [ ] `resolve_player` - partial resolution
- [ ] `resolve_player` - confidence threshold boundaries

##### Database Helpers
- [ ] `get_pending_players` - empty result
- [ ] `get_pending_players` - with limit
- [ ] `get_pending_players` - ordering verification
- [ ] `insert_candidate` - insert new
- [ ] `insert_candidate` - update existing
- [ ] `run_reconcile` - success
- [ ] `run_orphan_check` - no orphans
- [ ] `run_orphan_check` - with orphans
- [ ] `run_health_report` - JSON structure
- [ ] `seed_chadwick_csv` - file loading

##### Chadwick Cache
- [ ] `_load_chadwick_from_db` - cache population
- [ ] `_load_chadwick_from_csv` - parsing
- [ ] Cache lookup performance

##### Main Worker
- [ ] `run_enrichment` - dry run mode
- [ ] `run_enrichment` - with chadwick seed
- [ ] `run_enrichment` - skip chadwick load
- [ ] `run_enrichment` - rate limiting
- [ ] `run_enrichment` - error handling
- [ ] `run_enrichment` - empty queue

##### CLI
- [ ] `main` - all options
- [ ] `main` - verbose mode
- [ ] `main` - error exit codes
- [ ] `main` - missing database URL

**Estimated Tests:** 100+ tests

#### 1.4 Package Tests (`baseball/__init__.py`)
**Tests to Add:**
- [ ] Module import verification
- [ ] Version attribute
- [ ] Public API surface

**Estimated Tests:** 5 tests

---

### 2. SQL Tests

#### 2.1 Schema Validation Tests
**Location:** `tests/sql/test_schema_validation.py`

**Tests to Add:**
- [ ] All schemas exist (raw_statcast, raw_lahman, etc.)
- [ ] Table existence per schema
- [ ] Column existence and types
- [ ] Primary key constraints
- [ ] Foreign key constraints
- [ ] Unique constraints
- [ ] Check constraints
- [ ] NOT NULL constraints

**Estimated Tests:** 50 tests

#### 2.2 Raw Layer Tests
**Location:** `tests/sql/test_raw_layer.py`

**Tests to Add:**
- [ ] `raw_statcast.pitch` - 110 columns present
- [ ] `raw_statcast.pitch` - nullable columns
- [ ] `raw_retrosheet` tables - event file structure
- [ ] `raw_chadwick` tables - cwevent fields
- [ ] `raw_lahman` tables - all 21 tables
- [ ] `raw_mlbapi` JSONB structure
- [ ] `raw_fangraphs` payload tables
- [ ] `raw_bref` payload tables

**Estimated Tests:** 30 tests

#### 2.3 Staging Layer Tests
**Location:** `tests/sql/test_staging_layer.py`

**Tests to Add:**
- [ ] `stg.player_identity` - identity bridge columns
- [ ] `stg.player_identity` - confidence score range
- [ ] `stg.player_identity_candidate` - candidate structure
- [ ] `stg.game_identity` - game linking
- [ ] `stg.team_identity` - team mapping
- [ ] `stg.venue_identity` - venue mapping
- [ ] Views: `v_players_pending_enrichment`
- [ ] Views: `v_identity_review_queue`
- [ ] Views: `v_identity_conflicts`

**Estimated Tests:** 40 tests

#### 2.4 Core Layer Tests
**Location:** `tests/sql/test_core_layer.py`

**Tests to Add:**
- [ ] `core.player` - player entity
- [ ] `core.team` - team entity
- [ ] `core.venue` - venue entity
- [ ] `core.games` - canonical game entity with UUID PK
- [ ] `core.pitches` - 74+ columns, sparse for historical data
- [ ] `core.plate_appearances` - PA structure with game_id FK
- [ ] `core.roster_assignment` - roster structure
- [ ] `core.v_unified_plate_appearances` - serving view with has_pitch_telemetry
- [ ] Relationships and foreign keys

**Estimated Tests:** 30 tests

#### 2.5 Function Tests
**Location:** `tests/sql/test_functions.py`

**Tests to Add:**
- [ ] `stg.fn_validate_identity_completeness()`
- [ ] `stg.fn_detect_orphaned_pitches()`
- [ ] `stg.fn_cross_validate_identities()`
- [ ] `stg.fn_pinpoint_player_by_context()`
- [ ] `stg.fn_reconcile_candidates()`
- [ ] `stg.fn_full_identity_health_report()`
- [ ] `stg.set_updated_at()` trigger function

**Estimated Tests:** 25 tests

#### 2.6 Index and Constraint Tests
**Location:** `tests/sql/test_indexes_constraints.py`

**Tests to Add:**
- [ ] Unique indexes on identity tables
- [ ] Performance indexes on pitch table
- [ ] Foreign key constraint enforcement
- [ ] Check constraint validation

**Estimated Tests:** 20 tests

---

### 3. Integration Tests

#### 3.1 Database Integration
**Location:** `tests/integration/test_database.py`

**Tests to Add:**
- [ ] Full schema creation from SQL files
- [ ] Transaction rollback testing
- [ ] Concurrent insert scenarios
- [ ] Identity resolution end-to-end
- [ ] Chadwick seed and lookup
- [ ] StatsAPI integration (mocked)
- [ ] pybaseball integration (mocked)

**Estimated Tests:** 30 tests

#### 3.2 CLI Integration
**Location:** `tests/integration/test_cli_integration.py`

**Tests to Add:**
- [ ] `db-init` with real database
- [ ] `db-smoke` with real database
- [ ] Error handling with invalid DB
- [ ] SQL file execution order

**Estimated Tests:** 15 tests

---

### 4. Property-Based Tests

**Location:** `tests/property/test_properties.py`

**Tests to Add:**
- [ ] URL masking properties
- [ ] Confidence score boundaries
- [ ] Player name parsing invariants
- [ ] Database URL validation
- [ ] Settings validation invariants

**Estimated Tests:** 20 tests

---

### 5. Test Infrastructure

#### 5.1 Test Database Setup
- [ ] Docker-based PostgreSQL for integration tests
- [ ] Test fixtures for common data
- [ ] Factory boy-style test data builders
- [ ] Pytest fixtures for database connections

#### 5.2 CI/CD Integration
- [ ] GitHub Actions workflow
- [ ] Test coverage reporting
- [ ] Parallel test execution
- [ ] Test result caching

---

## Test File Structure

```
tests/
├── python/
│   ├── __init__.py
│   ├── test_cli.py              (existing - expand)
│   ├── test_settings.py         (existing - expand)
│   ├── test_package.py          (existing)
│   ├── test_enrich_player_identity.py  (NEW)
│   ├── conftest.py              (NEW - shared fixtures)
│   └── factories.py             (NEW - test data builders)
├── sql/
│   ├── test_schema_validation.py (NEW)
│   ├── test_raw_layer.py         (NEW)
│   ├── test_staging_layer.py     (NEW)
│   ├── test_core_layer.py        (NEW)
│   ├── test_functions.py         (NEW)
│   └── test_indexes_constraints.py (NEW)
├── integration/
│   ├── test_database.py         (NEW)
│   └── test_cli_integration.py  (NEW)
├── property/
│   └── test_properties.py         (NEW)
└── conftest.py                  (NEW - root fixtures)
```

---

## Testing Tools & Libraries

| Tool | Purpose |
|------|---------|
| pytest | Test framework |
| pytest-cov | Coverage reporting |
| pytest-mock | Mocking utilities |
| pytest-postgresql | Test database fixture |
| hypothesis | Property-based testing |
| factory-boy | Test data factories |
| sqlalchemy | Database testing utilities |
| psycopg2 | PostgreSQL adapter |

---

## Implementation Phases

### Phase 1: Foundation (Week 1)
- [ ] Create test infrastructure (conftest.py, fixtures)
- [ ] Expand settings tests to 100%
- [ ] Expand CLI tests to 100%
- [ ] Add conftest.py with shared fixtures

### Phase 2: Enrichment Module (Week 2)
- [ ] Dataclass tests
- [ ] Resolution function tests
- [ ] Database helper tests
- [ ] Main worker tests

### Phase 3: SQL Tests (Week 3)
- [ ] Schema validation tests
- [ ] Raw layer tests
- [ ] Staging layer tests
- [ ] Core layer tests

### Phase 4: Integration & Property Tests (Week 4)
- [ ] Integration tests
- [ ] Property-based tests
- [ ] CI/CD setup
- [ ] Coverage reporting

### Phase 5: Ingestion & Vector Tests (Week 5)
- [x] Ingestion module tests (base.py, retrosheet.py, statcast.py, mlbam.py, fangraphs.py, bref.py, espn.py, odds.py)
- [x] Vector database tests (document_store.py)
- [ ] End-to-end ingestion workflow tests
- [ ] Haystack integration tests

---

## Success Criteria

1. **100% Python code coverage** (measured by pytest-cov)
2. **All SQL files validated** against test database
3. **All functions tested** with edge cases
4. **CI/CD pipeline** runs all tests on every commit
5. **Coverage report** generated and tracked
6. **Test documentation** complete in docs/

---

## Running Tests

```bash
# Run all tests
pytest tests/ -v

# Run with coverage
pytest tests/ -v --cov=baseball --cov-report=html

# Run specific test file
pytest tests/python/test_enrich_player_identity.py -v

# Run SQL tests (requires running PostgreSQL)
pytest tests/sql/ -v --db-url=postgresql://...

# Run property-based tests
pytest tests/property/ -v
```

---

## Questions for Clarification

1. Should we use testcontainers for PostgreSQL integration tests?
2. Do we need to test against specific PostgreSQL versions?
3. Should we mock external APIs (StatsAPI, pybaseball) or use recorded responses?
4. Do we need performance benchmarks as part of the test suite?
5. Should we include data quality tests for the raw data sources?

---

## Completed Ingestion Tests (2026-05-27)

### Ingestion Module Tests
**Location:** `tests/python/test_ingestion/`

**Tests Added:**
- [x] `test_base.py` - BaseIngester ABC tests
- [x] `test_retrosheet.py` - RetrosheetIngester validation and ingestion
- [x] `test_statcast.py` - StatcastIngester season/date range ingestion
- [x] `test_mlbam.py` - MLBAMIngester endpoint methods
- [x] `test_fangraphs.py` - FanGraphsIngester stats/splits ingestion
- [x] `test_bref.py` - BRefIngester data ingestion
- [x] `test_espn.py` - ESPNIngester schedule/scores ingestion
- [x] `test_odds.py` - OddsIngester date/season ingestion
- [x] `test_orchestrator.py` - Ingestion orchestration and parallel execution
- [x] `test_engine.py` - Database engine and connection management

**Total Ingestion Tests:** 69 tests added

### Vector Database Tests (Pending)
**Location:** `tests/python/test_vector/`

**Tests to Add:**
- [ ] `test_document_store.py` - VectorStoreManager operations
- [ ] `test_qdrant_client.py` - Qdrant integration tests
- [ ] `test_pgvector.py` - PgVector integration tests
- [ ] `test_embeddings.py` - Embedding generation and storage