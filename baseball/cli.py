from __future__ import annotations

from pathlib import Path
from urllib.parse import urlparse, urlunparse
from typing import Optional

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
def db_init(
    recreate: bool = False,
    dry_run: bool = False,
) -> None:
    """Apply SQL bootstrap files to the configured DATABASE_URL.

    Applies SQL files in order from sql/010_extensions through
    sql/090_constraints_indexes.
    """
    from baseball.db import run_bootstrap

    settings = get_settings()

    if dry_run:
        table = Table(title="DB Init Plan (dry run)")
        table.add_column("Step")
        table.add_column("Value")
        table.add_row("Environment", settings.env.value)
        table.add_row("Database URL", _mask_db_url(str(settings.database.url)))
        table.add_row("SQL root", str(SQL_ROOT))
        console.print(table)
        console.print("[yellow]Dry run - no changes made[/yellow]")
        return

    run_bootstrap(
        database_url=str(settings.database.url),
        recreate=recreate,
    )


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
    console.print(
        "[yellow]NOTE:[/] db-smoke is a dry run stub. Implementation pending."
    )


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
    _stub = typer.Typer(
        name="enrich-identities",
        help="Player identity enrichment worker.",
    )

    @_stub.callback(invoke_without_command=True)
    def _enrich_stub(ctx: typer.Context) -> None:  # noqa: ANN001
        console.print(
            "[bold red]enrich-identities requires additional packages.[/bold red]\n"
            "Install them with:\n"
            "  pip install psycopg2-binary python-mlb-statsapi pybaseball"
        )
        raise typer.Exit(code=1)

    app.add_typer(_stub, name="enrich-identities")


# ---------------------------------------------------------------------------
# Ingestion commands
# ---------------------------------------------------------------------------

ingest_app = typer.Typer(help="Data ingestion commands for MLB sources")


@ingest_app.command("lahman")
def ingest_lahman(
    database_url: str = typer.Option(
        ..., envvar="DATABASE_URL", help="PostgreSQL connection string."
    ),
) -> None:
    """Ingest Lahman database tables.

    Generates historical player registry from Lahman CSV files.
    """
    import asyncio
    from psycopg_pool import AsyncConnectionPool
    from baseball.ingestion.lahman import LahmanIngester

    # Convert SQLAlchemy URL to psycopg format
    pg_url = database_url.replace("postgresql+asyncpg://", "postgresql://")

    async def _run():
        async with AsyncConnectionPool(pg_url) as pool:
            ingester = LahmanIngester(pool, workspace_id=None)
            result = await ingester.ingest(season=2023)
            console.print(f"[green]Lahman ingest complete: {result.rows_inserted} rows[/green]")

    asyncio.run(_run())


@ingest_app.command("retrosheet")
def ingest_retrosheet(
    database_url: str = typer.Option(
        ..., envvar="DATABASE_URL", help="PostgreSQL connection string."
    ),
    season: Optional[int] = typer.Option(
        None, "--season", "-s", help="Season to ingest (omit for all)."
    ),
) -> None:
    """Ingest Retrosheet event files.

    Establishes plate appearance blocks from event files.
    """
    import asyncio
    from psycopg_pool import AsyncConnectionPool
    from baseball.ingestion.retrosheet import RetrosheetIngester

    # Convert SQLAlchemy URL to psycopg format
    pg_url = database_url.replace("postgresql+asyncpg://", "postgresql://")

    async def _run():
        async with AsyncConnectionPool(pg_url) as pool:
            ingester = RetrosheetIngester(pool, workspace_id=None)
            result = await ingester.ingest(season=season)
            console.print(f"[green]Retrosheet ingest complete: {result.rows_inserted} rows[/green]")

    asyncio.run(_run())


@ingest_app.command("mlbapi")
def ingest_mlbapi(
    database_url: str = typer.Option(
        ..., envvar="DATABASE_URL", help="PostgreSQL connection string."
    ),
    season: Optional[int] = typer.Option(
        None, "--season", "-s", help="Season to ingest."
    ),
) -> None:
    """Sync MLB Stats API data.

    Syncs modern identity cross-links from MLB Stats API.
    """
    import asyncio
    from psycopg_pool import AsyncConnectionPool
    from baseball.ingestion.lahman import LahmanIngester

    # Convert SQLAlchemy URL to psycopg format
    pg_url = database_url.replace("postgresql+asyncpg://", "postgresql://")

    async def _run():
        async with AsyncConnectionPool(pg_url) as pool:
            ingester = LahmanIngester(pool, workspace_id=None)
            result = await ingester.ingest(season=season)
            console.print(f"[green]MLB API ingest complete: {result.rows_inserted} rows[/green]")

    asyncio.run(_run())


@ingest_app.command("statcast")
def ingest_statcast(
    database_url: str = typer.Option(
        ..., envvar="DATABASE_URL", help="PostgreSQL connection string."
    ),
    start_date: Optional[str] = typer.Option(
        None, "--start", "-S", help="Start date (YYYY-MM-DD)."
    ),
    end_date: Optional[str] = typer.Option(
        None, "--end", "-E", help="End date (YYYY-MM-DD)."
    ),
) -> None:
    """Load Statcast pitch telemetry.

    Loads high-fidelity pitch telemetry from Baseball Savant.
    """
    import asyncio
    from datetime import date
    from psycopg_pool import AsyncConnectionPool
    from baseball.ingestion.statcast import StatcastIngester

    # Convert SQLAlchemy URL to psycopg format
    pg_url = database_url.replace("postgresql+asyncpg://", "postgresql://")

    async def _run():
        async with AsyncConnectionPool(pg_url) as pool:
            ingester = StatcastIngester(pool, workspace_id=None)
            if start_date and end_date:
                result = await ingester.ingest(
                    start_date=date.fromisoformat(start_date),
                    end_date=date.fromisoformat(end_date),
                )
            else:
                result = await ingester.ingest(season=2023)
            console.print(f"[green]Statcast ingest complete: {result.rows_inserted} rows[/green]")

    asyncio.run(_run())


@ingest_app.command("fangraphs")
def ingest_fangraphs(
    database_url: str = typer.Option(
        ..., envvar="DATABASE_URL", help="PostgreSQL connection string."
    ),
    season: Optional[int] = typer.Option(
        None, "--season", "-s", help="Season to ingest."
    ),
    data_type: Optional[str] = typer.Option(
        None, "--type", "-t", help="Data type (batting, pitching, fielding, etc.)."
    ),
) -> None:
    """Ingest FanGraphs data.

    Loads stats and splits from FanGraphs.
    """
    import asyncio
    from psycopg_pool import AsyncConnectionPool
    from baseball.ingestion.fangraphs import FanGraphsIngester

    # Convert SQLAlchemy URL to psycopg format
    pg_url = database_url.replace("postgresql+asyncpg://", "postgresql://")

    async def _run():
        async with AsyncConnectionPool(pg_url) as pool:
            ingester = FanGraphsIngester(pool, workspace_id=None)
            result = await ingester.ingest(season=season, data_type=data_type)
            console.print(f"[green]FanGraphs ingest complete: {result.rows_inserted} rows[/green]")

    asyncio.run(_run())


@ingest_app.command("bref")
def ingest_bref(
    database_url: str = typer.Option(
        ..., envvar="DATABASE_URL", help="PostgreSQL connection string."
    ),
    season: Optional[int] = typer.Option(
        None, "--season", "-s", help="Season to ingest."
    ),
    data_type: Optional[str] = typer.Option(
        None, "--type", "-t", help="Data type (batting, pitching, fielding, etc.)."
    ),
) -> None:
    """Ingest Baseball Reference data.

    Loads stats from Baseball Reference.
    """
    import asyncio
    from psycopg_pool import AsyncConnectionPool
    from baseball.ingestion.bref import BRefIngester

    # Convert SQLAlchemy URL to psycopg format
    pg_url = database_url.replace("postgresql+asyncpg://", "postgresql://")

    async def _run():
        async with AsyncConnectionPool(pg_url) as pool:
            ingester = BRefIngester(pool, workspace_id=None)
            result = await ingester.ingest(season=season, data_type=data_type)
            console.print(f"[green]BRef ingest complete: {result.rows_inserted} rows[/green]")

    asyncio.run(_run())


@ingest_app.command("espn")
def ingest_espn(
    database_url: str = typer.Option(
        ..., envvar="DATABASE_URL", help="PostgreSQL connection string."
    ),
    season: Optional[int] = typer.Option(
        None, "--season", "-s", help="Season to ingest."
    ),
    data_type: Optional[str] = typer.Option(
        None, "--type", "-t", help="Data type (schedule, scores, standings)."
    ),
) -> None:
    """Ingest ESPN data.

    Loads schedule and scores from ESPN.
    """
    import asyncio
    from psycopg_pool import AsyncConnectionPool
    from baseball.ingestion.espn import ESPNIngester

    # Convert SQLAlchemy URL to psycopg format
    pg_url = database_url.replace("postgresql+asyncpg://", "postgresql://")

    async def _run():
        async with AsyncConnectionPool(pg_url) as pool:
            ingester = ESPNIngester(pool, workspace_id=None)
            result = await ingester.ingest(season=season, data_type=data_type)
            console.print(f"[green]ESPN ingest complete: {result.rows_inserted} rows[/green]")

    asyncio.run(_run())


@ingest_app.command("odds")
def ingest_odds(
    database_url: str = typer.Option(
        ..., envvar="DATABASE_URL", help="PostgreSQL connection string."
    ),
    date_val: Optional[str] = typer.Option(
        None, "--date", "-d", help="Date (YYYY-MM-DD)."
    ),
    sport: Optional[str] = typer.Option(
        "baseball", "--sport", help="Sport key for odds API."
    ),
) -> None:
    """Ingest betting odds data.

    Loads market lines from odds providers.
    """
    import asyncio
    from datetime import date
    from psycopg_pool import AsyncConnectionPool
    from baseball.ingestion.odds import OddsIngester

    # Convert SQLAlchemy URL to psycopg format
    pg_url = database_url.replace("postgresql+asyncpg://", "postgresql://")

    async def _run():
        async with AsyncConnectionPool(pg_url) as pool:
            ingester = OddsIngester(pool, workspace_id=None)
            result = await ingester.ingest(
                date_val=date.fromisoformat(date_val) if date_val else None,
                sport=sport,
            )
            console.print(f"[green]Odds ingest complete: {result.rows_inserted} rows[/green]")

    asyncio.run(_run())


app.add_typer(ingest_app, name="ingest")


# ---------------------------------------------------------------------------
# Migration commands (Alembic wrapper)
# ---------------------------------------------------------------------------

migrate_app = typer.Typer(help="Alembic database migrations")


@migrate_app.command("upgrade")
def migrate_upgrade(
    revision: str = typer.Argument("head", help="Target revision"),
) -> None:
    """Run Alembic migrations to the target revision."""
    from alembic.config import Config
    from alembic import command

    alembic_cfg = Config("alembic.ini")
    command.upgrade(alembic_cfg, revision)
    console.print(f"[green]Migrations upgraded to {revision}[/green]")


@migrate_app.command("downgrade")
def migrate_downgrade(
    revision: str = typer.Argument("-1", help="Target revision"),
) -> None:
    """Downgrade Alembic migrations by one revision."""
    from alembic.config import Config
    from alembic import command

    alembic_cfg = Config("alembic.ini")
    command.downgrade(alembic_cfg, revision)
    console.print(f"[green]Migrations downgraded to {revision}[/green]")


@migrate_app.command("current")
def migrate_current() -> None:
    """Show current migration revision."""
    from alembic.config import Config
    from alembic import command

    alembic_cfg = Config("alembic.ini")
    command.current(alembic_cfg)


@migrate_app.command("history")
def migrate_history() -> None:
    """Show migration history."""
    from alembic.config import Config
    from alembic import command

    alembic_cfg = Config("alembic.ini")
    command.history(alembic_cfg)


app.add_typer(migrate_app, name="migrate")


# ---------------------------------------------------------------------------
# Vector embedding commands
# ---------------------------------------------------------------------------

vector_app = typer.Typer(help="Vector embedding commands for similarity search")


@vector_app.command("init")
def vector_init(
    backend: str = typer.Option(
        "pgvector",
        "--backend",
        "-b",
        help="Vector backend to initialize (pgvector or qdrant).",
    ),
) -> None:
    """Initialize vector store backend.

    For pgvector: ensures pgvector extension and tables exist.
    For qdrant: validates connection to Qdrant server.
    """
    from baseball.settings import get_settings
    from baseball.vector.document_store import VectorStoreManager

    settings = get_settings()

    if backend == "pgvector":
        try:
            manager = VectorStoreManager(pgvector_connection_str=str(settings.database.url))
            # Accessing pgvector_store triggers initialization
            _ = manager.pgvector_store
            console.print("[green]PgVector initialized successfully.[/green]")
        except Exception as exc:
            console.print(f"[red]Failed to initialize PgVector: {exc}[/red]")
            raise typer.Exit(code=1)
    elif backend == "qdrant":
        try:
            manager = VectorStoreManager()
            _ = manager.qdrant_store
            console.print("[green]Qdrant connection validated successfully.[/green]")
        except Exception as exc:
            console.print(f"[red]Failed to connect to Qdrant: {exc}[/red]")
            raise typer.Exit(code=1)
    else:
        console.print(f"[red]Unknown backend: {backend}[/red]")
        raise typer.Exit(code=1)


@vector_app.command("embed-players")
def embed_players_cmd(
    database_url: str = typer.Option(
        ...,
        envvar="DATABASE_URL",
        help="PostgreSQL connection string.",
    ),
    model: Optional[str] = typer.Option(
        None,
        "--model",
        "-m",
        help="Embedding model to use (overrides EMBEDDING_MODEL env).",
    ),
    batch_size: int = typer.Option(
        100,
        "--batch-size",
        "-n",
        help="Batch size for embedding API calls.",
    ),
    dry_run: bool = typer.Option(
        False,
        "--dry-run",
        help="Show players to embed without writing.",
    ),
) -> None:
    """Generate and store embeddings for all players.

    Uses OpenAI embeddings (text-embedding-3-small) by default.
    Embeddings stored in raw_vector.embeddings with source_table='player'.
    """
    from baseball.vector.embeddings import (
        embed_players,
        fetch_players_for_embedding,
        make_player_text,
    )

    if dry_run:
        players = fetch_players_for_embedding(database_url)
        console.print(f"[yellow]DRY RUN — {len(players)} players would be embedded[/yellow]")
        for p in players[:10]:
            text = make_player_text(
                p["full_name"],
                bats=p["bats"],
                throws=p["throws"],
                birth_year=p["birth_year"],
            )
            console.print(f"  {p['player_id']}: {text}")
        if len(players) > 10:
            console.print(f"  ... and {len(players) - 10} more")
        return

    embedded, written = embed_players(
        database_url=database_url,
        batch_size=batch_size,
        model=model or "text-embedding-3-small",
    )
    console.print(
        f"[green]Embedding complete: {embedded} generated, {written} written to database[/green]"
    )


@vector_app.command("embed-games")
def embed_games_cmd(
    database_url: str = typer.Option(
        ...,
        envvar="DATABASE_URL",
        help="PostgreSQL connection string.",
    ),
    model: Optional[str] = typer.Option(
        None,
        "--model",
        "-m",
        help="Embedding model to use.",
    ),
    batch_size: int = typer.Option(
        100,
        "--batch-size",
        "-n",
        help="Batch size for embedding API calls.",
    ),
    season: Optional[int] = typer.Option(
        None,
        "--season",
        "-s",
        help="Season to filter games.",
    ),
    dry_run: bool = typer.Option(
        False,
        "--dry-run",
        help="Show games to embed without writing.",
    ),
) -> None:
    """Generate and store embeddings for games.

    Uses OpenAI embeddings (text-embedding-3-small) by default.
    Embeddings stored in raw_vector.embeddings with source_table='game'.
    """
    from baseball.vector.embeddings import (
        embed_games,
        fetch_games_for_embedding,
        make_game_text,
    )

    if dry_run:
        games = fetch_games_for_embedding(database_url, season)
        console.print(f"[yellow]DRY RUN — {len(games)} games would be embedded[/yellow]")
        for g in games[:10]:
            text = make_game_text(
                g["home_team"],
                g["away_team"],
                g["game_date"],
                g["venue"],
            )
            console.print(f"  {g['game_id']}: {text}")
        if len(games) > 10:
            console.print(f"  ... and {len(games) - 10} more")
        return

    embedded, written = embed_games(
        database_url=database_url,
        batch_size=batch_size,
        model=model or "text-embedding-3-small",
        season=season,
    )
    console.print(
        f"[green]Embedding complete: {embedded} generated, {written} written to database[/green]"
    )


app.add_typer(vector_app, name="vector")


# ---------------------------------------------------------------------------
# Export commands
# ---------------------------------------------------------------------------

export_app = typer.Typer(help="Export features to Parquet for ML training")


@export_app.command("features")
def export_features_cmd(
    database_url: str = typer.Option(
        ...,
        envvar="DATABASE_URL",
        help="PostgreSQL connection string.",
    ),
    output_dir: str = typer.Option(
        "./exports",
        "--output-dir",
        "-o",
        help="Output directory for parquet files (local or S3 path).",
    ),
    views: Optional[str] = typer.Option(
        None,
        "--views",
        "-v",
        help="Comma-separated list of views to export (default: all).",
    ),
    partition_by: Optional[str] = typer.Option(
        None,
        "--partition-by",
        "-p",
        help="Column to partition output by.",
    ),
    dry_run: bool = typer.Option(
        False,
        "--dry-run",
        help="Show views to export without writing.",
    ),
) -> None:
    """Export materialized views to Parquet format.

    Exports mart.mv_player_statcast_summary, mart.mv_pitch_arsenal_by_season,
    and mart.mv_game_score_context for use in Python/R ML training pipelines.

    Output format: Parquet (supports local filesystem and S3).
    """
    from baseball.export import MART_VIEWS

    if views:
        view_list = [v.strip() for v in views.split(",")]
    else:
        view_list = MART_VIEWS

    if dry_run:
        console.print("[yellow]DRY RUN — views to export:[/yellow]")
        for v in view_list:
            console.print(f"  mart.{v}")
        return

    from baseball.export import export_features

    exported, rows = export_features(
        database_url=database_url,
        views=view_list,
        output_dir=output_dir,
        partition_by=partition_by,
    )
    console.print(
        f"[green]Export complete: {exported} views, {rows} total rows[/green]"
    )


app.add_typer(export_app, name="export")
