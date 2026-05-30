"""Tests for baseball/ingestion/bref.py.

Covers BRefIngester class and Baseball Reference data ingestion.
"""

from __future__ import annotations

from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch
import uuid

import pytest

from baseball.ingestion.bref import BRefIngester
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
# BRefIngester.__init__ Tests
# ---------------------------------------------------------------------------


class TestBRefIngesterInit:
    """Tests for BRefIngester initialization."""

    def test_default_data_dir(self, mock_pool, workspace_id):
        """Default data_dir is set correctly."""
        ingester = BRefIngester(pool=mock_pool, workspace_id=workspace_id)
        assert ingester.data_dir == Path("data/bref")

    def test_custom_data_dir(self, mock_pool, workspace_id):
        """Custom data_dir can be provided."""
        custom_dir = Path("/custom/data")
        ingester = BRefIngester(
            pool=mock_pool, workspace_id=workspace_id, data_dir=custom_dir
        )
        assert ingester.data_dir == custom_dir

    def test_source_code_is_bref(self, mock_pool, workspace_id):
        """Source code is set to 'bref'."""
        ingester = BRefIngester(pool=mock_pool, workspace_id=workspace_id)
        assert ingester.source_code == "bref"


# ---------------------------------------------------------------------------
# BRefIngester.validate Tests
# ---------------------------------------------------------------------------


class TestBRefIngesterValidate:
    """Tests for BRefIngester.validate method."""

    @pytest.mark.asyncio
    async def test_validate_returns_true_when_table_exists(
        self, mock_pool, mock_conn, workspace_id
    ):
        """Returns True when raw_bref.batting table exists."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[True])
        mock_conn.execute.return_value = mock_result

        ingester = BRefIngester(pool=mock_pool, workspace_id=workspace_id)
        result = await ingester.validate()

        assert result is True

    @pytest.mark.asyncio
    async def test_validate_returns_false_when_table_missing(
        self, mock_pool, mock_conn, workspace_id
    ):
        """Returns False when raw_bref.batting table does not exist."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[False])
        mock_conn.execute.return_value = mock_result

        ingester = BRefIngester(pool=mock_pool, workspace_id=workspace_id)
        result = await ingester.validate()

        assert result is False


# ---------------------------------------------------------------------------
# BRefIngester.ingest Tests
# ---------------------------------------------------------------------------


class TestBRefIngesterIngest:
    """Tests for BRefIngester.ingest method."""

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

        ingester = BRefIngester(pool=mock_pool, workspace_id=workspace_id)

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
    async def test_ingest_with_batting(self, mock_pool, mock_conn, workspace_id):
        """Ingestion with batting data_type calls _ingest_batting."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = BRefIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_batting", new_callable=AsyncMock
        ) as mock_batting:
            mock_batting.return_value = IngestResult(
                rows_processed=500, rows_inserted=500
            )
            result = await ingester.ingest(season=2023, data_type="batting")

        mock_batting.assert_called_once()

    @pytest.mark.asyncio
    async def test_ingest_with_pitching(self, mock_pool, mock_conn, workspace_id):
        """Ingestion with pitching data_type calls _ingest_pitching."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = BRefIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_pitching", new_callable=AsyncMock
        ) as mock_pitching:
            mock_pitching.return_value = IngestResult(
                rows_processed=300, rows_inserted=300
            )
            result = await ingester.ingest(season=2023, data_type="pitching")

        mock_pitching.assert_called_once()

    @pytest.mark.asyncio
    async def test_ingest_with_fielding(self, mock_pool, mock_conn, workspace_id):
        """Ingestion with fielding data_type calls _ingest_fielding."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = BRefIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_fielding", new_callable=AsyncMock
        ) as mock_fielding:
            mock_fielding.return_value = IngestResult(
                rows_processed=200, rows_inserted=200
            )
            result = await ingester.ingest(season=2023, data_type="fielding")

        mock_fielding.assert_called_once()

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

        ingester = BRefIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_schedule", new_callable=AsyncMock
        ) as mock_schedule:
            mock_schedule.return_value = IngestResult(
                rows_processed=162, rows_inserted=162
            )
            result = await ingester.ingest(season=2023, data_type="schedule")

        mock_schedule.assert_called_once()

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

        ingester = BRefIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(
            ingester, "_ingest_all", side_effect=ValueError("Test error")
        ):
            result = await ingester.ingest()

        assert result.errors == 1


# ---------------------------------------------------------------------------
# BRefIngester._ingest_batting Tests
# ---------------------------------------------------------------------------


class TestIngestBatting:
    """Tests for BRefIngester._ingest_batting method."""

    @pytest.mark.asyncio
    async def test_ingest_batting_raises_without_pybaseball(
        self, mock_pool, workspace_id
    ):
        """Raises ImportError when pybaseball is not installed."""
        ingester = BRefIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.dict(
            "sys.modules", {"pybaseball": None, "pybaseball.batting_stats_bref": None}
        ):
            with pytest.raises(ImportError, match="pybaseball is required"):
                await ingester._ingest_batting(
                    2023, uuid.UUID("12345678-1234-5678-1234-567812345678")
                )

    @pytest.mark.asyncio
    async def test_ingest_batting_creates_csv(self, mock_pool, workspace_id, tmp_path):
        """Creates CSV file for bulk loading."""
        ingester = BRefIngester(
            pool=mock_pool, workspace_id=workspace_id, data_dir=tmp_path
        )

        mock_df = MagicMock()
        mock_df.__len__ = MagicMock(return_value=500)
        mock_df.to_csv = MagicMock()

        with patch("pybaseball.batting_stats_bref", return_value=mock_df):
            with patch.object(
                ingester, "_bulk_load_csv", new_callable=AsyncMock, return_value=500
            ):
                result = await ingester._ingest_batting(
                    2023,
                    uuid.UUID("12345678-1234-5678-1234-567812345678"),
                )

        assert result.rows_processed == 500
        assert result.rows_inserted == 500


# ---------------------------------------------------------------------------
# BRefIngester._ingest_pitching Tests
# ---------------------------------------------------------------------------


class TestIngestPitching:
    """Tests for BRefIngester._ingest_pitching method."""

    @pytest.mark.asyncio
    async def test_ingest_pitching_creates_csv(self, mock_pool, workspace_id, tmp_path):
        """Creates CSV file for bulk loading."""
        ingester = BRefIngester(
            pool=mock_pool, workspace_id=workspace_id, data_dir=tmp_path
        )

        mock_df = MagicMock()
        mock_df.__len__ = MagicMock(return_value=300)
        mock_df.to_csv = MagicMock()

        with patch("pybaseball.pitching_stats_bref", return_value=mock_df):
            with patch.object(
                ingester, "_bulk_load_csv", new_callable=AsyncMock, return_value=300
            ):
                result = await ingester._ingest_pitching(
                    2023,
                    uuid.UUID("12345678-1234-5678-1234-567812345678"),
                )

        assert result.rows_processed == 300
        assert result.rows_inserted == 300


# ---------------------------------------------------------------------------
# BRefIngester._ingest_fielding Tests
# ---------------------------------------------------------------------------


class TestIngestFielding:
    """Tests for BRefIngester._ingest_fielding method."""

    @pytest.mark.asyncio
    async def test_ingest_fielding_creates_csv(self, mock_pool, workspace_id, tmp_path):
        """Creates CSV file for bulk loading."""
        ingester = BRefIngester(
            pool=mock_pool, workspace_id=workspace_id, data_dir=tmp_path
        )

        mock_df = MagicMock()
        mock_df.__len__ = MagicMock(return_value=200)
        mock_df.to_csv = MagicMock()

        with patch("pybaseball.fielding_stats", return_value=mock_df):
            with patch.object(
                ingester, "_bulk_load_csv", new_callable=AsyncMock, return_value=200
            ):
                result = await ingester._ingest_fielding(
                    2023,
                    uuid.UUID("12345678-1234-5678-1234-567812345678"),
                )

        assert result.rows_processed == 200
        assert result.rows_inserted == 200


# ---------------------------------------------------------------------------
# BRefIngester._ingest_schedule Tests
# ---------------------------------------------------------------------------


class TestIngestSchedule:
    """Tests for BRefIngester._ingest_schedule method."""

    @pytest.mark.asyncio
    async def test_ingest_schedule_raises_without_pybaseball(
        self, mock_pool, workspace_id
    ):
        """Raises ImportError when pybaseball is not installed."""
        ingester = BRefIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.dict(
            "sys.modules", {"pybaseball": None, "pybaseball.schedule_and_record": None}
        ):
            with pytest.raises(ImportError, match="pybaseball is required"):
                await ingester._ingest_schedule(
                    2023, uuid.UUID("12345678-1234-5678-1234-567812345678")
                )

    @pytest.mark.asyncio
    async def test_ingest_schedule_creates_csv(self, mock_pool, workspace_id, tmp_path):
        """Creates CSV file for schedule data."""
        ingester = BRefIngester(
            pool=mock_pool, workspace_id=workspace_id, data_dir=tmp_path
        )

        mock_df = MagicMock()
        mock_df.__len__ = MagicMock(return_value=162)
        mock_df.to_csv = MagicMock()

        with patch("pybaseball.schedule_and_record", return_value=mock_df):
            with patch.object(
                ingester, "_bulk_load_csv", new_callable=AsyncMock, return_value=162
            ):
                result = await ingester._ingest_schedule(
                    2023,
                    uuid.UUID("12345678-1234-5678-1234-567812345678"),
                )

        assert result.rows_processed == 162
        assert result.rows_inserted == 162
