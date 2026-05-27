"""Tests for baseball/ingestion/retrosheet.py.

Covers RetrosheetIngester class and Retrosheet event file parsing.
"""

from __future__ import annotations

import gzip
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
    async def test_validate_returns_true_when_table_exists(self, mock_pool, mock_conn, workspace_id):
        """Returns True when raw_retrosheet.record table exists."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.acquire.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[True])
        mock_conn.execute.return_value = mock_result

        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)
        result = await ingester.validate()

        assert result is True

    @pytest.mark.asyncio
    async def test_validate_returns_false_when_table_missing(self, mock_pool, mock_conn, workspace_id):
        """Returns False when raw_retrosheet.record table does not exist."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.acquire.return_value = mock_acquire_ctx

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
        mock_pool.acquire.return_value = mock_acquire_ctx

        # Mock for source_endpoint_id
        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(ingester, "_ingest_all", new_callable=AsyncMock) as mock_ingest_all:
            mock_ingest_all.return_value = IngestResult(rows_processed=100, rows_inserted=100)
            result = await ingester.ingest()

        assert result.rows_processed == 100
        assert result.rows_inserted == 100

    @pytest.mark.asyncio
    async def test_ingest_with_specific_year(self, mock_pool, mock_conn, workspace_id):
        """Ingestion with year parameter calls _ingest_year."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.acquire.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(ingester, "_ingest_year", new_callable=AsyncMock) as mock_ingest_year:
            mock_ingest_year.return_value = IngestResult(rows_processed=50, rows_inserted=50)
            result = await ingester.ingest(year=2023)

        mock_ingest_year.assert_called_once()

    @pytest.mark.asyncio
    async def test_ingest_with_specific_file(self, mock_pool, mock_conn, workspace_id):
        """Ingestion with file_path parameter calls _ingest_single_file."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.acquire.return_value = mock_acquire_ctx

        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(return_value=[1])
        mock_conn.execute.return_value = mock_result

        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)

        with tempfile.NamedTemporaryFile(mode="w", suffix=".EVN", delete=False) as f:
            f.write("id,ANA202304050\n")
            f.write("info,key,value\n")
            temp_path = Path(f.name)

        with patch.object(ingester, "_ingest_single_file", new_callable=AsyncMock) as mock_single:
            mock_single.return_value = IngestResult(rows_processed=10, rows_inserted=10)
            result = await ingester.ingest(file_path=temp_path)

        mock_single.assert_called_once()

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

        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)

        with patch.object(ingester, "_ingest_all", side_effect=ValueError("Test error")):
            result = await ingester.ingest()

        assert result.errors == 1


# ---------------------------------------------------------------------------
# RetrosheetIngester._parse_event_file Tests
# ---------------------------------------------------------------------------


class TestParseEventFile:
    """Tests for RetrosheetIngester._parse_event_file method."""

    def test_parse_id_record(self, mock_pool, workspace_id):
        """Parses id record correctly."""
        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)

        with tempfile.NamedTemporaryFile(mode="w", suffix=".EVN", delete=False) as f:
            f.write("id,ANA202304050\n")
            f.write("info,venue,Angel Stadium\n")
            temp_path = Path(f.name)

        records = ingester._parse_event_file(temp_path)

        assert len(records) == 2
        assert records[0]["record_type"] == "id"
        assert records[0]["game_id"] == "ANA202304050"
        assert records[1]["record_type"] == "info"

    def test_parse_gzipped_file(self, mock_pool, workspace_id):
        """Parses gzipped event file correctly."""
        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)

        temp_path = Path(tempfile.mktemp(suffix=".EVN.gz"))
        with gzip.open(temp_path, "wt", encoding="utf-8") as gz:
            gz.write("id,ANA202304050\n")
            gz.write("start,1,2,3,4,5,6,7,8,9\n")

        records = ingester._parse_event_file(temp_path)

        assert len(records) == 2
        assert records[0]["record_type"] == "id"
        assert records[1]["record_type"] == "start"

    def test_parse_ignores_empty_lines(self, mock_pool, workspace_id):
        """Empty lines are ignored."""
        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)

        temp_path = Path(tempfile.mktemp(suffix=".EVN"))
        with open(temp_path, "w") as f:
            f.write("id,ANA202304050\n")
            f.write("\n")
            f.write("info,venue,Angel Stadium\n")

        records = ingester._parse_event_file(temp_path)

        assert len(records) == 2

    def test_parse_ignores_unknown_record_types(self, mock_pool, workspace_id):
        """Unknown record types are ignored."""
        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)

        temp_path = Path(tempfile.mktemp(suffix=".EVN"))
        with open(temp_path, "w") as f:
            f.write("id,ANA202304050\n")
            f.write("unknown,data,here\n")

        records = ingester._parse_event_file(temp_path)

        assert len(records) == 1
        assert records[0]["record_type"] == "id"


# ---------------------------------------------------------------------------
# RetrosheetIngester._extract_game_id Tests
# ---------------------------------------------------------------------------


class TestExtractGameId:
    """Tests for RetrosheetIngester._extract_game_id method."""

    def test_extract_game_id_from_id_record(self, mock_pool, workspace_id):
        """Extracts game ID from id record."""
        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)

        game_id = ingester._extract_game_id("id,ANA202304050", "id")
        assert game_id == "ANA202304050"

    def test_extract_game_id_returns_none_for_non_id_record(self, mock_pool, workspace_id):
        """Returns None for non-id record types."""
        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)

        game_id = ingester._extract_game_id("info,venue,Angel Stadium", "info")
        assert game_id is None

    def test_extract_game_id_handles_malformed_id_record(self, mock_pool, workspace_id):
        """Handles malformed id record gracefully."""
        ingester = RetrosheetIngester(pool=mock_pool, workspace_id=workspace_id)

        game_id = ingester._extract_game_id("id", "id")
        assert game_id is None