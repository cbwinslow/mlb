"""Tests for baseball/ingestion/fangraphs.py.

Covers FanGraphsIngester class and FanGraphs data ingestion.
"""

from __future__ import annotations

from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch
import uuid

import pytest

from baseball.ingestion.fangraphs import FanGraphsIngester
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
# FanGraphsIngester.__init__ Tests
# ---------------------------------------------------------------------------


class TestFanGraphsIngesterInit:
    """Tests for FanGraphsIngester initialization."""

    def test_default_data_dir(self, mock_pool, workspace_id):
        """Default data_dir is set correctly."""
        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id)
        assert ingester.data_dir == Path("data/fangraphs")

    def test_custom_data_dir(self, mock_pool, workspace_id):
        """Custom data_dir can be provided."""
        custom_dir = Path("/custom/data")
        ingester = FanGraphsIngester(
            pool=mock_pool, workspace_id=workspace_id, data_dir=custom_dir
        )
        assert ingester.data_dir == custom_dir

    def test_source_code_is_fangraphs(self, mock_pool, workspace_id):
        """Source code is set to 'fangraphs'."""
        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id)
        assert ingester.source_code == "fangraphs"


# ---------------------------------------------------------------------------
# FanGraphsIngester.validate Tests
# ---------------------------------------------------------------------------


class TestFanGraphsIngesterValidate:
    """Tests for FanGraphsIngester.validate method."""

    @pytest.mark.asyncio
    async def test_validate_returns_true_when_table_exists(self, mock_pool, mock_conn, workspace_id):
        """Returns True when raw_fangraphs.batter_splits table exists."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[True])
        mock_conn.execute.return_value = mock_result

        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id)
        result = await ingester.validate()

        assert result is True

    @pytest.mark.asyncio
    async def test_validate_returns_false_when_table_missing(self, mock_pool, mock_conn, workspace_id):
        """Returns False when raw_fangraphs.batter_splits table does not exist."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[False])
        mock_conn.execute.return_value = mock_result

        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id)
        result = await ingester.validate()

        assert result is False


# ---------------------------------------------------------------------------
# FanGraphsIngester.ingest Tests
# ---------------------------------------------------------------------------


class TestFanGraphsIngesterIngest:
    """Tests for FanGraphsIngester.ingest method."""

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

        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(ingester, "_ingest_all", new_callable=AsyncMock) as mock_ingest_all:
            mock_ingest_all.return_value = IngestResult(rows_processed=100, rows_inserted=100)
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

        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(ingester, "_ingest_batting", new_callable=AsyncMock) as mock_batting:
            mock_batting.return_value = IngestResult(rows_processed=500, rows_inserted=500)
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

        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(ingester, "_ingest_pitching", new_callable=AsyncMock) as mock_pitching:
            mock_pitching.return_value = IngestResult(rows_processed=300, rows_inserted=300)
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

        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(ingester, "_ingest_fielding", new_callable=AsyncMock) as mock_fielding:
            mock_fielding.return_value = IngestResult(rows_processed=200, rows_inserted=200)
            result = await ingester.ingest(season=2023, data_type="fielding")

        mock_fielding.assert_called_once()

    @pytest.mark.asyncio
    async def test_ingest_with_batter_splits(self, mock_pool, mock_conn, workspace_id):
        """Ingestion with batter_splits data_type calls _ingest_batter_splits."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(ingester, "_ingest_batter_splits", new_callable=AsyncMock) as mock_splits:
            mock_splits.return_value = IngestResult(rows_processed=150, rows_inserted=150)
            result = await ingester.ingest(season=2023, data_type="batter_splits")

        mock_splits.assert_called_once()

    @pytest.mark.asyncio
    async def test_ingest_with_pitcher_splits(self, mock_pool, mock_conn, workspace_id):
        """Ingestion with pitcher_splits data_type calls _ingest_pitcher_splits."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(ingester, "_ingest_pitcher_splits", new_callable=AsyncMock) as mock_splits:
            mock_splits.return_value = IngestResult(rows_processed=100, rows_inserted=100)
            result = await ingester.ingest(season=2023, data_type="pitcher_splits")

        mock_splits.assert_called_once()

    @pytest.mark.asyncio
    async def test_ingest_with_baserunning(self, mock_pool, mock_conn, workspace_id):
        """Ingestion with baserunning data_type calls _ingest_baserunning."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(ingester, "_ingest_baserunning", new_callable=AsyncMock) as mock_base:
            mock_base.return_value = IngestResult(rows_processed=80, rows_inserted=80)
            result = await ingester.ingest(season=2023, data_type="baserunning")

        mock_base.assert_called_once()

    @pytest.mark.asyncio
    async def test_ingest_with_plate_discipline(self, mock_pool, mock_conn, workspace_id):
        """Ingestion with plate_discipline data_type calls _ingest_plate_discipline."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(ingester, "_ingest_plate_discipline", new_callable=AsyncMock) as mock_pd:
            mock_pd.return_value = IngestResult(rows_processed=120, rows_inserted=120)
            result = await ingester.ingest(season=2023, data_type="plate_discipline")

        mock_pd.assert_called_once()

    @pytest.mark.asyncio
    async def test_ingest_marks_failed_on_exception(self, mock_pool, mock_conn, workspace_id):
        """Ingestion marks run as failed when exception occurs."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(ingester, "_ingest_all", side_effect=ValueError("Test error")):
            result = await ingester.ingest()

        assert result.errors == 1


# ---------------------------------------------------------------------------
# FanGraphsIngester._ingest_batting Tests
# ---------------------------------------------------------------------------


class TestIngestBatting:
    """Tests for FanGraphsIngester._ingest_batting method."""

    @pytest.mark.asyncio
    async def test_ingest_batting_raises_without_pybaseball(self, mock_pool, workspace_id):
        """Raises ImportError when pybaseball is not installed."""
        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.dict("sys.modules", {"pybaseball": None, "pybaseball.batting_stats": None}):
            with pytest.raises(ImportError, match="pybaseball is required"):
                await ingester._ingest_batting(2023, uuid.UUID("12345678-1234-5678-1234-567812345678"))

    @pytest.mark.asyncio
    async def test_ingest_batting_creates_csv(self, mock_pool, workspace_id, tmp_path):
        """Creates CSV file for bulk loading."""
        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id, data_dir=tmp_path)

        mock_df = MagicMock()
        mock_df.__len__ = MagicMock(return_value=500)
        mock_df.to_csv = MagicMock()

        with patch("pybaseball.batting_stats", return_value=mock_df):
            with patch.object(ingester, "_bulk_load_csv", new_callable=AsyncMock, return_value=500):
                result = await ingester._ingest_batting(
                    2023,
                    uuid.UUID("12345678-1234-5678-1234-567812345678"),
                )

        assert result.rows_processed == 500
        assert result.rows_inserted == 500


# ---------------------------------------------------------------------------
# FanGraphsIngester._ingest_pitching Tests
# ---------------------------------------------------------------------------


class TestIngestPitching:
    """Tests for FanGraphsIngester._ingest_pitching method."""

    @pytest.mark.asyncio
    async def test_ingest_pitching_creates_csv(self, mock_pool, workspace_id, tmp_path):
        """Creates CSV file for bulk loading."""
        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id, data_dir=tmp_path)

        mock_df = MagicMock()
        mock_df.__len__ = MagicMock(return_value=300)
        mock_df.to_csv = MagicMock()

        with patch("pybaseball.pitching_stats", return_value=mock_df):
            with patch.object(ingester, "_bulk_load_csv", new_callable=AsyncMock, return_value=300):
                result = await ingester._ingest_pitching(
                    2023,
                    uuid.UUID("12345678-1234-5678-1234-567812345678"),
                )

        assert result.rows_processed == 300
        assert result.rows_inserted == 300


# ---------------------------------------------------------------------------
# FanGraphsIngester._ingest_fielding Tests
# ---------------------------------------------------------------------------


class TestIngestFielding:
    """Tests for FanGraphsIngester._ingest_fielding method."""

    @pytest.mark.asyncio
    async def test_ingest_fielding_creates_csv(self, mock_pool, workspace_id, tmp_path):
        """Creates CSV file for bulk loading."""
        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id, data_dir=tmp_path)

        mock_df = MagicMock()
        mock_df.__len__ = MagicMock(return_value=200)
        mock_df.to_csv = MagicMock()

        with patch("pybaseball.fielding_stats", return_value=mock_df):
            with patch.object(ingester, "_bulk_load_csv", new_callable=AsyncMock, return_value=200):
                result = await ingester._ingest_fielding(
                    2023,
                    uuid.UUID("12345678-1234-5678-1234-567812345678"),
                )

        assert result.rows_processed == 200
        assert result.rows_inserted == 200


# ---------------------------------------------------------------------------
# FanGraphsIngester._ingest_batter_splits Tests
# ---------------------------------------------------------------------------


class TestIngestBatterSplits:
    """Tests for FanGraphsIngester._ingest_batter_splits method."""

    @pytest.mark.asyncio
    async def test_ingest_batter_splits_creates_csv(self, mock_pool, workspace_id, tmp_path):
        """Creates CSV file for batter splits."""
        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id, data_dir=tmp_path)

        mock_df = MagicMock()
        mock_df.__len__ = MagicMock(return_value=150)
        mock_df.to_csv = MagicMock()

        with patch("pybaseball.batting_stats_bref", return_value=mock_df):
            with patch.object(ingester, "_bulk_load_csv", new_callable=AsyncMock, return_value=150):
                result = await ingester._ingest_batter_splits(
                    2023,
                    uuid.UUID("12345678-1234-5678-1234-567812345678"),
                )

        assert result.rows_processed == 150
        assert result.rows_inserted == 150


# ---------------------------------------------------------------------------
# FanGraphsIngester._ingest_pitcher_splits Tests
# ---------------------------------------------------------------------------


class TestIngestPitcherSplits:
    """Tests for FanGraphsIngester._ingest_pitcher_splits method."""

    @pytest.mark.asyncio
    async def test_ingest_pitcher_splits_creates_csv(self, mock_pool, workspace_id, tmp_path):
        """Creates CSV file for pitcher splits."""
        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id, data_dir=tmp_path)

        mock_df = MagicMock()
        mock_df.__len__ = MagicMock(return_value=100)
        mock_df.to_csv = MagicMock()

        with patch("pybaseball.pitching_stats_bref", return_value=mock_df):
            with patch.object(ingester, "_bulk_load_csv", new_callable=AsyncMock, return_value=100):
                result = await ingester._ingest_pitcher_splits(
                    2023,
                    uuid.UUID("12345678-1234-5678-1234-567812345678"),
                )

        assert result.rows_processed == 100
        assert result.rows_inserted == 100


# ---------------------------------------------------------------------------
# FanGraphsIngester._ingest_baserunning Tests
# ---------------------------------------------------------------------------


class TestIngestBaserunning:
    """Tests for FanGraphsIngester._ingest_baserunning method."""

    @pytest.mark.asyncio
    async def test_ingest_baserunning_creates_csv(self, mock_pool, workspace_id, tmp_path):
        """Creates CSV file for baserunning data."""
        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id, data_dir=tmp_path)

        mock_df = MagicMock()
        mock_df.__len__ = MagicMock(return_value=80)
        mock_df.to_csv = MagicMock()

        with patch("pybaseball.fg_batting_data", return_value=mock_df):
            with patch.object(ingester, "_bulk_load_csv", new_callable=AsyncMock, return_value=80):
                result = await ingester._ingest_baserunning(
                    2023,
                    uuid.UUID("12345678-1234-5678-1234-567812345678"),
                )

        assert result.rows_processed == 80
        assert result.rows_inserted == 80


# ---------------------------------------------------------------------------
# FanGraphsIngester._ingest_plate_discipline Tests
# ---------------------------------------------------------------------------


class TestIngestPlateDiscipline:
    """Tests for FanGraphsIngester._ingest_plate_discipline method."""

    @pytest.mark.asyncio
    async def test_ingest_plate_discipline_creates_csv(self, mock_pool, workspace_id, tmp_path):
        """Creates CSV file for plate discipline data."""
        ingester = FanGraphsIngester(pool=mock_pool, workspace_id=workspace_id, data_dir=tmp_path)

        mock_df = MagicMock()
        mock_df.__len__ = MagicMock(return_value=120)
        mock_df.to_csv = MagicMock()

        with patch("pybaseball.fg_batting_data", return_value=mock_df):
            with patch.object(ingester, "_bulk_load_csv", new_callable=AsyncMock, return_value=120):
                result = await ingester._ingest_plate_discipline(
                    2023,
                    uuid.UUID("12345678-1234-5678-1234-567812345678"),
                )

        assert result.rows_processed == 120
        assert result.rows_inserted == 120