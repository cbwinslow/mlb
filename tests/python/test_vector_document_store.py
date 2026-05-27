"""Tests for baseball/vector/document_store.py.

Covers VectorStoreManager and document creation functions.
"""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from baseball.vector.document_store import (
    VectorStoreManager,
    create_player_document,
    create_game_document,
)
from haystack import Document


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def sample_embedding():
    """Sample 1536-dimension embedding vector."""
    return [0.1] * 1536


# ---------------------------------------------------------------------------
# VectorStoreManager.__init__ Tests
# ---------------------------------------------------------------------------


class TestVectorStoreManagerInit:
    """Tests for VectorStoreManager initialization."""

    def test_default_qdrant_location(self):
        """Default qdrant_location is set correctly."""
        manager = VectorStoreManager(pgvector_connection_str="postgresql://test")
        assert manager.qdrant_location == "http://localhost:6333"

    def test_custom_qdrant_location(self):
        """Custom qdrant_location can be provided."""
        manager = VectorStoreManager(
            pgvector_connection_str="postgresql://test",
            qdrant_location="http://custom:6333",
        )
        assert manager.qdrant_location == "http://custom:6333"

    def test_pgvector_connection_str_stored(self):
        """pgvector_connection_str is stored correctly."""
        manager = VectorStoreManager(pgvector_connection_str="postgresql://test")
        assert manager.pgvector_connection_str == "postgresql://test"

    def test_qdrant_api_key_stored(self):
        """qdrant_api_key is stored correctly."""
        manager = VectorStoreManager(
            pgvector_connection_str="postgresql://test",
            qdrant_api_key="secret-key",
        )
        assert manager.qdrant_api_key == "secret-key"


# ---------------------------------------------------------------------------
# VectorStoreManager.pgvector_store Tests
# ---------------------------------------------------------------------------


class TestPgVectorStore:
    """Tests for VectorStoreManager.pgvector_store property."""

    def test_raises_without_connection_str(self):
        """Raises ValueError when pgvector_connection_str is not provided."""
        manager = VectorStoreManager()
        with pytest.raises(ValueError, match="pgvector_connection_str required"):
            _ = manager.pgvector_store

    def test_creates_pgvector_store(self, sample_embedding):
        """Creates PgvectorDocumentStore with correct parameters."""
        manager = VectorStoreManager(pgvector_connection_str="postgresql://test")

        with patch(
            "baseball.vector.document_store.PgvectorDocumentStore",
            autospec=True,
        ) as mock_store_class:
            mock_store = MagicMock()
            mock_store_class.return_value = mock_store

            store = manager.pgvector_store

            mock_store_class.assert_called_once_with(
                connection_string="postgresql://test",
                embedding_dimension=1536,
                vector_function="cosine_similarity",
                search_strategy="exact",
            )
            assert store == mock_store

    def test_lazy_initialization(self, sample_embedding):
        """PgVector store is lazily initialized."""
        manager = VectorStoreManager(pgvector_connection_str="postgresql://test")

        with patch(
            "baseball.vector.document_store.PgvectorDocumentStore",
            autospec=True,
        ) as mock_store_class:
            mock_store = MagicMock()
            mock_store_class.return_value = mock_store

            # Access twice
            _ = manager.pgvector_store
            _ = manager.pgvector_store

            # Should only be created once
            mock_store_class.assert_called_once()


# ---------------------------------------------------------------------------
# VectorStoreManager.qdrant_store Tests
# ---------------------------------------------------------------------------


class TestQdrantStore:
    """Tests for VectorStoreManager.qdrant_store property."""

    def test_creates_qdrant_store(self, sample_embedding):
        """Creates QdrantDocumentStore with correct parameters."""
        manager = VectorStoreManager()

        with patch(
            "baseball.vector.document_store.QdrantDocumentStore",
            autospec=True,
        ) as mock_store_class:
            mock_store = MagicMock()
            mock_store_class.return_value = mock_store

            store = manager.qdrant_store

            mock_store_class.assert_called_once_with(
                location="http://localhost:6333",
                api_key=None,
                embedding_dim=1536,
                use_sparse_embeddings=False,
            )
            assert store == mock_store

    def test_qdrant_store_with_api_key(self, sample_embedding):
        """Creates QdrantDocumentStore with API key."""
        manager = VectorStoreManager(qdrant_api_key="test-key")

        with patch(
            "baseball.vector.document_store.QdrantDocumentStore",
            autospec=True,
        ) as mock_store_class:
            mock_store = MagicMock()
            mock_store_class.return_value = mock_store

            _ = manager.qdrant_store

            mock_store_class.assert_called_once_with(
                location="http://localhost:6333",
                api_key="test-key",
                embedding_dim=1536,
                use_sparse_embeddings=False,
            )


# ---------------------------------------------------------------------------
# VectorStoreManager.get_store Tests
# ---------------------------------------------------------------------------


class TestGetStore:
    """Tests for VectorStoreManager.get_store method."""

    def test_get_store_pgvector(self, sample_embedding):
        """get_store returns PgvectorDocumentStore for pgvector backend."""
        manager = VectorStoreManager(pgvector_connection_str="postgresql://test")

        with patch(
            "baseball.vector.document_store.PgvectorDocumentStore",
            autospec=True,
        ) as mock_store_class:
            mock_store = MagicMock()
            mock_store_class.return_value = mock_store

            store = manager.get_store(backend="pgvector")

            assert store == mock_store

    def test_get_store_qdrant(self, sample_embedding):
        """get_store returns QdrantDocumentStore for qdrant backend."""
        manager = VectorStoreManager()

        with patch(
            "baseball.vector.document_store.QdrantDocumentStore",
            autospec=True,
        ) as mock_store_class:
            mock_store = MagicMock()
            mock_store_class.return_value = mock_store

            store = manager.get_store(backend="qdrant")

            assert store == mock_store

    def test_get_store_unknown_backend(self, sample_embedding):
        """Raises ValueError for unknown backend."""
        manager = VectorStoreManager()

        with pytest.raises(ValueError, match="Unknown backend"):
            manager.get_store(backend="unknown")


# ---------------------------------------------------------------------------
# VectorStoreManager.write_documents Tests
# ---------------------------------------------------------------------------


class TestWriteDocuments:
    """Tests for VectorStoreManager.write_documents method."""

    def test_write_documents_pgvector(self, sample_embedding):
        """write_documents writes to PgvectorDocumentStore."""
        manager = VectorStoreManager(pgvector_connection_str="postgresql://test")

        with patch(
            "baseball.vector.document_store.PgvectorDocumentStore",
            autospec=True,
        ) as mock_store_class:
            mock_store = MagicMock()
            mock_store.write_documents.return_value = 5
            mock_store_class.return_value = mock_store

            docs = [
                Document(content="Player 1", embedding=sample_embedding, meta={"id": "1"}),
                Document(content="Player 2", embedding=sample_embedding, meta={"id": "2"}),
            ]

            count = manager.write_documents(docs, backend="pgvector")

            assert count == 5
            mock_store.write_documents.assert_called_once_with(docs)

    def test_write_documents_qdrant_with_collection(self, sample_embedding):
        """write_documents sets collection name for Qdrant."""
        manager = VectorStoreManager()

        with patch(
            "baseball.vector.document_store.QdrantDocumentStore",
            autospec=True,
        ) as mock_store_class:
            mock_store = MagicMock()
            mock_store.write_documents.return_value = 3
            mock_store_class.return_value = mock_store

            docs = [
                Document(content="Game 1", embedding=sample_embedding, meta={"id": "1"}),
            ]

            count = manager.write_documents(docs, backend="qdrant", collection="games")

            assert mock_store.collection_name == "games"
            assert count == 3


# ---------------------------------------------------------------------------
# VectorStoreManager.query Tests
# ---------------------------------------------------------------------------


class TestQuery:
    """Tests for VectorStoreManager.query method."""

    def test_query_pgvector(self, sample_embedding):
        """query searches PgvectorDocumentStore."""
        manager = VectorStoreManager(pgvector_connection_str="postgresql://test")

        with patch(
            "baseball.vector.document_store.PgvectorDocumentStore",
            autospec=True,
        ) as mock_store_class:
            mock_store = MagicMock()
            mock_store.query_by_embedding.return_value = [
                Document(content="Result 1", embedding=sample_embedding, meta={"id": "1"}),
            ]
            mock_store_class.return_value = mock_store

            results = manager.query(sample_embedding, backend="pgvector", top_k=5)

            assert len(results) == 1
            mock_store.query_by_embedding.assert_called_once_with(query=sample_embedding, top_k=5)

    def test_query_qdrant_with_collection(self, sample_embedding):
        """query sets collection name for Qdrant."""
        manager = VectorStoreManager()

        with patch(
            "baseball.vector.document_store.QdrantDocumentStore",
            autospec=True,
        ) as mock_store_class:
            mock_store = MagicMock()
            mock_store.query_by_embedding.return_value = []
            mock_store_class.return_value = mock_store

            results = manager.query(
                sample_embedding, backend="qdrant", collection="players", top_k=10
            )

            assert mock_store.collection_name == "players"


# ---------------------------------------------------------------------------
# create_player_document Tests
# ---------------------------------------------------------------------------


class TestCreatePlayerDocument:
    """Tests for create_player_document function."""

    def test_creates_document_with_required_fields(self, sample_embedding):
        """Creates Document with player_id, name, and embedding."""
        doc = create_player_document(
            player_id="12345",
            name="Mike Trout",
            embedding=sample_embedding,
        )

        assert isinstance(doc, Document)
        assert doc.content == "Mike Trout"
        assert doc.embedding == sample_embedding
        assert doc.meta["player_id"] == "12345"
        assert doc.meta["name"] == "Mike Trout"

    def test_includes_season_when_provided(self, sample_embedding):
        """Includes season in metadata when provided."""
        doc = create_player_document(
            player_id="12345",
            name="Mike Trout",
            embedding=sample_embedding,
            season=2023,
        )

        assert doc.meta["season"] == 2023

    def test_includes_team_when_provided(self, sample_embedding):
        """Includes team in metadata when provided."""
        doc = create_player_document(
            player_id="12345",
            name="Mike Trout",
            embedding=sample_embedding,
            team="LAA",
        )

        assert doc.meta["team"] == "LAA"

    def test_includes_additional_metadata(self, sample_embedding):
        """Includes additional metadata fields."""
        doc = create_player_document(
            player_id="12345",
            name="Mike Trout",
            embedding=sample_embedding,
            metadata={"position": "OF", "bats": "R"},
        )

        assert doc.meta["position"] == "OF"
        assert doc.meta["bats"] == "R"

    def test_merges_metadata(self, sample_embedding):
        """Merges season/team with additional metadata."""
        doc = create_player_document(
            player_id="12345",
            name="Mike Trout",
            embedding=sample_embedding,
            season=2023,
            team="LAA",
            metadata={"position": "OF"},
        )

        assert doc.meta["player_id"] == "12345"
        assert doc.meta["name"] == "Mike Trout"
        assert doc.meta["season"] == 2023
        assert doc.meta["team"] == "LAA"
        assert doc.meta["position"] == "OF"


# ---------------------------------------------------------------------------
# create_game_document Tests
# ---------------------------------------------------------------------------


class TestCreateGameDocument:
    """Tests for create_game_document function."""

    def test_creates_document_with_required_fields(self, sample_embedding):
        """Creates Document with game_id, date, and embedding."""
        doc = create_game_document(
            game_id="2023/04/15/laa-nyy",
            date="2023-04-15",
            embedding=sample_embedding,
        )

        assert isinstance(doc, Document)
        assert doc.meta["game_id"] == "2023/04/15/laa-nyy"
        assert doc.meta["date"] == "2023-04-15"
        assert doc.embedding == sample_embedding

    def test_default_content_is_game_id(self, sample_embedding):
        """Default content is 'Game {game_id}'."""
        doc = create_game_document(
            game_id="2023/04/15/laa-nyy",
            date="2023-04-15",
            embedding=sample_embedding,
        )

        assert doc.content == "Game 2023/04/15/laa-nyy"

    def test_custom_content(self, sample_embedding):
        """Custom content can be provided."""
        doc = create_game_document(
            game_id="2023/04/15/laa-nyy",
            date="2023-04-15",
            embedding=sample_embedding,
            content="LAA vs NYY - Extra innings thriller",
        )

        assert doc.content == "LAA vs NYY - Extra innings thriller"

    def test_includes_teams_when_provided(self, sample_embedding):
        """Includes home_team and away_team in metadata."""
        doc = create_game_document(
            game_id="2023/04/15/laa-nyy",
            date="2023-04-15",
            embedding=sample_embedding,
            home_team="NYY",
            away_team="LAA",
        )

        assert doc.meta["home_team"] == "NYY"
        assert doc.meta["away_team"] == "LAA"

    def test_includes_additional_metadata(self, sample_embedding):
        """Includes additional metadata fields."""
        doc = create_game_document(
            game_id="2023/04/15/laa-nyy",
            date="2023-04-15",
            embedding=sample_embedding,
            metadata={"attendance": 45000, "duration": "3:15"},
        )

        assert doc.meta["attendance"] == 45000
        assert doc.meta["duration"] == "3:15"