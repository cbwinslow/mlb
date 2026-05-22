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


# ---------------------------------------------------------------------------
# Ingestion sub-commands
# ---------------------------------------------------------------------------
# Lazy import: enrich_player_identity has optional heavy deps (psycopg2,
# statsapi, pybaseball). Importing at the module level would crash the CLI
# entirely if those packages aren't installed. add_typer() with a callback
# keeps the import deferred until the sub-command is actually invoked.

def _get_enrich_app() -> typer.Typer:
    from baseball.ingestion.enrich_player_identity import app as enrich_app  # noqa: PLC0415
    return enrich_app


# Register the sub-app eagerly so `baseball --help` always lists it,
# but the heavy import only fires when `baseball enrich-identities` is called.
try:
    from baseball.ingestion.enrich_player_identity import app as _enrich_app
    app.add_typer(_enrich_app, name="enrich-identities")
except ImportError:
    # Optional deps missing — register a stub that explains what to install.
    _stub = typer.Typer(name="enrich-identities", help="Player identity enrichment worker (requires psycopg2, python-mlb-statsapi, pybaseball).")

    @_stub.callback(invoke_without_command=True)
    def _enrich_stub(ctx: typer.Context) -> None:  # noqa: ANN001
        console.print(
            "[bold red]enrich-identities requires additional packages.[/bold red]\n"
            "Install them with:\n"
            "  pip install psycopg2-binary python-mlb-statsapi pybaseball"
        )
        raise typer.Exit(code=1)

    app.add_typer(_stub, name="enrich-identities")
