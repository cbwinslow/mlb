# MLB Database Finalization Plan

## Executive Summary

This plan tracks the remaining implementation tasks needed to finalize the MLB database platform. Much of the core work from the 2026-05-25-finalizing-db.md plan has already been completed.

## Already Completed ✅

### Schema Layer
- `sql/050_staging/004_identity_trigger_and_indexes.sql` - EXISTS with updated_at triggers, partial unique indexes, auto-resolution trigger
- `sql/080_functions/013_identity_validation_functions.sql` - EXISTS (797 lines)
- `sql/080_functions/014_identity_reconciliation_functions.sql` - EXISTS (429 lines)
- `sql/050_staging/005_staging_indexes.sql` - EXISTS with player_identity_candidate indexes

### Python Layer  
- PR #18 implements `scripts/enrich_player_identity.py` and `docs/external-tools.md`
- Identity validation pipeline is functional

## Remaining Critical Fixes

The following issues were identified in automated code review (Issue #31) and need fixing:

### Issue #32: Auth FK Execution Order
- `sql/030_meta/` layer references `auth` schema which doesn't exist until `sql/070_ml_ops`
- Need to move FK definitions to `sql/090_constraints_indexes/`

### Issue #33: pyproject.toml Dev Dependencies  
- pytest, ruff, mypy, pylint are in main dependencies instead of dev group

### Issue #34: .gitignore and Runtime State
- `*.bak.refact/buddy/runtime_queue.jsonl` is a concatenation error (should be two lines)
- `.refact/buddy/state.json` should not be tracked in git

### Issue #35: Non-idempotent util.ingest_play_event()
- Missing ON CONFLICT handling for core.pitches and core.plate_appearances inserts

### Issue #36: UUID Type Mismatches
- INTEGER MLBAM IDs in raw tables vs UUID in core tables
- Need proper identity resolution in ingestion functions

## Task Breakdown

### Phase 1: Bootstrap Fixes
| Issue | Title | Branch | PR |
|-------|-------|--------|-----|
| #32 | Auth FK execution order | feature/32-fix-bootstrap-auth-fk-order | TBD |
| #33 | pyproject.toml dev dependencies | feature/33-fix-dev-dependencies | TBD |
| #34 | .gitignore fixes | feature/34-fix-gitignore | TBD |
| #35 | util.ingest_play_event idempotency | feature/35-fix-ingestion-idempotency | TBD |

### Phase 2: Type Mismatch Fixes
| Issue | Title | Branch | PR |
|-------|-------|--------|-----|
| #36 | UUID type mismatches | feature/36-fix-uuid-type-mismatches | TBD |

## Execution Plan

### Phase 1: Bootstrap Fixes
1. Create branch `feature/32-fix-bootstrap-auth-fk-order`
2. Implement Issue #32: Create `sql/090_constraints_indexes/014_meta_auth_fks.sql`
3. Implement Issue #33: Move dev dependencies to correct group
4. Implement Issue #34: Fix .gitignore and remove runtime state
5. Implement Issue #35: Add ON CONFLICT to `util.ingest_play_event()`
6. Run `scripts/bootstrap_db.sh` against fresh PostgreSQL - verify 0 errors
7. Run tests - verify all pass
8. Commit and open PR targeting main

### Phase 2: Type Mismatch Fixes
1. Create branch `feature/36-fix-uuid-type-mismatches`
2. Fix `util.ingest_statcast_play()` with proper UUID resolution
3. Fix `util.ingest_chadwick_play()` with proper UUID resolution
4. Add missing ON DELETE actions to FK definitions
5. Run bootstrap and tests
6. Commit and open PR targeting main

## Completion Criteria (from Original Plan)

- [ ] `./scripts/bootstrap_db.sh` runs against a fresh PostgreSQL 16 instance with zero errors
- [ ] All 197+ existing pgTAP tests still pass
- [ ] New SQL tests in Task 9 all pass
- [ ] No "relation does not exist", "function does not exist", or "schema does not exist" errors
- [ ] `ruff check baseball/ tests/ scripts/` — zero violations
- [ ] `mypy baseball/ --ignore-missing-imports` — zero errors
- [ ] All open issues (#31, #29) closed with PRs
- [ ] `.refact/buddy/state.json` removed from git tracking
- [ ] `pyproject.toml` has dev deps in correct group