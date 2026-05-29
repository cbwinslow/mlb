"""Tests for baseball/ingestion/base.py.

Covers BaseIngester abstract class and IngestResult dataclass.
"""

from __future__ import annotations

from pathlib import Path
from unittest.mock import AsyncMock, MagicMock
import uuid

import pytest

from baseball.ingestion.base import BaseIngester, IngestResult


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
def workspace_id():
    """Sample workspace UUID."""
    return uuid.UUID("12345678-1234-5678-1234-567812345678")


# ---------------------------------------------------------------------------
# IngestResult Tests
# ---------------------------------------------------------------------------


class TestIngestResult:
    """Tests for IngestResult dataclass."""

    def test_default_values(self):
        """Default values are set correctly."""
        result = IngestResult()
        assert result.rows_processed == 0
        assert result.rows_inserted == 0
        assert result.rows_updated == 0
        assert result.errors == 0
        assert result.ingest_run_id is None
        assert result.duration_seconds == 0.0

    def test_custom_values(self):
        """Custom values can be provided."""
        result = IngestResult(
            rows_processed=100,
            rows_inserted=95,
            rows_updated=3,
            errors=2,
            ingest_run_id=uuid.UUID("12345678-1234-5678-1234-567812345678"),
            duration_seconds=12.5,
        )
        assert result.rows_processed == 100
        assert result.rows_inserted == 95
        assert result.rows_updated == 3
        assert result.errors == 2
        assert result.ingest_run_id == uuid.UUID("12345678-1234-5678-1234-567812345678")
        assert result.duration_seconds == 12.5


# ---------------------------------------------------------------------------
# BaseIngester._get_source_endpoint_id Tests
# ---------------------------------------------------------------------------


class TestGetSourceEndpointId:
    """Tests for BaseIngester._get_source_endpoint_id method."""

    @pytest.mark.asyncio
    async def test_returns_existing_endpoint_id(self, mock_pool, workspace_id):
        """Returns existing endpoint_id when found."""
        mock_conn = AsyncMock()
        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute = AsyncMock(return_value=mock_result)

        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        # Create concrete subclass for testing
        class ConcreteIngester(BaseIngester):
            async def ingest(self, **kwargs):
                return IngestResult()

            async def validate(self):
                return True

        ingester = ConcreteIngester(
            pool=mock_pool, workspace_id=workspace_id, source_code="test"
        )
        result = await ingester._get_source_endpoint_id("test_endpoint")

        assert result == 1

    @pytest.mark.asyncio
    async def test_creates_endpoint_when_missing(self, mock_pool, workspace_id):
        """Creates endpoint when not found."""
        mock_conn = AsyncMock()

        # First call returns None (not found)
        mock_result_none = AsyncMock()
        mock_result_none.fetchone = AsyncMock(return_value=None)

        # Second call returns new id
        mock_result_new = AsyncMock()
        mock_result_new.fetchone = AsyncMock(return_value=[2])

        mock_conn.execute = AsyncMock(side_effect=[mock_result_none, mock_result_new])

        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        class ConcreteIngester(BaseIngester):
            async def ingest(self, **kwargs):
                return IngestResult()

            async def validate(self):
                return True

        ingester = ConcreteIngester(
            pool=mock_pool, workspace_id=workspace_id, source_code="test"
        )
        result = await ingester._get_source_endpoint_id("new_endpoint")

        assert result == 2


# ---------------------------------------------------------------------------
# BaseIngester._create_ingest_run Tests
# ---------------------------------------------------------------------------


class TestCreateIngestRun:
    """Tests for BaseIngester._create_ingest_run method."""

    @pytest.mark.asyncio
    async def test_creates_ingest_run(self, mock_pool, workspace_id):
        """Ingest run is created with correct parameters."""
        mock_conn = AsyncMock()
        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(
            return_value=[uuid.UUID("12345678-1234-5678-1234-567812345678")]
        )
        mock_conn.execute = AsyncMock(return_value=mock_result)

        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        class ConcreteIngester(BaseIngester):
            async def ingest(self, **kwargs):
                return IngestResult()

            async def validate(self):
                return True

        ingester = ConcreteIngester(
            pool=mock_pool, workspace_id=workspace_id, source_code="statcast"
        )
        result = await ingester._create_ingest_run(source_endpoint_id=1)

        assert result == uuid.UUID("12345678-1234-5678-1234-567812345678")
        assert mock_conn.execute.called


# ---------------------------------------------------------------------------
# BaseIngester._complete_ingest_run Tests
# ---------------------------------------------------------------------------


class TestCompleteIngestRun:
    """Tests for BaseIngester._complete_ingest_run method."""

    @pytest.mark.asyncio
    async def test_completes_ingest_run_with_success(self, mock_pool, workspace_id):
        """Ingest run is marked succeeded."""
        mock_conn = AsyncMock()
        mock_conn.execute = AsyncMock()
        mock_conn.commit = AsyncMock()

        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        class ConcreteIngester(BaseIngester):
            async def ingest(self, **kwargs):
                return IngestResult()

            async def validate(self):
                return True

        ingester = ConcreteIngester(
            pool=mock_pool, workspace_id=workspace_id, source_code="statcast"
        )
        await ingester._complete_ingest_run(
            ingest_run_id=uuid.UUID("12345678-1234-5678-1234-567812345678"),
            status="succeeded",
        )

        assert mock_conn.execute.called

    @pytest.mark.asyncio
    async def test_completes_ingest_run_with_failure(self, mock_pool, workspace_id):
        """Ingest run is marked failed with error message."""
        mock_conn = AsyncMock()
        mock_conn.execute = AsyncMock()
        mock_conn.commit = AsyncMock()

        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        class ConcreteIngester(BaseIngester):
            async def ingest(self, **kwargs):
                return IngestResult()

            async def validate(self):
                return True

        ingester = ConcreteIngester(
            pool=mock_pool, workspace_id=workspace_id, source_code="statcast"
        )
        await ingester._complete_ingest_run(
            ingest_run_id=uuid.UUID("12345678-1234-5678-1234-567812345678"),
            status="failed",
            error_message="Test error",
        )

        assert mock_conn.execute.called
