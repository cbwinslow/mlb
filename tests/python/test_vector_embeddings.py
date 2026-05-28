"""Tests for baseball/vector/embeddings.py.

Covers embedding providers, text generation, and embed functions.
"""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from baseball.vector.embeddings import (
    EmbeddingProvider,
    OpenAIEmbeddingProvider,
    make_player_text,
    make_game_text,
    write_embeddings,
)


# ---------------------------------------------------------------------------
# make_player_text Tests
# ---------------------------------------------------------------------------


class TestMakePlayerText:
    """Tests for make_player_text function."""

    def test_basic_name_only(self):
        """Creates text with just the name."""
        result = make_player_text("Mike Trout")
        assert result == "Mike Trout"

    def test_includes_bats(self):
        """Includes bats handedness."""
        result = make_player_text("Mike Trout", bats="R")
        assert result == "Mike Trout B:R"

    def test_includes_throws(self):
        """Includes throws handedness."""
        result = make_player_text("Mike Trout", throws="R")
        assert result == "Mike Trout T:R"

    def test_includes_birth_year(self):
        """Includes birth year."""
        result = make_player_text("Mike Trout", birth_year=1991)
        assert result == "Mike Trout 1991"

    def test_all_fields(self):
        """Includes all optional fields."""
        result = make_player_text(
            "Mike Trout",
            bats="R",
            throws="R",
            birth_year=1991,
        )
        assert result == "Mike Trout B:R T:R 1991"

    def test_position_included(self):
        """Includes position when provided."""
        result = make_player_text("Mike Trout", position="OF")
        assert result == "Mike Trout OF"


# ---------------------------------------------------------------------------
# make_game_text Tests
# ---------------------------------------------------------------------------


class TestMakeGameText:
    """Tests for make_game_text function."""

    def test_basic_teams_and_date(self):
        """Creates text with teams and date."""
        result = make_game_text("NYY", "LAA", "2023-04-15")
        assert result == "LAA vs NYY 2023-04-15"

    def test_includes_venue(self):
        """Includes venue when provided."""
        result = make_game_text("NYY", "LAA", "2023-04-15", venue="Yankee Stadium")
        assert result == "LAA vs NYY 2023-04-15 Yankee Stadium"


# ---------------------------------------------------------------------------
# EmbeddingProvider Protocol Tests
# ---------------------------------------------------------------------------


class TestEmbeddingProviderProtocol:
    """Tests for EmbeddingProvider protocol."""

    def test_protocol_check(self):
        """OpenAIEmbeddingProvider satisfies EmbeddingProvider protocol."""
        provider = OpenAIEmbeddingProvider(api_key="test", model="test-model")
        assert isinstance(provider, EmbeddingProvider)


# ---------------------------------------------------------------------------
# OpenAIEmbeddingProvider Tests
# ---------------------------------------------------------------------------


class TestOpenAIEmbeddingProvider:
    """Tests for OpenAIEmbeddingProvider class."""

    def test_init_stores_model(self):
        """Model is stored correctly."""
        provider = OpenAIEmbeddingProvider(api_key="test", model="text-embedding-3-large")
        assert provider.model == "text-embedding-3-large"

    def test_init_default_model(self):
        """Default model is text-embedding-3-small."""
        provider = OpenAIEmbeddingProvider(api_key="test")
        assert provider.model == "text-embedding-3-small"

    def test_embed_calls_api(self):
        """embed calls OpenAI API correctly."""
        mock_client = MagicMock()
        mock_client.embeddings.create.return_value = MagicMock(
            data=[MagicMock(embedding=[0.1] * 1536)]
        )

        with patch("openai.OpenAI", return_value=mock_client):
            provider = OpenAIEmbeddingProvider(api_key="test")
            result = provider.embed("Mike Trout")

        mock_client.embeddings.create.assert_called_once_with(
            model="text-embedding-3-small",
            input="Mike Trout",
        )
        assert len(result) == 1536

    def test_embed_batch_calls_api(self):
        """embed_batch calls OpenAI API with list of texts."""
        mock_client = MagicMock()
        mock_client.embeddings.create.return_value = MagicMock(
            data=[MagicMock(embedding=[0.1] * 1536) for _ in range(3)]
        )

        with patch("openai.OpenAI", return_value=mock_client):
            provider = OpenAIEmbeddingProvider(api_key="test")
            result = provider.embed_batch(["Player 1", "Player 2", "Player 3"])

        mock_client.embeddings.create.assert_called_once_with(
            model="text-embedding-3-small",
            input=["Player 1", "Player 2", "Player 3"],
        )
        assert len(result) == 3

    def test_embed_missing_api_key(self):
        """Raises ValueError when api_key is missing."""
        provider = OpenAIEmbeddingProvider()
        with pytest.raises(ValueError, match="OpenAI API key required"):
            provider.embed("test")

    def test_embed_missing_package(self):
        """Raises ImportError when openai package is missing."""
        provider = OpenAIEmbeddingProvider(api_key="test")
        with patch.dict("sys.modules", {"openai": None}):
            with pytest.raises(ImportError, match="openai package not installed"):
                _ = provider.client


# ---------------------------------------------------------------------------
# write_embeddings Tests
# ---------------------------------------------------------------------------


class TestWriteEmbeddings:
    """Tests for write_embeddings function."""

    def test_write_delegates_to_execute(self):
        """write_embeddings executes correct SQL for each record."""
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.rowcount = 1
        mock_conn.cursor.return_value.__enter__ = MagicMock(return_value=mock_cursor)
        mock_conn.cursor.return_value.__exit__ = MagicMock(return_value=False)

        records = [{"source_id": "123"}, {"source_id": "456"}]
        embeddings = [[0.1] * 1536, [0.2] * 1536]

        with patch("psycopg2.connect", return_value=mock_conn):
            count = write_embeddings(
                "postgresql://test",
                records,
                embeddings,
                "player",
                "text-embedding-3-small",
            )

        assert mock_cursor.execute.call_count == 2
        assert count == 2

    def test_on_conflict_do_nothing(self):
        """Uses ON CONFLICT DO NOTHING by default."""
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_conn.cursor.return_value.__enter__ = MagicMock(return_value=mock_cursor)
        mock_conn.cursor.return_value.__exit__ = MagicMock(return_value=False)

        records = [{"source_id": "123"}]
        embeddings = [[0.1] * 1536]

        with patch("psycopg2.connect", return_value=mock_conn):
            write_embeddings("postgresql://test", records, embeddings, "player", "model")

        call_args = mock_cursor.execute.call_args
        sql = call_args[0][0]
        assert "ON CONFLICT DO NOTHING" in sql

    def test_on_conflict_do_update(self):
        """Uses ON CONFLICT DO UPDATE when specified."""
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_conn.cursor.return_value.__enter__ = MagicMock(return_value=mock_cursor)
        mock_conn.cursor.return_value.__exit__ = MagicMock(return_value=False)

        records = [{"source_id": "123"}]
        embeddings = [[0.1] * 1536]

        with patch("psycopg2.connect", return_value=mock_conn):
            write_embeddings(
                "postgresql://test",
                records,
                embeddings,
                "player",
                "model",
                on_conflict="do_update",
            )

        call_args = mock_cursor.execute.call_args
        sql = call_args[0][0]
        assert "ON CONFLICT DO UPDATE" in sql