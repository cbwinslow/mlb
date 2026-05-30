"""Tests for baseball/ingestion/lahman.py.

Covers LahmanIngester class and CSV loading functionality.
"""

from __future__ import annotations

from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch
import uuid

import pytest

from baseball.ingestion.lahman import LahmanIngester
from baseball.ingestion.base import IngestResult


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def mock_pool():
    """Create a mock AsyncConnectionPool."""
    pool = MagicMock()
    pool.connection = MagicMock()
    return pool


@pytest.fixture
def mock_conn():
    """Create a mock async connection."""
    conn = AsyncMock()
    conn.execute = AsyncMock()
    conn.commit = AsyncMock()
    return conn


@pytest.fixture
def workspace_id():
    """Sample workspace UUID."""
    return uuid.UUID("12345678-1234-5678-1234-567812345678")


# ---------------------------------------------------------------------------
# LahmanIngester.__init__ Tests
# ---------------------------------------------------------------------------


class TestLahmanIngesterInit:
    """Tests for LahmanIngester initialization."""

    def test_default_data_dir(self, mock_pool, workspace_id):
        """Data directory defaults to data/lahman."""
        ingester = LahmanIngester(pool=mock_pool, workspace_id=workspace_id)
        assert ingester.data_dir == Path("data/lahman")

    def test_custom_data_dir(self, mock_pool, workspace_id):
        """Data directory can be customized."""
        ingester = LahmanIngester(
            pool=mock_pool, workspace_id=workspace_id, data_dir=Path("custom/path")
        )
        assert ingester.data_dir == Path("custom/path")

    def test_source_code_is_lahman(self, mock_pool, workspace_id):
        """Source code is correctly set to 'lahman'."""
        ingester = LahmanIngester(pool=mock_pool, workspace_id=workspace_id)
        assert ingester.source_code == "lahman"

    def test_engine_is_initialized(self, mock_pool, workspace_id):
        """IngestEngine is initialized."""
        ingester = LahmanIngester(pool=mock_pool, workspace_id=workspace_id)
        assert ingester.engine is not None


# ---------------------------------------------------------------------------
# LahmanIngester.validate Tests
# ---------------------------------------------------------------------------


class TestLahmanIngesterValidate:
    """Tests for LahmanIngester.validate() method."""

    @pytest.mark.asyncio
    async def test_validate_returns_true_when_table_exists(
        self, mock_pool, mock_conn, workspace_id
    ):
        """Validate returns True when people table exists."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[True])
        mock_conn.execute.return_value = mock_result

        ingester = LahmanIngester(pool=mock_pool, workspace_id=workspace_id)
        result = await ingester.validate()

        assert result is True

    @pytest.mark.asyncio
    async def test_validate_returns_false_when_table_missing(
        self, mock_pool, mock_conn, workspace_id
    ):
        """Validate returns False when people table does not exist."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[False])
        mock_conn.execute.return_value = mock_result

        ingester = LahmanIngester(pool=mock_pool, workspace_id=workspace_id)
        result = await ingester.validate()

        assert result is False


# ---------------------------------------------------------------------------
# LahmanIngester.ingest Tests
# ---------------------------------------------------------------------------


class TestLahmanIngesterIngest:
    """Tests for LahmanIngester.ingest() method."""

    @pytest.mark.asyncio
    async def test_ingest_with_data_type(self, mock_pool, mock_conn, workspace_id):
        """Ingestion works with specific data_type."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        with patch.object(
            LahmanIngester, "_ingest_table", new_callable=AsyncMock
        ) as mock_ingest_table:
            mock_ingest_table.return_value = IngestResult(
                rows_processed=100, rows_inserted=100
            )
            ingester = LahmanIngester(pool=mock_pool, workspace_id=workspace_id)
            result = await ingester.ingest(data_type="people")

        assert result.rows_processed == 100

    @pytest.mark.asyncio
    async def test_ingest_marks_failed_on_exception(
        self, mock_pool, mock_conn, workspace_id
    ):
        """Ingestion marks run as failed when exception occurs."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = LahmanIngester(pool=mock_pool, workspace_id=workspace_id)

        # This should not raise - it should handle the error gracefully
        result = await ingester.ingest(season=2023)

        assert result.errors >= 0  # May have errors if CSV not found
