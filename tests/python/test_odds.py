"""Tests for baseball/ingestion/odds.py.

Covers OddsIngester class and betting odds data ingestion.
"""

from __future__ import annotations

from datetime import date
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch
import uuid

import pytest

from baseball.ingestion.odds import OddsIngester
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
# OddsIngester.__init__ Tests
# ---------------------------------------------------------------------------


class TestOddsIngesterInit:
    """Tests for OddsIngester initialization."""

    def test_default_data_dir(self, mock_pool, workspace_id):
        """Default data_dir is set correctly."""
        ingester = OddsIngester(pool=mock_pool, workspace_id=workspace_id)
        assert ingester.data_dir == Path("data/odds")

    def test_custom_data_dir(self, mock_pool, workspace_id):
        """Custom data_dir can be provided."""
        custom_dir = Path("/custom/data")
        ingester = OddsIngester(
            pool=mock_pool, workspace_id=workspace_id, data_dir=custom_dir
        )
        assert ingester.data_dir == custom_dir

    def test_source_code_is_odds(self, mock_pool, workspace_id):
        """Source code is set to 'odds'."""
        ingester = OddsIngester(pool=mock_pool, workspace_id=workspace_id)
        assert ingester.source_code == "odds"

    def test_api_key_from_constructor(self, mock_pool, workspace_id):
        """API key is set from constructor."""
        ingester = OddsIngester(pool=mock_pool, workspace_id=workspace_id, api_key="test-api-key")
        assert ingester.api_key == "test-api-key"

    def test_api_key_defaults_to_none(self, mock_pool, workspace_id):
        """API key defaults to None when not provided."""
        ingester = OddsIngester(pool=mock_pool, workspace_id=workspace_id)
        assert ingester.api_key is None


# ---------------------------------------------------------------------------
# OddsIngester.validate Tests
# ---------------------------------------------------------------------------


class TestOddsIngesterValidate:
    """Tests for OddsIngester.validate method."""

    @pytest.mark.asyncio
    async def test_validate_returns_true_when_table_exists(self, mock_pool, mock_conn, workspace_id):
        """Returns True when raw_odds.market_lines table exists."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.acquire.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[True])
        mock_conn.execute.return_value = mock_result

        ingester = OddsIngester(pool=mock_pool, workspace_id=workspace_id)
        result = await ingester.validate()

        assert result is True

    @pytest.mark.asyncio
    async def test_validate_returns_false_when_table_missing(self, mock_pool, mock_conn, workspace_id):
        """Returns False when raw_odds.market_lines table does not exist."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.acquire.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[False])
        mock_conn.execute.return_value = mock_result

        ingester = OddsIngester(pool=mock_pool, workspace_id=workspace_id)
        result = await ingester.validate()

        assert result is False


# ---------------------------------------------------------------------------
# OddsIngester.ingest Tests
# ---------------------------------------------------------------------------


class TestOddsIngesterIngest:
    """Tests for OddsIngester.ingest method."""

    @pytest.mark.asyncio
    async def test_ingest_creates_ingest_run(self, mock_pool, mock_conn, workspace_id):
        """Ingestion creates an ingest run record."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.acquire.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = OddsIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(ingester, "_ingest_all", new_callable=AsyncMock) as mock_ingest_all:
            mock_ingest_all.return_value = IngestResult(rows_processed=100, rows_inserted=100)
            result = await ingester.ingest()

        assert result.rows_processed == 100
        assert result.rows_inserted == 100

    @pytest.mark.asyncio
    async def test_ingest_with_date(self, mock_pool, mock_conn, workspace_id):
        """Ingestion with date_val calls _ingest_date."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.acquire.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = OddsIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(ingester, "_ingest_date", new_callable=AsyncMock) as mock_date:
            mock_date.return_value = IngestResult(rows_processed=50, rows_inserted=50)
            result = await ingester.ingest(date_val=date(2023, 4, 15))

        mock_date.assert_called_once()

    @pytest.mark.asyncio
    async def test_ingest_with_season(self, mock_pool, mock_conn, workspace_id):
        """Ingestion with season calls _ingest_season."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.acquire.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = OddsIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(ingester, "_ingest_season", new_callable=AsyncMock) as mock_season:
            mock_season.return_value = IngestResult(rows_processed=500, rows_inserted=500)
            result = await ingester.ingest(season=2023)

        mock_season.assert_called_once()

    @pytest.mark.asyncio
    async def test_ingest_marks_failed_on_exception(self, mock_pool, mock_conn, workspace_id):
        """Ingestion marks run as failed when exception occurs."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.acquire.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = OddsIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(ingester, "_ingest_all", side_effect=ValueError("Test error")):
            result = await ingester.ingest()

        assert result.errors == 1


# ---------------------------------------------------------------------------
# OddsIngester._ingest_date Tests
# ---------------------------------------------------------------------------


class TestIngestDate:
    """Tests for OddsIngester._ingest_date method."""

    @pytest.mark.asyncio
    async def test_ingest_date_fetches_odds(self, mock_pool, mock_conn, workspace_id):
        """_ingest_date fetches odds data for a specific date."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.acquire.return_value = mock_acquire_ctx

        ingester = OddsIngester(pool=mock_pool, workspace_id=workspace_id, api_key="test-key")

        with patch("baseball.ingestion.odds.HistoricalLoaderFactory.fetch_api_json_stream") as mock_fetch:
            mock_fetch.return_value = [
                {"id": "1", "sport": "baseball", "commence_time": "2023-04-15T19:00Z"}
            ]
            result = await ingester._ingest_date(
                date(2023, 4, 15),
                "baseball",
                uuid.UUID("12345678-1234-5678-1234-567812345678"),
            )

        assert result.rows_processed == 1

    @pytest.mark.asyncio
    async def test_ingest_date_handles_empty_response(self, mock_pool, workspace_id):
        """_ingest_date handles empty API response gracefully."""
        ingester = OddsIngester(pool=mock_pool, workspace_id=workspace_id, api_key="test-key")

        with patch("baseball.ingestion.odds.HistoricalLoaderFactory.fetch_api_json_stream") as mock_fetch:
            mock_fetch.return_value = []
            result = await ingester._ingest_date(
                date(2023, 4, 15),
                "baseball",
                uuid.UUID("12345678-1234-5678-1234-567812345678"),
            )

        assert result.rows_processed == 0


# ---------------------------------------------------------------------------
# OddsIngester._ingest_season Tests
# ---------------------------------------------------------------------------


class TestIngestSeason:
    """Tests for OddsIngester._ingest_season method."""

    @pytest.mark.asyncio
    async def test_ingest_season_calls_ingest_date_for_each_day(self, mock_pool, workspace_id):
        """_ingest_season calls _ingest_date for each day in season."""
        ingester = OddsIngester(pool=mock_pool, workspace_id=workspace_id, api_key="test-key")

        with patch.object(ingester, "_ingest_date", new_callable=AsyncMock) as mock_date:
            mock_date.return_value = IngestResult(rows_processed=10, rows_inserted=10)
            result = await ingester._ingest_season(
                2023,
                "baseball",
                uuid.UUID("12345678-1234-5678-1234-567812345678"),
            )

        # Should have called _ingest_date for each day
        assert mock_date.call_count > 0


# ---------------------------------------------------------------------------
# OddsIngester._ingest_all Tests
# ---------------------------------------------------------------------------


class TestIngestAll:
    """Tests for OddsIngester._ingest_all method."""

    @pytest.mark.asyncio
    async def test_ingest_all_calls_ingest_date(self, mock_pool, workspace_id):
        """_ingest_all calls _ingest_date for current date."""
        ingester = OddsIngester(pool=mock_pool, workspace_id=workspace_id, api_key="test-key")

        with patch.object(ingester, "_ingest_date", new_callable=AsyncMock) as mock_date:
            mock_date.return_value = IngestResult(rows_processed=100, rows_inserted=100)
            result = await ingester._ingest_all(
                "baseball",
                uuid.UUID("12345678-1234-5678-1234-567812345678"),
            )

        mock_date.assert_called_once()