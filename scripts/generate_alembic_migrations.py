#!/usr/bin/env python
"""Generate Alembic migrations from SQL files in sql/ directory.

Per DEC-009: DDL is managed manually in sql/ files. Alembic tracks 
execution order only via op.execute() calls.
"""
from pathlib import Path
import re

SQL_ROOT = Path(__file__).parent.parent / "sql"
VERSIONS_ROOT = Path(__file__).parent.parent / "alembic" / "versions"

def get_sql_files_by_layer():
    """Get SQL files grouped by layer in execution order."""
    layers = {
        "010": "extensions",
        "020": "schemas", 
        "030": "meta",
        "040": "raw",
        "050": "staging",
        "060": "core",
        "070": "ml_ops",
        "080": "functions",
        "090": "constraints_indexes",
    }
    
    layer_files = {}
    for layer_dir in sorted(SQL_ROOT.iterdir()):
        if layer_dir.is_dir() and layer_dir.name[:3] in layers:
            files = sorted(layer_dir.glob("*.sql"))
            layer_files[layer_dir.name] = [f for f in files if not 'alter' in f.name.lower()]
    
    return layer_files

def generate_migration(layer_name: str, files: list[Path], rev_num: int):
    """Generate a single Alembic migration file."""
    rev_id = f"{rev_num:03d}_{layer_name}"
    
    mig_content = '''"""Apply {layer_name} layer SQL files.

Revision ID: {rev_id}
Revises: {prev_rev}
Create Date: 2026-05-26

Per DEC-009: DDL is managed manually in sql/ files.
Alembic tracks execution order only via op.execute() calls.
"""
from alembic import op
import pathlib

# revision identifiers
revision = "{rev_id}"
down_revision = "{prev_rev}"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Apply SQL files in order."""
    sql_root = pathlib.Path(__file__).parent.parent.parent / "sql" / "{layer_dir}"
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

'''.format(
        layer_name=layer_name,
        layer_dir=layer_name,
        rev_id=rev_id,
        prev_rev="{prev_rev}"  # Will be filled in
    )
    return rev_id, mig_content

def main():
    layer_files = get_sql_files_by_layer()
    prev_rev = "001_initial_schema"
    
    for i, (layer_name, files) in enumerate(sorted(layer_files.items()), start=2):
        rev_num = i
        rev_id, content = generate_migration(layer_name, files, rev_num)
        content = content.format(prev_rev=prev_rev)
        
        mig_path = VERSIONS_ROOT / f"{rev_id}.py"
        mig_path.write_text(content)
        print(f"Created {mig_path}")
        
        prev_rev = rev_id

if __name__ == "__main__":
    main()
