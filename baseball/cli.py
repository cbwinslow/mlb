from __future__ import annotations

from pathlib import Path
from urllib.parse import urlparse, urlunparse

import typer
from rich.console import Console
from rich.table import Table

from baseball.settings import get_settings


app = typer.Typer(help="Baseball platform CLI")
console = Console()


SQL_ROOT = Path(__file__).resolve().parents[1] / "sql"
TEST_SQL_ROOT = Path(__file__).resolve().parents[1] / "tests" / "sql"


def _mask_db_url(url: str) -> str:
    """Return the database URL with the password replaced by ***."""
    parsed = urlparse(str(url))
    if parsed.password:
        masked = parsed._replace(
            netloc=parsed.netloc.replace(f":{parsed.password}@", ":***@")
        )
        return urlunparse(masked)
    return str(url)


@app.command("db-init")
def db_init() -> None:
    """Apply SQL bootstrap files to the configured DATABASE_URL.

    This is a placeholder for the real implementation which will orchestrate
    psql or a migration runner against the sql/ directory using the documented
    folder order (010_extensions through 090_constraints_indexes).
    """

    settings = get_settings()

    table = Table(title="DB Init Plan")
    table.add_column("Step")
    table.add_column("Value")
    table.add_row("Environment", settings.env.value)
    table.add_row("Database URL", _mask_db_url(str(settings.database.url)))
    table.add_row("SQL root", str(SQL_ROOT))

    console.print(table)
    console.print("[yellow]NOTE:[/] db-init is currently a dry run stub. Implementation will be added next.")


@app.command("db-smoke")
def db_smoke() -> None:
    """Run SQL smoke tests against the configured DATABASE_URL.

    This will eventually execute the tests/sql suite; currently it only
    reports planned locations.
    """

    settings = get_settings()

    table = Table(title="DB Smoke Test Plan")
    table.add_column("Step")
    table.add_column("Value")
    table.add_row("Environment", settings.env.value)
    table.add_row("Database URL", _mask_db_url(str(settings.database.url)))
    table.add_row("Tests root", str(TEST_SQL_ROOT))

    console.print(table)
    console.print("[yellow]NOTE:[/] db-smoke is currently a dry run stub. Implementation will be added next.")
