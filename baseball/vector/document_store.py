"""baseball.vector.document_store — Haystack document store integration.

Provides vector storage backends for similarity search using Qdrant and PgVector.
"""

from __future__ import annotations

import logging
from typing import Optional

from haystack_integrations.document_stores.pgvector import PgvectorDocumentStore
from haystack_integrations.document_stores.qdrant import QdrantDocumentStore
from haystack import Document

log = logging.getLogger(__name__)


class VectorStoreManager:
    """Manager for vector document stores.

    Supports both PgVector (PostgreSQL) and Qdrant backends.
    """

    def __init__(
        self,
        pgvector_connection_str: Optional[str] = None,
        qdrant_location: Optional[str] = "http://localhost:6333",
        qdrant_api_key: Optional[str] = None,
    ):
        self.pgvector_connection_str = pgvector_connection_str
        self.qdrant_location = qdrant_location
        self.qdrant_api_key = qdrant_api_key
        self._pgvector_store: Optional[PgvectorDocumentStore] = None
        self._qdrant_store: Optional[QdrantDocumentStore] = None

    @property
    def pgvector_store(self) -> PgvectorDocumentStore:
        """Lazy-initialized PgVector document store."""
        if self._pgvector_store is None:
            if not self.pgvector_connection_str:
                raise ValueError("pgvector_connection_str required for PgVector store")
            self._pgvector_store = PgvectorDocumentStore(
                connection_string=self.pgvector_connection_str,
                embedding_dimension=1536,
                vector_function="cosine_similarity",
                search_strategy="exact",
            )
        return self._pgvector_store

    @property
    def qdrant_store(self) -> QdrantDocumentStore:
        """Lazy-initialized Qdrant document store."""
        if self._qdrant_store is None:
            self._qdrant_store = QdrantDocumentStore(
                location=self.qdrant_location,
                api_key=self.qdrant_api_key,
                embedding_dim=1536,
                use_sparse_embeddings=False,
            )
        return self._qdrant_store

    def get_store(
        self, backend: str = "pgvector"
    ) -> PgvectorDocumentStore | QdrantDocumentStore:
        """Get the appropriate document store.

        Args:
            backend: 'pgvector' or 'qdrant'

        Returns:
            The requested document store instance.
        """
        if backend == "pgvector":
            return self.pgvector_store
        elif backend == "qdrant":
            return self.qdrant_store
        else:
            raise ValueError(f"Unknown backend: {backend}")

    def write_documents(
        self,
        documents: list[Document],
        backend: str = "pgvector",
        collection: Optional[str] = None,
    ) -> int:
        """Write documents to the vector store.

        Args:
            documents: List of Haystack Document objects
            backend: 'pgvector' or 'qdrant'
            collection: Qdrant collection name (required for qdrant backend)

        Returns:
            Number of documents written.
        """
        store = self.get_store(backend)
        if backend == "qdrant" and collection:
            store.collection_name = collection
        return store.write_documents(documents)

    def query(
        self,
        query_embedding: list[float],
        backend: str = "pgvector",
        collection: Optional[str] = None,
        top_k: int = 10,
    ) -> list[Document]:
        """Query for similar documents.

        Args:
            query_embedding: Query vector
            backend: 'pgvector' or 'qdrant'
            collection: Qdrant collection name (required for qdrant backend)
            top_k: Number of results to return

        Returns:
            List of matching Document objects.
        """
        store = self.get_store(backend)
        if backend == "qdrant" and collection:
            store.collection_name = collection
        return store.query_by_embedding(query=query_embedding, top_k=top_k)


def create_player_document(
    player_id: str,
    name: str,
    embedding: list[float],
    season: Optional[int] = None,
    team: Optional[str] = None,
    metadata: Optional[dict] = None,
) -> Document:
    """Create a Haystack Document for a player.

    Args:
        player_id: MLBAM or other player ID
        name: Player name
        embedding: Vector embedding
        season: Optional season
        team: Optional team
        metadata: Additional metadata

    Returns:
        Haystack Document with player data.
    """
    doc_metadata = {
        "player_id": player_id,
        "name": name,
        **(metadata or {}),
    }
    if season:
        doc_metadata["season"] = season
    if team:
        doc_metadata["team"] = team

    return Document(
        content=name,
        embedding=embedding,
        meta=doc_metadata,
    )


def create_game_document(
    game_id: str,
    date: str,
    embedding: list[float],
    home_team: Optional[str] = None,
    away_team: Optional[str] = None,
    metadata: Optional[dict] = None,
    content: Optional[str] = None,
) -> Document:
    """Create a Haystack Document for a game.

    Args:
        game_id: Game identifier
        date: Game date
        embedding: Vector embedding
        home_team: Home team name
        away_team: Away team name
        metadata: Additional metadata
        content: Optional content string

    Returns:
        Haystack Document with game data.
    """
    doc_metadata = {
        "game_id": game_id,
        "date": date,
        **(metadata or {}),
    }
    if home_team:
        doc_metadata["home_team"] = home_team
    if away_team:
        doc_metadata["away_team"] = away_team

    return Document(
        content=content or f"Game {game_id}",
        embedding=embedding,
        meta=doc_metadata,
    )
