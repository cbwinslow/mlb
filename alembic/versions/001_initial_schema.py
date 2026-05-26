"""Initial schema - manual DDL execution tracking

Revision ID: 001_initial_schema
Revises: 
Create Date: 2026-05-26

Per DEC-009: DDL is managed manually in sql/ files.
Alembic tracks execution order only via op.execute() calls.
See: sql/README.md for full migration order
"""
from alembic import op

# revision identifiers, used by Alembic.
revision = "001_initial_schema"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Record that initial schema has been applied.

    The actual DDL is in sql/010 through sql/090 directories.
    This migration is a marker that the bootstrap was completed.
    """
    op.execute(
        "COMMENT ON DATABASE CURRENT_DATABASE() IS "
        "'MLB Analytics Platform - Schema applied via bootstrap'"
    )


def downgrade() -> None:
    """No-op - database should be dropped for full reset."""
    pass
