"""Apply 010_extensions layer SQL files.

Revision ID: 002_010_extensions
Revises: 001_initial_schema
Create Date: 2026-05-26

Per DEC-009: DDL is managed manually in sql/ files.
Alembic tracks execution order only via op.execute() calls.
"""

from alembic import op
import pathlib

# revision identifiers
revision = "002_010_extensions"
down_revision = "001_initial_schema"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Apply SQL files in order."""
    sql_root = pathlib.Path(__file__).parent.parent.parent / "sql" / "010_extensions"
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
