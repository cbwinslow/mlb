"""Database bootstrap and administration commands."""
from __future__ import annotations

import functools
from urllib.parse import urlparse

import subprocess
from pathlib import Path

from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn

console = Console()

SQL_ROOT = Path(__file__).resolve().parent.parent / "sql"


def _normalize_url(url: str) -> str:
    """Convert SQLAlchemy URL to PostgreSQL URL for psql.

    Converts postgresql+asyncpg:// to postgresql://
    """
    if "+asyncpg" in url:
        return url.replace("postgresql+asyncpg://", "postgresql://")
    if "+psycopg2" in url:
        return url.replace("postgresql+psycopg2://", "postgresql://")
    return url


def _get_sql_files() -> list[Path]:
    """Get SQL files in proper layer order (010 through 090)."""
    sql_files = []
    for layer in ["010", "020", "030", "040", "050", "060", "070", "080", "090"]:
        for subdir in sorted(SQL_ROOT.glob(f"{layer}_*")):
            if subdir.is_dir():
                sql_files.extend(sorted(subdir.glob("*.sql")))
    return sql_files


@functools.lru_cache(maxsize=1)
def get_sql_files() -> tuple[Path, ...]:
    """Cached getter for SQL file paths in layer order."""
    return tuple(_get_sql_files())


def run_bootstrap(
    database_url: str,
    recreate: bool = False,
) -> None:
    """Run SQL bootstrap files against the target database.

    Args:
        database_url: PostgreSQL connection string.
        recreate: Drop and recreate the database first.
    """
    pg_url = _normalize_url(database_url)

    if recreate:
        console.print("[yellow]Recreating database...[/yellow]")
        _drop_database(pg_url)
        _create_database(pg_url)

    # Get SQL files in proper layer order (010 through 090)
    sql_files = get_sql_files()
    console.print(f"[blue]Found {len(sql_files)} SQL files to apply[/blue]")

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console,
    ) as progress:
        task = progress.add_task("Applying SQL files...", total=len(sql_files))

        for sql_file in sql_files:
            progress.console.print(f"  [cyan]Applying[/cyan] {sql_file.relative_to(SQL_ROOT)}")
            _run_sql_file(pg_url, sql_file)
            progress.advance(task)

    console.print("[green]✓[/green] Bootstrap complete")


def _run_sql_file(database_url: str, sql_file: Path) -> None:
    """Run a single SQL file using psql."""
    result = subprocess.run(
        ["psql", database_url, "-v", "ON_ERROR_STOP=1", "-f", str(sql_file)],
        capture_output=True,
        text=True,
        check=True,
    )
    if result.stderr:
        console.print(f"[dim]{result.stderr}[/dim]")


def _drop_database(database_url: str) -> None:
    """Drop the target database."""
    parsed = urlparse(database_url)
    db_name = parsed.path.lstrip("/")

    subprocess.run(
        ["dropdb", "--if-exists", db_name],
        check=True,
        capture_output=True,
    )


def _create_database(database_url: str) -> None:
    """Create the target database."""
    parsed = urlparse(database_url)
    db_name = parsed.path.lstrip("/")

    subprocess.run(
        ["createdb", db_name],
        check=True,
        capture_output=True,
    )