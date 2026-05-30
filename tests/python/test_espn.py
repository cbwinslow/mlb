"""Tests for baseball/ingestion/espn.py.

Covers ESPNIngester class and ESPN data ingestion.
"""

from __future__ import annotations

from datetime import date
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch
import uuid

import pytest

from baseball.ingestion.espn import ESPNIngester
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
# ESPNIngester.__init__ Tests
# ---------------------------------------------------------------------------


class TestESPNIngesterInit:
    """Tests for ESPNIngester initialization."""

    def test_default_data_dir(self, mock_pool, workspace_id):
        """Default data_dir is set correctly."""
        ingester = ESPNIngester(pool=mock_pool, workspace_id=workspace_id)
        assert ingester.data_dir == Path("data/espn")

    def test_custom_data_dir(self, mock_pool, workspace_id):
        """Custom data_dir can be provided."""
        custom_dir = Path("/custom/data")
        ingester = ESPNIngester(
            pool=mock_pool, workspace_id=workspace_id, data_dir=custom_dir
        )
        assert ingester.data_dir == custom_dir

    def test_source_code_is_espn(self, mock_pool, workspace_id):
        """Source code is set to 'espn'."""
        ingester = ESPNIngester(pool=mock_pool, workspace_id=workspace_id)
        assert ingester.source_code == "espn"

    def test_base_url_is_set(self, mock_pool, workspace_id):
        """BASE_URL is set correctly."""
        ingester = ESPNIngester(pool=mock_pool, workspace_id=workspace_id)
        assert (
            ingester.BASE_URL
            == "https://site.api.espn.com/apis/site/v2/sports/baseball/mlb"
        )


# ---------------------------------------------------------------------------
# ESPNIngester.validate Tests
# ---------------------------------------------------------------------------


class TestESPNIngesterValidate:
    """Tests for ESPNIngester.validate method."""

    @pytest.mark.asyncio
    async def test_validate_returns_true_when_table_exists(
        self, mock_pool, mock_conn, workspace_id
    ):
        """Returns True when raw_espn.schedule table exists."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[True])
        mock_conn.execute.return_value = mock_result

        ingester = ESPNIngester(pool=mock_pool, workspace_id=workspace_id)
        result = await ingester.validate()

        assert result is True

    @pytest.mark.asyncio
    async def test_validate_returns_false_when_table_missing(
        self, mock_pool, mock_conn, workspace_id
    ):
        """Returns False when raw_espn.schedule table does not exist."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[False])
        mock_conn.execute.return_value = mock_result

        ingester = ESPNIngester(pool=mock_pool, workspace_id=workspace_id)
        result = await ingester.validate()

        assert result is False


# ---------------------------------------------------------------------------
# ESPNIngester.ingest Tests
# ---------------------------------------------------------------------------


class TestESPNIngesterIngest:
    """Tests for ESPNIngester.ingest method."""

    @pytest.mark.asyncio
    async def test_ingest_creates_ingest_run(self, mock_pool, mock_conn, workspace_id):
        """Ingestion creates an ingest run record."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = ESPNIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_all", new_callable=AsyncMock
        ) as mock_ingest_all:
            mock_ingest_all.return_value = IngestResult(
                rows_processed=100, rows_inserted=100
            )
            result = await ingester.ingest()

        assert result.rows_processed == 100
        assert result.rows_inserted == 100

    @pytest.mark.asyncio
    async def test_ingest_with_schedule(self, mock_pool, mock_conn, workspace_id):
        """Ingestion with schedule data_type calls _ingest_schedule."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = ESPNIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_schedule", new_callable=AsyncMock
        ) as mock_schedule:
            mock_schedule.return_value = IngestResult(
                rows_processed=30, rows_inserted=30
            )
            result = await ingester.ingest(season=2023, data_type="schedule")

        mock_schedule.assert_called_once()

    @pytest.mark.asyncio
    async def test_ingest_with_scores(self, mock_pool, mock_conn, workspace_id):
        """Ingestion with scores data_type calls _ingest_scores."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = ESPNIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_scores", new_callable=AsyncMock
        ) as mock_scores:
            mock_scores.return_value = IngestResult(rows_processed=15, rows_inserted=15)
            result = await ingester.ingest(
                date_val=date(2023, 4, 15), data_type="scores"
            )

        mock_scores.assert_called_once()

    @pytest.mark.asyncio
    async def test_ingest_with_standings(self, mock_pool, mock_conn, workspace_id):
        """Ingestion with standings data_type calls _ingest_standings."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = ESPNIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_standings", new_callable=AsyncMock
        ) as mock_standings:
            mock_standings.return_value = IngestResult(
                rows_processed=1, rows_inserted=1
            )
            result = await ingester.ingest(season=2023, data_type="standings")

        mock_standings.assert_called_once()

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

        ingester = ESPNIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_all", side_effect=ValueError("Test error")
        ):
            result = await ingester.ingest()

        assert result.errors == 1


# ---------------------------------------------------------------------------
# ESPNIngester._ingest_schedule Tests
# ---------------------------------------------------------------------------


class TestIngestSchedule:
    """Tests for ESPNIngester._ingest_schedule method."""

    @pytest.mark.asyncio
    async def test_ingest_schedule_fetches_teams(
        self, mock_pool, mock_conn, workspace_id
    ):
        """_ingest_schedule fetches teams and inserts schedule data."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = ESPNIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch(
            "baseball.ingestion.espn.HistoricalLoaderFactory.fetch_api_json_stream"
        ) as mock_fetch:
            mock_fetch.return_value = {
                "teams": [{"id": 1, "name": "Angels", "schedule": {"games": []}}]
            }
            result = await ingester._ingest_schedule(
                2023,
                uuid.UUID("12345678-1234-5678-1234-567812345678"),
            )

        assert result.rows_processed == 1


# ---------------------------------------------------------------------------
# ESPNIngester._ingest_scores Tests
# ---------------------------------------------------------------------------


class TestIngestScores:
    """Tests for ESPNIngester._ingest_scores method."""

    @pytest.mark.asyncio
    async def test_ingest_scores_fetches_events(
        self, mock_pool, mock_conn, workspace_id
    ):
        """_ingest_scores fetches events and inserts score data."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = ESPNIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch(
            "baseball.ingestion.espn.HistoricalLoaderFactory.fetch_api_json_stream"
        ) as mock_fetch:
            mock_fetch.return_value = {"events": [{"id": "1", "competitions": []}]}
            result = await ingester._ingest_scores(
                date(2023, 4, 15),
                uuid.UUID("12345678-1234-5678-1234-567812345678"),
            )

        assert result.rows_processed == 1


# ---------------------------------------------------------------------------
# ESPNIngester._ingest_standings Tests
# ---------------------------------------------------------------------------


class TestIngestStandings:
    """Tests for ESPNIngester._ingest_standings method."""

    @pytest.mark.asyncio
    async def test_ingest_standings_fetches_data(
        self, mock_pool, mock_conn, workspace_id
    ):
        """_ingest_standings fetches and inserts standings data."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = ESPNIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch(
            "baseball.ingestion.espn.HistoricalLoaderFactory.fetch_api_json_stream"
        ) as mock_fetch:
            mock_fetch.return_value = {"standings": {"groups": []}}
            result = await ingester._ingest_standings(
                2023,
                uuid.UUID("12345678-1234-5678-1234-567812345678"),
            )

        assert result.rows_processed == 1
