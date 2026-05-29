"""Tests for baseball/ingestion/retrosheet.py.

Covers RetrosheetIngester class and Retrosheet event file parsing.
"""

from __future__ import annotations

import tempfile
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch
import uuid

import pytest

from baseball.ingestion.retrosheet import RetrosheetIngester
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
# RetrosheetIngester.__init__ Tests
# ---------------------------------------------------------------------------


class TestRetrosheetIngesterInit:
    """Tests for RetrosheetIngester initialization."""

    def test_default_data_dir(self, mock_pool, workspace_id):
        """Default data_dir is set correctly."""
        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)
        assert ingester.data_dir == Path("data/retrosheet")

    def test_custom_data_dir(self, mock_pool, workspace_id):
        """Custom data_dir can be provided."""
        custom_dir = Path("/custom/data")
        ingester = RetrosheetIngester(
            pool=mock_pool, workspace_id=workspace_id, data_dir=custom_dir
        )
        assert ingester.data_dir == custom_dir

    def test_source_code_is_retrosheet(self, mock_pool, workspace_id):
        """Source code is set to 'retrosheet'."""
        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)
        assert ingester.source_code == "retrosheet"


# ---------------------------------------------------------------------------
# RetrosheetIngester.validate Tests
# ---------------------------------------------------------------------------


class TestRetrosheetIngesterValidate:
    """Tests for RetrosheetIngester.validate method."""

    @pytest.mark.asyncio
    async def test_validate_returns_true_when_table_exists(
        self, mock_pool, mock_conn, workspace_id
    ):
        """Returns True when raw_retrosheet.events table exists."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[True])
        mock_conn.execute.return_value = mock_result

        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)
        result = await ingester.validate()

        assert result is True

    @pytest.mark.asyncio
    async def test_validate_returns_false_when_table_missing(
        self, mock_pool, mock_conn, workspace_id
    ):
        """Returns False when raw_retrosheet.events table does not exist."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[False])
        mock_conn.execute.return_value = mock_result

        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)
        result = await ingester.validate()

        assert result is False


# ---------------------------------------------------------------------------
# RetrosheetIngester.ingest Tests
# ---------------------------------------------------------------------------


class TestRetrosheetIngesterIngest:
    """Tests for RetrosheetIngester.ingest method."""

    @pytest.mark.asyncio
    async def test_ingest_creates_ingest_run(self, mock_pool, mock_conn, workspace_id):
        """Ingestion creates an ingest run record."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        # Mock for source_endpoint_id
        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_events", new_callable=AsyncMock
        ) as mock_ingest_events:
            mock_ingest_events.return_value = IngestResult(
                rows_processed=100, rows_inserted=100
            )
            result = await ingester.ingest()

        assert result.rows_processed == 100
        assert result.rows_inserted == 100

    @pytest.mark.asyncio
    async def test_ingest_with_specific_year(self, mock_pool, mock_conn, workspace_id):
        """Ingestion with year parameter calls _ingest_events."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_events", new_callable=AsyncMock
        ) as mock_ingest_events:
            mock_ingest_events.return_value = IngestResult(
                rows_processed=50, rows_inserted=50
            )
            result = await ingester.ingest(year=2023)

        mock_ingest_events.assert_called_once()

    @pytest.mark.asyncio
    async def test_ingest_with_data_type_all(self, mock_pool, mock_conn, workspace_id):
        """Ingestion with data_type='all' calls _ingest_all."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_all", new_callable=AsyncMock
        ) as mock_ingest_all:
            mock_ingest_all.return_value = IngestResult(
                rows_processed=200, rows_inserted=200
            )
            result = await ingester.ingest(data_type="all")

        mock_ingest_all.assert_called_once()

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

        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_events", side_effect=ValueError("Test error")
        ):
            result = await ingester.ingest()

        assert result.errors == 1


# ---------------------------------------------------------------------------
# RetrosheetIngester._ingest_single_event_file Tests
# ---------------------------------------------------------------------------


class TestIngestSingleEventFile:
    """Tests for RetrosheetIngester._ingest_single_event_file method."""

    @pytest.mark.asyncio
    async def test_ingest_single_event_file_processes_records(
        self, mock_pool, mock_conn, workspace_id
    ):
        """Processes event file records correctly."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)

        # Mock Chadwick
        mock_chadwick = MagicMock()
        mock_chadwick.games.return_value = []

        result = await ingester._ingest_single_event_file(
            Path("/fake/path.EVN"), uuid.UUID("12345678-1234-5678-1234-567812345678"), mock_chadwick
        )

        assert result.rows_processed == 0

    @pytest.mark.asyncio
    async def test_ingest_events_handles_missing_directory(
        self, mock_pool, workspace_id
    ):
        """Returns empty result when events directory does not exist."""
        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)
        result = await ingester._ingest_events(2023, uuid.UUID("12345678-1234-5678-1234-567812345678"))
        assert result.rows_processed == 0
        assert result.errors == 1  # pychadwick not installed error
