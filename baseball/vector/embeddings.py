"""baseball.vector.embeddings — Embedding generation and storage.

Provides embedding providers and functions to generate/store embeddings for
players, games, and other entities in the MLB analytics platform.
"""

from __future__ import annotations

import logging
from typing import Optional, Protocol, runtime_checkable

import psycopg2
from rich.console import Console
from rich.progress import (
    BarColumn,
    Progress,
    SpinnerColumn,
    TaskProgressColumn,
    TextColumn,
)

log = logging.getLogger(__name__)
console = Console()


@runtime_checkable
class EmbeddingProvider(Protocol):
    """Protocol for embedding providers."""

    def embed(self, text: str) -> list[float]:
        """Generate embedding for a single text string."""
        ...

    def embed_batch(self, texts: list[str]) -> list[list[float]]:
        """Generate embeddings for multiple text strings."""
        ...


class OpenAIEmbeddingProvider:
    """OpenAI embedding provider implementation."""

    def __init__(
        self,
        api_key: Optional[str] = None,
        model: str = "text-embedding-3-small",
    ):
        self.api_key = api_key
        self.model = model
        self._client = None

    @property
    def client(self):
        """Lazy-initialized OpenAI client."""
        if self._client is None:
            if not self.api_key:
                raise ValueError("OpenAI API key required for embedding generation")
            try:
                from openai import OpenAI

                self._client = OpenAI(api_key=self.api_key)
            except ImportError as exc:
                raise ImportError(
                    "openai package not installed. Run: pip install openai"
                ) from exc
        return self._client

    def embed(self, text: str) -> list[float]:
        """Generate embedding for a single text string."""
        result = self.client.embeddings.create(
            model=self.model,
            input=text,
        )
        return result.data[0].embedding

    def embed_batch(self, texts: list[str]) -> list[list[float]]:
        """Generate embeddings for multiple text strings."""
        result = self.client.embeddings.create(
            model=self.model,
            input=texts,
        )
        return [d.embedding for d in result.data]


def make_player_text(
    full_name: str,
    position: Optional[str] = None,
    bats: Optional[str] = None,
    throws: Optional[str] = None,
    birth_year: Optional[int] = None,
) -> str:
    """Create text description for player embedding.

    Args:
        full_name: Player name
        position: Primary position (e.g., "OF", "P")
        bats: Bats handedness ("L" or "R")
        throws: Throws handedness ("L" or "R")
        birth_year: Birth year (extracted from birth_date)

    Returns:
        Combined text string for embedding.
    """
    parts = [full_name]
    if position:
        parts.append(position)
    if bats:
        parts.append(f"B:{bats}")
    if throws:
        parts.append(f"T:{throws}")
    if birth_year:
        parts.append(str(birth_year))
    return " ".join(parts)


def make_game_text(
    home_team: str,
    away_team: str,
    game_date: str,
    venue: Optional[str] = None,
) -> str:
    """Create text description for game embedding.

    Args:
        home_team: Home team code/name
        away_team: Away team code/name
        game_date: Game date (YYYY-MM-DD)
        venue: Optional venue name

    Returns:
        Combined text string for embedding.
    """
    parts = [f"{away_team} vs {home_team}", game_date]
    if venue:
        parts.append(venue)
    return " ".join(parts)


def fetch_players_for_embedding(
    database_url: str,
    season: Optional[int] = None,
    min_games: Optional[int] = None,
) -> list[dict]:
    """Fetch players from core.player for embedding.

    Args:
        database_url: PostgreSQL connection string
        season: Optional season filter (not yet implemented for core.player)
        min_games: Optional minimum games threshold (not yet implemented)

    Returns:
        List of player dicts with player_id, full_name, etc.
    """
    sql = """
        SELECT player_id,
               full_name,
               bats,
               throws,
               birth_date
        FROM   core.player
    """
    conn = psycopg2.connect(database_url)
    try:
        with conn.cursor() as cur:
            cur.execute(sql)
            rows = cur.fetchall()
        return [
            {
                "player_id": r[0],
                "full_name": r[1],
                "bats": r[2],
                "throws": r[3],
                "birth_year": r[4].year if r[4] else None,
            }
            for r in rows
        ]
    finally:
        conn.close()


def fetch_games_for_embedding(
    database_url: str,
    season: Optional[int] = None,
) -> list[dict]:
    """Fetch games from core.games for embedding.

    Args:
        database_url: PostgreSQL connection string
        season: Optional season filter

    Returns:
        List of game dicts with game_id, teams, date, venue.
    """
    sql = """
        SELECT g.game_id,
               ht.team_name as home_team,
               at.team_name as away_team,
               g.game_date,
               v.venue_name
        FROM   core.games g
        JOIN   core.team ht ON g.home_team_id = ht.team_id
        JOIN   core.team at ON g.away_team_id = at.team_id
        LEFT JOIN core.venue v ON g.venue_id = v.venue_id
    """
    params = []
    if season:
        sql += " WHERE EXTRACT(YEAR FROM g.game_date) = %s"
        params.append(season)

    conn = psycopg2.connect(database_url)
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params if params else None)
            rows = cur.fetchall()
        return [
            {
                "game_id": r[0],
                "home_team": r[1],
                "away_team": r[2],
                "game_date": r[3],
                "venue": r[4],
            }
            for r in rows
        ]
    finally:
        conn.close()


def write_embeddings(
    database_url: str,
    records: list[dict],
    embeddings: list[list[float]],
    source_table: str,
    model: str,
    provider: str = "openai",
    on_conflict: str = "do_nothing",
) -> int:
    """Write embeddings to raw_vector.embeddings table.

    Args:
        database_url: PostgreSQL connection string
        records: List of records with source_id
        embeddings: List of embedding vectors
        source_table: Source table name (without schema)
        model: Embedding model name
        provider: Embedding provider name
        on_conflict: "do_nothing" or "do_update"

    Returns:
        Number of rows written.
    """
    if on_conflict == "do_nothing":
        conflict_sql = "ON CONFLICT DO NOTHING"
    else:
        conflict_sql = (
            "ON CONFLICT DO UPDATE SET embedding_vector = EXCLUDED.embedding_vector"
        )

    sql = f"""
        INSERT INTO raw_vector.embeddings
            (source_schema, source_table, source_id, embedding_vector, embedding_model, embedding_provider)
        VALUES
            (%(schema)s, %(table)s, %(id)s, %(vec)s, %(model)s, %(provider)s)
        {conflict_sql}
    """

    count = 0
    conn = psycopg2.connect(database_url)
    try:
        with conn.cursor() as cur:
            for record, emb in zip(records, embeddings, strict=True):
                cur.execute(
                    sql,
                    {
                        "schema": "core",
                        "table": source_table,
                        "id": str(record["source_id"]),
                        "vec": emb,
                        "model": model,
                        "provider": provider,
                    },
                )
                count += cur.rowcount
            conn.commit()
    finally:
        conn.close()

    return count


def embed_players(
    database_url: str,
    provider: Optional[EmbeddingProvider] = None,
    batch_size: int = 100,
    model: str = "text-embedding-3-small",
) -> tuple[int, int]:
    """Generate and store embeddings for all players.

    Args:
        database_url: PostgreSQL connection string
        provider: Optional EmbeddingProvider (creates OpenAI provider if not provided)
        batch_size: Batch size for embedding API calls
        model: Embedding model name

    Returns:
        Tuple of (players_processed, embeddings_written)
    """
    if provider is None:
        try:
            from baseball.settings import get_settings

            settings = get_settings()
            provider = OpenAIEmbeddingProvider(
                api_key=settings.vector.openai_api_key,
                model=model,
            )
        except ImportError:
            raise ImportError(
                "OpenAI provider requires openai package. Run: pip install openai"
            )

    players = fetch_players_for_embedding(database_url)
    total_embedded = 0
    total_written = 0

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{{task.description}}"),
        BarColumn(),
        TaskProgressColumn(),
        console=console,
    ) as progress:
        task = progress.add_task("Embedding players...", total=len(players))

        for i in range(0, len(players), batch_size):
            batch = players[i : i + batch_size]
            texts = [
                make_player_text(
                    p["full_name"],
                    bats=p["bats"],
                    throws=p["throws"],
                    birth_year=p["birth_year"],
                )
                for p in batch
            ]

            embeddings = provider.embed_batch(texts)
            total_embedded += len(embeddings)

            records = [{"source_id": p["player_id"]} for p in batch]
            written = write_embeddings(
                database_url,
                records,
                embeddings,
                "player",
                model,
            )
            total_written += written

            progress.advance(task, len(batch))

    return total_embedded, total_written


def embed_games(
    database_url: str,
    provider: Optional[EmbeddingProvider] = None,
    batch_size: int = 100,
    model: str = "text-embedding-3-small",
    season: Optional[int] = None,
) -> tuple[int, int]:
    """Generate and store embeddings for games.

    Args:
        database_url: PostgreSQL connection string
        provider: Optional EmbeddingProvider
        batch_size: Batch size for embedding API calls
        model: Embedding model name
        season: Optional season filter

    Returns:
        Tuple of (games_processed, embeddings_written)
    """
    if provider is None:
        try:
            from baseball.settings import get_settings

            settings = get_settings()
            provider = OpenAIEmbeddingProvider(
                api_key=settings.vector.openai_api_key,
                model=model,
            )
        except ImportError:
            raise ImportError(
                "OpenAI provider requires openai package. Run: pip install openai"
            )

    games = fetch_games_for_embedding(database_url, season)
    total_embedded = 0
    total_written = 0

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{{task.description}}"),
        BarColumn(),
        TaskProgressColumn(),
        console=console,
    ) as progress:
        task = progress.add_task("Embedding games...", total=len(games))

        for i in range(0, len(games), batch_size):
            batch = games[i : i + batch_size]
            texts = [
                make_game_text(
                    g["home_team"],
                    g["away_team"],
                    g["game_date"],
                    g["venue"],
                )
                for g in batch
            ]

            embeddings = provider.embed_batch(texts)
            total_embedded += len(embeddings)

            records = [{"source_id": g["game_id"]} for g in batch]
            written = write_embeddings(
                database_url,
                records,
                embeddings,
                "game",
                model,
            )
            total_written += written

            progress.advance(task, len(batch))

    return total_embedded, total_written
