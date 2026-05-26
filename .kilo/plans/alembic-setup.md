# Alembic Setup Plan (Milestone 2)

## Objective
Per DEC-009: DDL is managed manually in `sql/` files. Alembic tracks execution order only via `op.execute()` calls — no auto-generation from SQLAlchemy models.

## Implementation Steps

### 1. Alembic Infrastructure ✅ Done
- [x] `alembic/` directory created
- [x] `alembic.ini` - basic configuration
- [x] `alembic/env.py` - migration environment
- [x] `alembic/script.py.mako` - migration template
- [x] `alembic/versions/001_initial_schema.py` - initial marker migration
- [x] `alembic` added to dev dependencies in `pyproject.toml`
- [x] `baseball migrate` CLI commands added

### 2. Pending Implementation
- [ ] Create migrations for each SQL directory (010-090)
- [ ] Each migration uses `op.execute(open(file).read())` for SQL files
- [ ] Migration order matches sql/README.md documented order
- [ ] Add `db-migrate` command that runs Alembic after SQL bootstrap
- [ ] Document in docs/ the Alembic usage pattern

### 3. SQL Directory to Migration Mapping
Per sql/README.md, migrations should track:
1. `010_extensions/` - PostgreSQL extensions
2. `020_schemas/` - Schema creation
3. `030_meta/` - Metadata tables
4. `040_raw/` - Raw ingestion tables
5. `050_staging/` - Staging tables and triggers
6. `060_core/` - Core entities and relationships
7. `070_ml_ops/` - ML ops tables and MVs
8. `080_functions/` - PL/pgSQL functions
9. `090_constraints_indexes/` - Final indexes and constraints

## Next Action
Create migration files for sql/010 through sql/090 directories.
