# Documentation Audit Checklist — Schema Refactor (May 2026)

This document tracks the audit of all Markdown files for stale references after the schema refactor.

## Audit Summary

| File | Status | Notes |
|------|--------|-------|
| `README.md` | ✅ Verified | Schema refactor section added |
| `AGENTS.md` | ✅ Updated | File maps corrected, removed files noted |
| `OBJECTIVES.md` | ✅ Updated | DEC-004 updated to reference `core.pitches` |
| `ROADMAP.md` | ✅ Updated | Milestone 1.5 added for schema refactor |
| `sql/README.md` | ✅ Updated | File tree corrected |
| `docs/project-summary.md` | ✅ Updated | Table names corrected |
| `docs/testing-strategy.md` | ✅ Updated | Test table names corrected |
| `docs/player_identity_design.md` | ✅ Updated | Diagram updated |
| `docs/github-workflow.md` | ✅ Updated | Issue title example corrected |
| `docs/architecture.md` | ✅ Verified | No stale references found |
| `docs/data-dictionary.md` | ✅ Verified | No stale references found |
| `docs/ingestion.md` | ✅ Verified | No stale references found |
| `docs/modeling.md` | ✅ Verified | No stale references found |
| `docs/operations.md` | ✅ Verified | No stale references found |
| `docs/external-tools.md` | ✅ Verified | No stale references found |

## Stale References Fixed

| Old Reference | New Reference | File |
|---------------|---------------|------|
| `core.game` | `core.games` | `sql/README.md` |
| `core.pitch` | `core.pitches` | `OBJECTIVES.md`, `docs/player_identity_design.md` |
| `core.plate_appearance` | `core.plate_appearances` | `docs/project-summary.md` |
| `stg.game_bridge` | `stg.game_identity_bridge` | `docs/project-summary.md` |
| `002_game_bridge.sql` | `005_game_identity_bridge.sql` | `sql/README.md` |
| `004_core_pitch_alter.sql` | Integrated into `002_core_gameplay.sql` | `AGENTS.md` |

## Files Deleted (No Longer Referenced)

- `sql/050_staging/002_game_bridge.sql` — replaced by `005_game_identity_bridge.sql`
- `sql/060_core/004_core_pitch_alter.sql` — integrated into `002_core_gameplay.sql`
- `sql/040_raw/003_raw_statcast_migration_v2.sql` — superseded by `003_raw_statcast.sql`

## Verification

- [x] All Markdown files scanned for stale references
- [x] File maps updated in AGENTS.md
- [x] ROADMAP.md updated with completed milestone
- [x] OBJECTIVES.md updated with correct table names
- [x] Bootstrap verified (197/197 tests pass)