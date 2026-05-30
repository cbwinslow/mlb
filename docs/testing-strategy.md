# MLB Platform: Comprehensive Testing Strategy

> **Last updated:** 2026-05-30
> **Goal:** 100% test coverage with hundreds of tests across Python, SQL, and integration layers

**Current Status:** 433 tests collected (Python), SQL tests in place

---

## Executive Summary

This document outlines the comprehensive testing strategy for the MLB analytics platform. The strategy follows industry best practices with a focus on:

1. **Unit Testing** - Pure function testing with mocked dependencies
2. **Integration Testing** - Database operations with test containers
3. **SQL Testing** - Schema validation, constraint testing, function testing
4. **Property-Based Testing** - Edge case discovery with hypothesis
5. **Contract Testing** - API and data format validation
6. **Data Quality Testing** - Raw source validation and cross-source consistency

---

## Test Coverage Targets

| Layer | Target Coverage | Current Tests | Priority |
|-------|-----------------|---------------|----------|
| Python Unit Tests | 100% | 433+ | High |
| SQL Schema Tests | 100% | 100+ (functional) | High |
| SQL Function Tests | 100% | 100+ (functional) | High |
| Integration Tests | 90%+ | 0 | Medium |
| Property-Based Tests | 80%+ | 0 | Medium |
| Data Quality Tests | 100% | 0 | High |
| **Total** | **100%** | **500+** | - |

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
**Current Status:** Tests exist in `test_enrich_player_identity.py`

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

## Test File Structure (Current)

```
tests/
├── python/
│   ├── __init__.py
│   ├── conftest.py              (shared fixtures)
│   ├── test_cli.py              (CLI tests)
│   ├── test_settings.py         (settings tests)
│   ├── test_package.py          (package tests)
│   ├── test_enrich_player_identity.py  (identity enrichment tests)
│   ├── test_base_ingester.py    (BaseIngester tests)
│   ├── test_retrosheet.py       (RetrosheetIngester tests)
│   ├── test_statcast.py         (StatcastIngester tests)
│   ├── test_mlbam.py            (MLBAMIngester tests)
│   ├── test_fangraphs.py        (FanGraphsIngester tests)
│   ├── test_bref.py             (BRefIngester tests)
│   ├── test_espn.py             (ESPNIngester tests)
│   ├── test_odds.py             (OddsIngester tests)
│   ├── test_orchestrator.py     (orchestration tests)
│   ├── test_engine.py           (engine tests)
│   ├── test_loaders.py          (loader tests)
│   ├── test_lahman.py           (Lahman tests)
│   ├── test_db.py               (db bootstrap tests)
│   ├── test_export.py           (export tests)
│   ├── test_vector_document_store.py (vector store tests)
│   └── test_vector_embeddings.py (embedding tests)
├── sql/
│   ├── bootstrap/
│   │   └── 001_smoke.sql        (schema smoke tests)
│   ├── 013_identity_validation_tests.sql (identity function tests)
│   ├── 014_utility_functions_tests.sql (utility function tests)
│   └── contraints/
│       └── 001_meta_checks.sql  (constraint tests)
├── integration/                 (Created)
│   └── test_database.py
├── property/                    (Created)
│   └── test_properties.py
└── data_quality/                (Created)
    ├── test_identity_consistency.sql
    ├── test_statcast_validation.sql
    ├── test_lahman_validation.sql
    ├── test_retrosheet_validation.sql
    └── test_mv_accuracy.sql
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
- [x] Integration tests (created test_database.py)
- [x] Property-based tests (created test_properties.py)
- [ ] CI/CD setup
- [ ] Coverage reporting

### Phase 5: Ingestion & Vector Tests (Week 5)
- [x] Ingestion module tests (base.py, retrosheet.py, statcast.py, mlbam.py, fangraphs.py, bref.py, espn.py, odds.py)
- [x] Vector database tests (document_store.py, embeddings.py)
- [ ] End-to-end ingestion workflow tests
- [ ] Haystack integration tests

---

### Phase 6: Data Quality & Cross-Source Tests (Week 6)
- [x] Identity reconciliation tests (test_identity_consistency.sql)
- [x] Cross-source data consistency tests (test_identity_consistency.sql)
- [x] Raw data validation tests (test_statcast_validation.sql, test_lahman_validation.sql, test_retrosheet_validation.sql)
- [x] Materialized view accuracy tests (test_mv_accuracy.sql)

---

## Success Criteria

1. **100% Python code coverage** (measured by pytest-cov)
2. **All SQL functions tested** with functional tests (100+ tests in place)
3. **All schemas validated** against bootstrap smoke tests
4. **Identity resolution verified** end-to-end
5. **Cross-source consistency** validated (MLBAM ↔ Retrosheet ↔ Lahman ↔ Chadwick)
6. **CI/CD pipeline** runs all tests on every commit
7. **Coverage report** generated and tracked
8. **Data quality reports** generated for each ingestion run

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

## Current Test Status (2026-05-30)

### Python Tests (433 collected)
**Location:** `tests/python/`

**Completed:**
- [x] `test_settings.py` - Settings module tests (50+ tests)
- [x] `test_cli.py` - CLI command tests (70+ tests)
- [x] `test_package.py` - Package import tests
- [x] `test_enrich_player_identity.py` - Player identity enrichment tests
- [x] `test_base_ingester.py` - BaseIngester ABC tests
- [x] `test_retrosheet.py` - RetrosheetIngester tests
- [x] `test_statcast.py` - StatcastIngester tests
- [x] `test_mlbam.py` - MLBAMIngester tests
- [x] `test_fangraphs.py` - FanGraphsIngester tests
- [x] `test_bref.py` - BRefIngester tests
- [x] `test_espn.py` - ESPNIngester tests
- [x] `test_odds.py` - OddsIngester tests
- [x] `test_orchestrator.py` - Ingestion orchestration tests
- [x] `test_engine.py` - Database engine tests
- [x] `test_loaders.py` - Data loader tests
- [x] `test_lahman.py` - Lahman ingestion tests
- [x] `test_db.py` - Database bootstrap tests
- [x] `test_export.py` - Feature export tests
- [x] `test_vector_document_store.py` - Vector store tests (12 tests)
- [x] `test_vector_embeddings.py` - Embedding tests (18 tests)

### SQL Tests (Functional)
**Location:** `tests/sql/`

**Completed:**
- [x] `bootstrap/001_smoke.sql` - Schema existence smoke tests
- [x] `013_identity_validation_tests.sql` - Identity function tests
- [x] `014_utility_functions_tests.sql` - Utility function tests (100+ tests)
- [x] `contraints/001_meta_checks.sql` - Meta constraint tests

---

## Tests That Give Us Real Results

### Critical Business Logic Tests

These tests answer important questions about data quality and correctness:

#### 1. Identity Resolution Tests
**Question:** "Do we correctly link the same player across all data sources?"
- `stg.fn_validate_identity_completeness()` - Validates cross-source ID coverage
- `stg.fn_cross_validate_identities()` - Detects conflicting ID mappings
- `stg.fn_reconcile_candidates()` - Tests candidate resolution logic
- `stg.fn_full_identity_health_report()` - Overall identity health check

#### 2. Data Integrity Tests
**Question:** "Is our raw data complete and consistent?"
- `util.validate_statcast_pitch_business_key()` - Ensures required pitch fields
- `util.validate_lahman_year_id()` - Validates year range (1871-2100)
- `util.normalize_retrosheet_record_type()` - Ensures record type consistency
- `raw_statcast.pitch` column count - Verifies 118 fields present

#### 3. Ingestion Pipeline Tests
**Question:** "Does our ingestion handle edge cases correctly?"
- `IngestResult` tracking - Verifies row counts and error handling
- `BaseIngester._get_source_endpoint_id()` - Tests endpoint caching
- `IngestEngine.bulk_load_raw_csv()` - Tests COPY operation correctness
- ON CONFLICT handling in `util.ingest_chadwick_play()` - Tests deduplication

#### 4. Materialized View Tests
**Question:** "Do our analytics views return accurate results?"
- `mv_player_statcast_summary` - Tests pitch count aggregations
- `mv_pitch_arsenal_by_season` - Tests pitch type breakdowns
- `mv_game_score_context` - Tests game context calculations
- `mv_batter_spray_heatmap` - Tests spray chart data
- `mv_pitcher_zone_profile` - Tests zone profile accuracy

---

## Recommended Test Additions

### High-Impact Tests Missing

#### 1. Cross-Source Consistency Tests
```sql
-- Test: MLBAM player ID exists in Statcast data
SELECT COUNT(*) FROM raw_statcast.pitch p
WHERE NOT EXISTS (
    SELECT 1 FROM stg.player_identity pi
    WHERE pi.mlbam_player_id = p.batter
);
-- Should return 0 (no orphaned Statcast players)
```

#### 2. Historical Data Gap Tests
```sql
-- Test: Lahman years align with Retrosheet
SELECT DISTINCT year FROM raw_lahman.batting
EXCEPT
SELECT DISTINCT EXTRACT(YEAR FROM game_date) FROM raw_retrosheet.game;
-- Should show gaps we expect (pre-1950s, etc.)
```

#### 3. Team Code Resolution Tests
```sql
-- Test: All Statcast team codes resolve to core.team
SELECT DISTINCT away_team
FROM raw_statcast.pitch p
WHERE p.away_team IS NOT NULL
AND NOT EXISTS (
    SELECT 1 FROM core.team t
    WHERE t.statcast_team_id = p.away_team
);
-- Should return 0 (all teams resolved)
```

#### 4. Venue Resolution Tests
```sql
-- Test: All venues have proper location data
SELECT venue_id, venue_name
FROM core.venue
WHERE venue_location IS NULL
AND venue_name IS NOT NULL;
-- Should return 0 (all venues geocoded)
```

#### 5. Materialized View Freshness Tests
```sql
-- Test: MVs are refreshed within expected window
SELECT mv_name, last_refresh
FROM mart.mv_workspace_model_summary
WHERE last_refresh < NOW() - INTERVAL '7 days';
-- Should return 0 (all MVs fresh)
```

### Vector Database Tests (Completed)
**Location:** `tests/python/`

**Tests Added:**
- [x] `test_vector_document_store.py` - VectorStoreManager operations (12 tests)
- [x] `test_vector_embeddings.py` - Embedding generation and storage (18 tests)

---

### Data Quality Tests (Planned)
**Location:** `tests/sql/data_quality/`

**Tests to Add:**
- [ ] `test_identity_consistency.sql` - Cross-source ID consistency
- [ ] `test_statcast_validation.sql` - Statcast data quality checks
- [ ] `test_lahman_validation.sql` - Lahman data integrity
- [ ] `test_retrosheet_validation.sql` - Retrosheet event file validation
- [ ] `test_mv_accuracy.sql` - Materialized view correctness

---

## Test Execution Matrix

| Test Type | Command | When to Run | Purpose |
|-----------|---------|-------------|---------|
| Unit Tests | `pytest tests/python -v` | Every commit | Fast feedback on code changes |
| SQL Function Tests | `psql -f tests/sql/014_utility_functions_tests.sql` | Every commit | Validate SQL functions exist and work |
| SQL Smoke Tests | `psql -f tests/sql/bootstrap/001_smoke.sql` | Every commit | Validate schema structure |
| Integration Tests | `pytest tests/integration -v` | Daily / PR | Validate end-to-end workflows |
| Property Tests | `pytest tests/property -v` | Daily | Discover edge cases |
| Data Quality Tests | `psql -f tests/sql/data_quality/*.sql` | Weekly | Validate data integrity |

---

## Questions Answered by Tests

### Data Quality Questions
| Question | Test That Answers It |
|----------|---------------------|
| Are all Statcast fields being ingested? | `raw_statcast.pitch` column count test |
| Do we have cross-source player identity coverage? | `stg.fn_validate_identity_completeness()` |
| Are there orphaned pitches without player IDs? | `stg.fn_detect_orphaned_pitches()` |
| Are our materialized views accurate? | `mv_player_statcast_summary` aggregation tests |
| Is Lahman data complete for target years? | Year range validation tests |
| Do all team codes resolve correctly? | Team code resolution tests |
| Are venue locations populated? | Venue geocoding tests |

### Business Logic Questions
| Question | Test That Answers It |
|----------|---------------------|
| Does ingestion handle duplicates correctly? | ON CONFLICT tests in ingest functions |
| Are confidence scores calculated correctly? | `identity_match_score()` tests |
| Do we stop live polling at the right time? | `should_stop_live_polling()` tests |
| Are feature keys unique? | `build_feature_entity_key()` tests |
| Do we track ingestion runs properly? | `start_ingest_run()` / `finish_ingest_run()` tests |

---

## Next Steps

1. **Add integration test infrastructure** - Create `tests/integration/` directory with database fixtures
2. **Create data quality test directory** - Add `tests/sql/data_quality/` with cross-source tests
3. **Add property-based tests** - Create `tests/property/` for edge case discovery
4. **Set up CI/CD** - GitHub Actions workflow to run all test categories
5. **Add coverage reporting** - Track coverage trends over time

---

## AI Agent Testing Guidance

### Test Patterns for Different Data Sources

When creating tests for each data source, follow these patterns:

#### Statcast Tests
```python
# Pattern: Test all 118 fields are captured
def test_statcast_pitch_has_all_fields():
    """Verify raw_statcast.pitch captures all Statcast fields."""
    expected_columns = [
        'game_pk', 'inning', 'at_bat_number', 'pitch_number',
        'batter', 'pitcher', 'events', 'description',
        # ... all 118 columns
    ]
    # Assert all columns exist in table schema
```

#### Lahman Tests
```python
# Pattern: Test year range validation (1871-2100)
def test_lahman_year_range():
    """Verify Lahman data respects valid year range."""
    # Test 1871 (first valid year)
    # Test 2100 (last valid year)
    # Test 1870 (invalid - before range)
    # Test 2101 (invalid - after range)
```

#### Retrosheet Tests
```python
# Pattern: Test record type validation
def test_retrosheet_record_types():
    """Verify all Retrosheet record types are recognized."""
    valid_types = ['id', 'play', 'info', 'starting_lineup', 'sub', 'data']
    for record_type in valid_types:
        assert util.is_valid_retrosheet_record_type(record_type)
```

#### Chadwick Tests
```python
# Pattern: Test cwevent field mapping (96 fields)
def test_chadwick_cwevent_fields():
    """Verify all 96 cwevent fields are mapped correctly."""
    # Test field name normalization
    # Test required field validation
    # Test data type constraints
```

### Cross-Source Validation Patterns

#### Identity Bridge Tests
```sql
-- Pattern: Verify cross-source player identity completeness
SELECT 
    COUNT(*) as missing_mlbam,
    COUNT(*) FILTER (WHERE mlbam_player_id IS NULL) as no_mlbam
FROM raw_statcast.pitch p
LEFT JOIN stg.player_identity pi ON pi.mlbam_player_id = p.batter;
```

#### Game Identity Tests
```sql
-- Pattern: Verify game identity mapping
SELECT 
    COUNT(*) as unmapped_games
FROM raw_statcast.pitch p
WHERE NOT EXISTS (
    SELECT 1 FROM core.games g 
    WHERE g.game_pk = p.game_pk
);
```

### Edge Case Testing Guidance

#### NULL Handling
- Test all nullable columns accept NULL values
- Test NULL propagation through views
- Test NULL in aggregate functions (COUNT, AVG, etc.)

#### Historical Data Gaps
- Test pre-1950 data (no Statcast)
- Test 1950-2014 data (partial Statcast)
- Test 2015+ data (full Statcast)

#### Team Code Changes
- Test historical team name changes (e.g., MIL → ATL in 1966)
- Test team relocations (e.g., MON → WAS in 2005)
- Test defunct teams (e.g., KCM, SLA, etc.)

#### Player Name Variations
- Test accented characters (José, Raúl, etc.)
- Test name changes (Ted Williams, not Theodore)
- Test common name collisions (multiple "John Smith")

### Performance Testing Guidance

#### Query Performance Tests
```sql
-- Pattern: Test query execution time
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM raw_statcast.pitch 
WHERE game_pk = 12345;
-- Assert execution time < 100ms for indexed queries
```

#### Bulk Load Tests
```python
# Pattern: Test bulk load performance
def test_bulk_load_performance():
    """Verify bulk load handles 1M+ rows efficiently."""
    # Time the COPY operation
    # Assert rows/sec > 10000
```

### Test Data Generation Patterns

#### Synthetic Player Data
```python
# Generate realistic player identities
def generate_player_identity(
    mlbam_id: int | None = None,
    retrosheet_id: str | None = None,
    bbref_id: str | None = None,
    confidence: float = 1.0
):
    """Generate test player identity with cross-source IDs."""
```

#### Game Timeline Data
```python
# Generate realistic game timelines
def generate_game_timeline(
    game_pk: int,
    date: date,
    teams: tuple[str, str]
):
    """Generate test game with realistic inning/pitch structure."""
```

### Test Assertion Patterns

#### Data Quality Assertions
```python
# Pattern: Assert data completeness
def assert_data_completeness(table_name: str, min_rows: int):
    """Assert table has minimum expected rows."""
    count = execute(f"SELECT COUNT(*) FROM {table_name}")
    assert count >= min_rows, f"{table_name} has only {count} rows"

# Pattern: Assert cross-source consistency
def assert_cross_source_consistency(source_a: str, source_b: str, join_key: str):
    """Assert no orphaned records between sources."""
    orphaned = execute(f"""
        SELECT COUNT(*) FROM {source_a} a
        WHERE NOT EXISTS (
            SELECT 1 FROM {source_b} b 
            WHERE b.{join_key} = a.{join_key}
        )
    """)
    assert orphaned == 0, f"Found {orphaned} orphaned records"
```

### Test Organization for AI Agents

When adding new tests, follow this structure:

1. **Identify the business question** - What does this test prove?
2. **Choose the test type** - Unit, SQL function, integration, or data quality?
3. **Write the minimal test** - One assertion per test
4. **Add to the appropriate file** - Follow existing patterns
5. **Update this document** - Mark as completed

### Common Test Anti-Patterns to Avoid

- ❌ Testing implementation details instead of behavior
- ❌ Testing the same logic in multiple places
- ❌ Hardcoding expected values that change over time
- ❌ Testing external APIs directly (use mocks)
- ❌ Testing PostgreSQL internals (focus on your logic)

### Test Review Checklist

Before committing tests, verify:
- [ ] Test answers a specific business question
- [ ] Test name clearly describes what it validates
- [ ] Test uses appropriate assertions (not just `assert True`)
- [ ] Test handles edge cases (NULL, empty, error conditions)
- [ ] Test is deterministic (same result every run)
- [ ] Test is fast (< 1 second for unit tests)
- [ ] Test follows existing patterns in the codebase
