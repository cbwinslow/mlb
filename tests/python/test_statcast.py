"""Tests for baseball/ingestion/statcast.py.

Covers StatcastIngester class and Statcast data ingestion.
"""

from __future__ import annotations

from datetime import date
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch
import uuid
from unittest import mock

import pytest

from baseball.ingestion.statcast import StatcastIngester
from baseball.ingestion.base import IngestResult


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def mock_pool():
    """Create a mock AsyncConnectionPool."""
    pool = MagicMock()
    pool.acquire = MagicMock()
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
# StatcastIngester.__init__ Tests
# ---------------------------------------------------------------------------


class TestStatcastIngesterInit:
    """Tests for StatcastIngester initialization."""

    def test_default_data_dir(self, mock_pool, workspace_id):
        """Default data_dir is set correctly."""
        ingester = StatcastIngester(pool=mock_pool, workspace_id=workspace_id)
        assert ingester.data_dir == Path("data/statcast")

    def test_custom_data_dir(self, mock_pool, workspace_id):
        """Custom data_dir can be provided."""
        custom_dir = Path("/custom/data")
        ingester = StatcastIngester(
            pool=mock_pool, workspace_id=workspace_id, data_dir=custom_dir
        )
        assert ingester.data_dir == custom_dir

    def test_source_code_is_statcast(self, mock_pool, workspace_id):
        """Source code is set to 'statcast'."""
        ingester = StatcastIngester(pool=mock_pool, workspace_id=workspace_id)
        assert ingester.source_code == "statcast"

    def test_engine_is_initialized(self, mock_pool, workspace_id):
        """IngestEngine is initialized."""
        ingester = StatcastIngester(pool=mock_pool, workspace_id=workspace_id)
        assert ingester.engine is not None


# ---------------------------------------------------------------------------
# StatcastIngester.validate Tests
# ---------------------------------------------------------------------------


class TestStatcastIngesterValidate:
    """Tests for StatcastIngester.validate method."""

    @pytest.mark.asyncio
    async def test_validate_returns_true_when_table_exists(
        self, mock_pool, mock_conn, workspace_id
    ):
        """Returns True when raw_statcast.pitch table exists."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[True])
        mock_conn.execute.return_value = mock_result

        ingester = StatcastIngester(pool=mock_pool, workspace_id=workspace_id)
        result = await ingester.validate()

        assert result is True

    @pytest.mark.asyncio
    async def test_validate_returns_false_when_table_missing(
        self, mock_pool, mock_conn, workspace_id
    ):
        """Returns False when raw_statcast.pitch table does not exist."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[False])
        mock_conn.execute.return_value = mock_result

        ingester = StatcastIngester(pool=mock_pool, workspace_id=workspace_id)
        result = await ingester.validate()

        assert result is False


# ---------------------------------------------------------------------------
# StatcastIngester.ingest Tests
# ---------------------------------------------------------------------------


class TestStatcastIngesterIngest:
    """Tests for StatcastIngester.ingest method."""

    @pytest.mark.asyncio
    async def test_ingest_with_season(self, mock_pool, mock_conn, workspace_id):
        """Ingestion with season parameter calls _ingest_season."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = StatcastIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_season", new_callable=AsyncMock
        ) as mock_season:
            mock_season.return_value = IngestResult(
                rows_processed=1000, rows_inserted=1000
            )
            result = await ingester.ingest(season=2023)

        mock_season.assert_called_once()

    @pytest.mark.asyncio
    async def test_ingest_with_date_range(self, mock_pool, mock_conn, workspace_id):
        """Ingestion with date range calls _ingest_range."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = StatcastIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_range", new_callable=AsyncMock
        ) as mock_range:
            mock_range.return_value = IngestResult(
                rows_processed=500, rows_inserted=500
            )
            result = await ingester.ingest(
                start_date=date(2023, 4, 1),
                end_date=date(2023, 4, 30),
            )

        mock_range.assert_called_once()

    @pytest.mark.asyncio
    async def test_ingest_raises_without_params(
        self, mock_pool, mock_conn, workspace_id
    ):
        """Ingestion returns error result when called without season or date range."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_conn

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = StatcastIngester(pool=mock_pool, workspace_id=workspace_id)
        result = await ingester.ingest()

        assert result.errors == 1

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

        ingester = StatcastIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_season", side_effect=ValueError("Test error")
        ):
            result = await ingester.ingest(season=2023)

        assert result.errors == 1


# ---------------------------------------------------------------------------
# StatcastIngester._ingest_season Tests
# ---------------------------------------------------------------------------


class TestIngestSeason:
    """Tests for StatcastIngester._ingest_season method."""

    @pytest.mark.asyncio
    async def test_ingest_season_calls_ingest_range(self, mock_pool, workspace_id):
        """_ingest_season calls _ingest_range with correct dates."""
        ingester = StatcastIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_range", new_callable=AsyncMock
        ) as mock_range:
            mock_range.return_value = IngestResult(
                rows_processed=1000, rows_inserted=1000
            )
            await ingester._ingest_season(
                2023, uuid.UUID("12345678-1234-5678-1234-567812345678")
            )

        mock_range.assert_called_once()
        call_args = mock_range.call_args
        assert call_args[0][0] == date(2023, 3, 1)  # March 1
        assert call_args[0][1] == date(2023, 10, 31)  # October 31


# ---------------------------------------------------------------------------
# StatcastIngester._ingest_range Tests
# ---------------------------------------------------------------------------


class TestIngestRange:
    """Tests for StatcastIngester._ingest_range method."""

    @pytest.mark.asyncio
    async def test_ingest_range_raises_without_pybaseball(
        self, mock_pool, workspace_id
    ):
        """Raises ImportError when pybaseball is not installed."""
        ingester = StatcastIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.dict(
            "sys.modules", {"pybaseball": None, "pybaseball.statcast": None}
        ):
            with pytest.raises(ImportError, match="pybaseball is required"):
                await ingester._ingest_range(
                    date(2023, 4, 1),
                    date(2023, 4, 30),
                    uuid.UUID("12345678-1234-5678-1234-567812345678"),
                )

    @pytest.mark.asyncio
    async def test_ingest_range_creates_csv(self, mock_pool, workspace_id, tmp_path):
        """Creates CSV file for bulk loading."""
        ingester = StatcastIngester(
            pool=mock_pool, workspace_id=workspace_id, data_dir=tmp_path
        )

        mock_df = MagicMock()
        mock_df.__len__ = MagicMock(return_value=100)
        mock_df.to_csv = MagicMock()

        with patch("pybaseball.statcast", return_value=mock_df):
            with patch.object(
                ingester.engine,
                "bulk_load_raw_csv",
                new_callable=AsyncMock,
                return_value=100,
            ):
                result = await ingester._ingest_range(
                    date(2023, 4, 1),
                    date(2023, 4, 30),
                    uuid.UUID("12345678-1234-5678-1234-567812345678"),
                )

        assert result.rows_processed == 100
        assert result.rows_inserted == 100
