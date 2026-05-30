"""Apply 030_meta layer SQL files.

Revision ID: 004_030_meta
Revises: 003_020_schemas
Create Date: 2026-05-26

Per DEC-009: DDL is managed manually in sql/ files.
Alembic tracks execution order only via op.execute() calls.
"""

from alembic import op
import pathlib

# revision identifiers
revision = "004_030_meta"
down_revision = "003_020_schemas"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Apply SQL files in order."""
    sql_root = pathlib.Path(__file__).parent.parent.parent / "sql" / "030_meta"
    sql_files = sorted(sql_root.glob("*.sql"))

    for sql_file in sql_files:
        if "alter" not in sql_file.name.lower():
            op.execute(sql_file.read_text())

    # Apply alter files last if they exist
    alter_files = sorted(sql_root.glob("*_alter.sql"))
    for sql_file in alter_files:
        op.execute(sql_file.read_text())


def downgrade() -> None:
    """No automatic downgrade - SQL files may have destructive operations."""
    pass
