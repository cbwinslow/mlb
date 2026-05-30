"""Tests for baseball/ingestion/mlbam.py.

Covers MLBAMIngester class and MLB StatsAPI data ingestion.
"""

from __future__ import annotations

from datetime import date
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch
import uuid

import pytest

from baseball.ingestion.mlbam import MLBAMIngester
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
# MLBAMIngester.__init__ Tests
# ---------------------------------------------------------------------------


class TestMLBAMIngesterInit:
    """Tests for MLBAMIngester initialization."""

    def test_default_data_dir(self, mock_pool, workspace_id):
        """Default data_dir is set correctly."""
        ingester = MLBAMIngester(pool=mock_pool, workspace_id=workspace_id)
        assert ingester.data_dir == Path("data/mlbapi")

    def test_custom_data_dir(self, mock_pool, workspace_id):
        """Custom data_dir can be provided."""
        custom_dir = Path("/custom/data")
        ingester = MLBAMIngester(
            pool=mock_pool, workspace_id=workspace_id, data_dir=custom_dir
        )
        assert ingester.data_dir == custom_dir

    def test_source_code_is_mlbapi(self, mock_pool, workspace_id):
        """Source code is set to 'mlbapi'."""
        ingester = MLBAMIngester(pool=mock_pool, workspace_id=workspace_id)
        assert ingester.source_code == "mlbapi"

    def test_base_url_is_set(self, mock_pool, workspace_id):
        """BASE_URL is set correctly."""
        ingester = MLBAMIngester(pool=mock_pool, workspace_id=workspace_id)
        assert ingester.BASE_URL == "https://statsapi.mlb.com/api/v1"


# ---------------------------------------------------------------------------
# MLBAMIngester.validate Tests
# ---------------------------------------------------------------------------


class TestMLBAMIngesterValidate:
    """Tests for MLBAMIngester.validate method."""

    @pytest.mark.asyncio
    async def test_validate_returns_true_when_table_exists(
        self, mock_pool, mock_conn, workspace_id
    ):
        """Returns True when raw_mlbapi.payload table exists."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[True])
        mock_conn.execute.return_value = mock_result

        ingester = MLBAMIngester(pool=mock_pool, workspace_id=workspace_id)
        result = await ingester.validate()

        assert result is True

    @pytest.mark.asyncio
    async def test_validate_returns_false_when_table_missing(
        self, mock_pool, mock_conn, workspace_id
    ):
        """Returns False when raw_mlbapi.payload table does not exist."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[False])
        mock_conn.execute.return_value = mock_result

        ingester = MLBAMIngester(pool=mock_pool, workspace_id=workspace_id)
        result = await ingester.validate()

        assert result is False


# ---------------------------------------------------------------------------
# MLBAMIngester.ingest Tests
# ---------------------------------------------------------------------------


class TestMLBAMIngesterIngest:
    """Tests for MLBAMIngester.ingest method."""

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

        ingester = MLBAMIngester(pool=mock_pool, workspace_id=workspace_id)

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
    async def test_ingest_with_schedule_endpoint(
        self, mock_pool, mock_conn, workspace_id
    ):
        """Ingestion with schedule endpoint calls _ingest_schedule."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = MLBAMIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_schedule", new_callable=AsyncMock
        ) as mock_schedule:
            mock_schedule.return_value = IngestResult(
                rows_processed=50, rows_inserted=50
            )
            result = await ingester.ingest(
                endpoint="schedule", date_val=date(2023, 4, 15)
            )

        mock_schedule.assert_called_once()

    @pytest.mark.asyncio
    async def test_ingest_with_teams_endpoint(self, mock_pool, mock_conn, workspace_id):
        """Ingestion with teams endpoint calls _ingest_teams."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = MLBAMIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_teams", new_callable=AsyncMock
        ) as mock_teams:
            mock_teams.return_value = IngestResult(rows_processed=30, rows_inserted=30)
            result = await ingester.ingest(endpoint="teams")

        mock_teams.assert_called_once()

    @pytest.mark.asyncio
    async def test_ingest_with_people_endpoint(
        self, mock_pool, mock_conn, workspace_id
    ):
        """Ingestion with people endpoint calls _ingest_people."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = MLBAMIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_people", new_callable=AsyncMock
        ) as mock_people:
            mock_people.return_value = IngestResult(
                rows_processed=1000, rows_inserted=1000
            )
            result = await ingester.ingest(endpoint="people")

        mock_people.assert_called_once()

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

        ingester = MLBAMIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_all", side_effect=ValueError("Test error")
        ):
            result = await ingester.ingest()

        assert result.errors == 1


# ---------------------------------------------------------------------------
# MLBAMIngester._ingest_schedule Tests
# ---------------------------------------------------------------------------


class TestIngestSchedule:
    """Tests for MLBAMIngester._ingest_schedule method."""

    @pytest.mark.asyncio
    async def test_ingest_schedule_fetches_data(
        self, mock_pool, mock_conn, workspace_id
    ):
        """_ingest_schedule fetches and inserts schedule data."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = MLBAMIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch(
            "baseball.ingestion.mlbam.HistoricalLoaderFactory.fetch_api_json_stream"
        ) as mock_fetch:
            mock_fetch.return_value = {
                "dates": [{"games": [{"gamePk": 1, "gameType": "R"}]}]
            }
            result = await ingester._ingest_schedule(
                date(2023, 4, 15),
                uuid.UUID("12345678-1234-5678-1234-567812345678"),
            )

        assert result.rows_processed == 1


# ---------------------------------------------------------------------------
# MLBAMIngester._ingest_teams Tests
# ---------------------------------------------------------------------------


class TestIngestTeams:
    """Tests for MLBAMIngester._ingest_teams method."""

    @pytest.mark.asyncio
    async def test_ingest_teams_fetches_data(self, mock_pool, mock_conn, workspace_id):
        """_ingest_teams fetches and inserts team data."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = MLBAMIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch(
            "baseball.ingestion.mlbam.HistoricalLoaderFactory.fetch_api_json_stream"
        ) as mock_fetch:
            mock_fetch.return_value = {
                "teams": [{"id": 1, "name": "Angels", "abbreviation": "LAA"}]
            }
            result = await ingester._ingest_teams(
                uuid.UUID("12345678-1234-5678-1234-567812345678"),
            )

        assert result.rows_processed == 1


# ---------------------------------------------------------------------------
# MLBAMIngester._ingest_people Tests
# ---------------------------------------------------------------------------


class TestIngestPeople:
    """Tests for MLBAMIngester._ingest_people method."""

    @pytest.mark.asyncio
    async def test_ingest_people_fetches_data(self, mock_pool, mock_conn, workspace_id):
        """_ingest_people fetches and inserts people data."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = MLBAMIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch(
            "baseball.ingestion.mlbam.HistoricalLoaderFactory.fetch_paginated_json"
        ) as mock_fetch:
            mock_fetch.return_value = [{"id": 1, "fullName": "Mike Trout"}]
            result = await ingester._ingest_people(
                uuid.UUID("12345678-1234-5678-1234-567812345678"),
            )

        assert result.rows_processed == 1
