"""Tests for baseball/ingestion/statcast.py.

Covers StatcastIngester class and Statcast data ingestion.
"""

from __future__ import annotations

import tempfile
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch
import uuid

import pytest
import pandas as pd

from baseball.ingestion.statcast import StatcastIngester
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


@pytest.fixture
def sample_statcast_df():
    """Create a sample DataFrame matching pybaseball statcast output."""
    return pd.DataFrame({
        "pitch_type": ["FF", "SL", "CH"],
        "game_date": ["2024-04-01", "2024-04-01", "2024-04-01"],
        "game_year": [2024, 2024, 2024],
        "game_pk": [123456, 123456, 123456],
        "at_bat_number": [1, 2, 3],
        "pitch_number": [1, 1, 1],
        "batter": [12345, 12345, 12346],
        "pitcher": [54321, 54321, 54321],
        "events": ["field_out", "strikeout", "single"],
        "description": ["hit_into_play", "swinging_strike", "hit_into_play"],
        "type": ["X", "S", "X"],
        "release_speed": [95.5, 88.2, 92.1],
        "release_spin_rate": [2200, 2400, 2100],
        "pfx_x": [-4.5, -2.1, -3.2],
        "pfx_z": [12.5, 8.9, 10.1],
        "plate_x": [0.5, -1.2, 0.8],
        "plate_z": [2.8, 3.5, 2.2],
        "inning": [1, 1, 2],
        "inning_topbot": ["Top", "Top", "Bottom"],
        "outs_when_up": [0, 1, 1],
        "balls": [1, 0, 2],
        "strikes": [1, 2, 1],
        "home_team": ["NYY", "NYY", "NYY"],
        "away_team": ["BOS", "BOS", "BOS"],
    })


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
    async def test_ingest_season_creates_ingest_run(
        self, mock_pool, mock_conn, workspace_id
    ):
        """Ingestion creates an ingest run record."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        # Mock source_endpoint_id lookup
        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        with patch.object(
            StatcastIngester, "_ingest_season", new_callable=AsyncMock
        ) as mock_ingest_season:
            mock_ingest_season.return_value = 100

            ingester = StatcastIngester(pool=mock_pool, workspace_id=workspace_id)
            result = await ingester.ingest(season=2024)

            assert result.rows_inserted == 100

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

        with patch.object(
            StatcastIngester, "_ingest_range", new_callable=AsyncMock
        ) as mock_ingest_range:
            mock_ingest_range.return_value = 150

            ingester = StatcastIngester(pool=mock_pool, workspace_id=workspace_id)
            result = await ingester.ingest(
                start_date=pd.Timestamp("2024-04-01").date(),
                end_date=pd.Timestamp("2024-04-02").date(),
            )

            assert result.rows_inserted == 150

    @pytest.mark.asyncio
    async def test_ingest_raises_error_without_dates(
        self, mock_pool, workspace_id
    ):
        """Ingestion returns error count without dates or season."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=AsyncMock())
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        ingester = StatcastIngester(pool=mock_pool, workspace_id=workspace_id)
        result = await ingester.ingest()

        # Error is caught and returned as error count
        assert result.errors >= 1


# ---------------------------------------------------------------------------
# StatcastIngester._ingest_range Tests
# ---------------------------------------------------------------------------


class TestIngestRange:
    """Tests for StatcastIngester._ingest_range method."""

    @pytest.mark.asyncio
    async def test_ingest_range_handles_empty_dataframe(
        self, mock_pool, mock_conn, workspace_id, tmp_path
    ):
        """Ingestion handles empty DataFrame."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        # Empty df
        empty_df = pd.DataFrame()

        with patch(
            "pybaseball.statcast", return_value=empty_df
        ):
            ingester = StatcastIngester(
                pool=mock_pool, workspace_id=workspace_id, data_dir=tmp_path
            )

            rows = await ingester._ingest_range(
                pd.Timestamp("2024-04-01").date(),
                pd.Timestamp("2024-04-02").date(),
                uuid.UUID("12345678-1234-5678-1234-567812345678"),
            )

            assert rows == 0


# ---------------------------------------------------------------------------
# StatcastIngester._process_to_core Tests
# ---------------------------------------------------------------------------


class TestProcessToCore:
    """Tests for StatcastIngester._process_to_core method."""

    @pytest.mark.asyncio
    async def test_process_to_core_handles_empty(
        self, mock_pool, mock_conn, workspace_id
    ):
        """Returns 0 when no rows to process."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchall = AsyncMock(return_value=[])
        mock_conn.execute.return_value = mock_result
        mock_conn.commit = AsyncMock()

        ingester = StatcastIngester(pool=mock_pool, workspace_id=workspace_id)
        processed = await ingester._process_to_core(
            uuid.UUID("12345678-1234-5678-1234-567812345678")
        )

        assert processed == 0