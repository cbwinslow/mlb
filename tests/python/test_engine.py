"""Tests for baseball/ingestion/engine.py.

Covers IngestEngine class and its async methods.
"""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from baseball.ingestion.engine import IngestEngine


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def mock_pool():
    """Create a mock AsyncConnectionPool."""
    pool = MagicMock()
    pool.acquire = MagicMock(return_value=AsyncMock())
    return pool


@pytest.fixture
def ingest_engine(mock_pool):
    """Create an IngestEngine instance with mock pool."""
    return IngestEngine(pool=mock_pool)


# ---------------------------------------------------------------------------
# IngestEngine.__init__ Tests
# ---------------------------------------------------------------------------


class TestIngestEngineInit:
    """Tests for IngestEngine initialization."""

    def test_pool_is_assigned(self, mock_pool):
        """Pool is assigned to instance."""
        engine = IngestEngine(pool=mock_pool)
        assert engine.pool is mock_pool

    def test_pool_can_be_none(self):
        """Pool can be None (for testing)."""
        engine = IngestEngine(pool=None)
        assert engine.pool is None


# ---------------------------------------------------------------------------
# _get_pk_column Tests
# ---------------------------------------------------------------------------


class TestGetPkColumn:
    """Tests for _get_pk_column() method."""

    def test_raw_mlbapi_returns_correct_pk(self, ingest_engine):
        """Returns correct PK for raw_mlbapi tables."""
        assert ingest_engine._get_pk_column("raw_mlbapi.payload") == "mlbapi_payload_id"

    def test_raw_statcast_returns_correct_pk(self, ingest_engine):
        """Returns correct PK for raw_statcast tables."""
        assert ingest_engine._get_pk_column("raw_statcast.pitch") == "statcast_pitch_id"

    def test_raw_fangraphs_returns_correct_pk(self, ingest_engine):
        """Returns correct PK for raw_fangraphs tables."""
        assert ingest_engine._get_pk_column("raw_fangraphs.batter_splits") == "raw_fangraphs_payload_id"

    def test_raw_bref_returns_correct_pk(self, ingest_engine):
        """Returns correct PK for raw_bref tables."""
        assert ingest_engine._get_pk_column("raw_bref.page") == "raw_bref_page_id"

    def test_raw_espn_returns_correct_pk(self, ingest_engine):
        """Returns correct PK for raw_espn tables."""
        assert ingest_engine._get_pk_column("raw_espn.schedule") == "raw_espn_page_id"

    def test_raw_odds_returns_correct_pk(self, ingest_engine):
        """Returns correct PK for raw_odds tables."""
        assert ingest_engine._get_pk_column("raw_odds.market_lines") == "raw_odds_provider_payload_id"

    def test_unknown_schema_returns_default(self, ingest_engine):
        """Unknown schema returns 'id' as default."""
        assert ingest_engine._get_pk_column("unknown.table") == "id"


# ---------------------------------------------------------------------------
# bulk_load_raw_csv Tests
# ---------------------------------------------------------------------------


class TestBulkLoadRawCsv:
    """Tests for bulk_load_raw_csv() async method."""

    @pytest.mark.asyncio
    async def test_generates_correct_copy_sql(self, ingest_engine, mock_pool):
        """COPY SQL is generated correctly."""
        mock_conn = AsyncMock()
        mock_cursor = AsyncMock()
        # In psycopg async, conn.cursor() returns a cursor object directly (not a context manager)
        # The cursor has async methods like copy_expert
        mock_conn.cursor = MagicMock(return_value=mock_cursor)
        mock_pool.connection.return_value.__aenter__.return_value = mock_conn
        mock_conn.execute = AsyncMock(return_value=AsyncMock(fetchone=lambda: [100]))
        mock_conn.commit = AsyncMock()

        # Create temp CSV file
        import tempfile
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            f.write("col1,col2\nval1,val2\n")
            temp_path = Path(f.name)

        try:
            result = await ingest_engine.bulk_load_raw_csv(
                table_name="raw_statcast.pitch",
                file_path=temp_path,
            )
            # Verify copy_expert was called with COPY command
            assert mock_cursor.copy_expert.called
            sql_arg = mock_cursor.copy_expert.call_args[0][0]
            assert "COPY raw_statcast.pitch" in sql_arg
            assert "FORMAT csv" in sql_arg
            assert "HEADER true" in sql_arg
        finally:
            temp_path.unlink()

    @pytest.mark.asyncio
    async def test_handles_column_list(self, ingest_engine, mock_pool):
        """Column list is included in COPY when provided."""
        mock_conn = AsyncMock()
        mock_cursor = AsyncMock()
        mock_conn.cursor = MagicMock(return_value=mock_cursor)
        mock_pool.connection.return_value.__aenter__.return_value = mock_conn
        mock_conn.execute = AsyncMock(return_value=AsyncMock(fetchone=lambda: [50]))
        mock_conn.commit = AsyncMock()

        import tempfile
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            f.write("col1,col2\nval1,val2\n")
            temp_path = Path(f.name)

        try:
            result = await ingest_engine.bulk_load_raw_csv(
                table_name="raw_statcast.pitch",
                file_path=temp_path,
                columns=["col1", "col2"],
            )
            sql_arg = mock_cursor.copy_expert.call_args[0][0]
            assert "(col1, col2)" in sql_arg
        finally:
            temp_path.unlink()


# ---------------------------------------------------------------------------
# ingest_raw_jsonb Tests
# ---------------------------------------------------------------------------


class TestIngestRawJsonb:
    """Tests for ingest_raw_jsonb() async method."""

    @pytest.mark.asyncio
    async def test_inserts_json_with_ingest_run_id(self, ingest_engine, mock_pool):
        """JSON is inserted with ingest_run_id."""
        mock_conn = AsyncMock()
        mock_pool.connection.return_value.__aenter__.return_value = mock_conn
        mock_conn.execute = AsyncMock(return_value=AsyncMock(fetchone=lambda: [1]))
        mock_conn.commit = AsyncMock()

        json_data = {"test": "data", "nested": {"key": "value"}}
        result = await ingest_engine.ingest_raw_jsonb(
            table_name="raw_mlbapi.payload",
            json_data=json_data,
            ingest_run_id="test-run-123",
        )

        assert mock_conn.execute.called
        sql_arg = mock_conn.execute.call_args[0][0]
        assert "INSERT INTO raw_mlbapi.payload" in sql_arg
        assert "response_json" in sql_arg
        assert "ingest_run_id" in sql_arg

    @pytest.mark.asyncio
    async def test_handles_extra_columns(self, ingest_engine, mock_pool):
        """Extra columns are included in insert."""
        mock_conn = AsyncMock()
        mock_pool.connection.return_value.__aenter__.return_value = mock_conn
        mock_conn.execute = AsyncMock(return_value=AsyncMock(fetchone=lambda: [1]))
        mock_conn.commit = AsyncMock()

        result = await ingest_engine.ingest_raw_jsonb(
            table_name="raw_mlbapi.payload",
            json_data={"test": "data"},
            extra_column="test_value",
        )

        sql_arg = mock_conn.execute.call_args[0][0]
        assert "extra_column" in sql_arg


# ---------------------------------------------------------------------------
# upsert_player_identity Tests
# ---------------------------------------------------------------------------


class TestUpsertPlayerIdentity:
    """Tests for upsert_player_identity() async method."""

    @pytest.mark.asyncio
    async def test_inserts_new_player(self, ingest_engine, mock_pool):
        """New player identity is inserted."""
        mock_conn = AsyncMock()
        mock_pool.connection.return_value.__aenter__.return_value = mock_conn
        mock_conn.execute = AsyncMock(return_value=AsyncMock(fetchone=lambda: [42]))
        mock_conn.commit = AsyncMock()

        result = await ingest_engine.upsert_player_identity(
            mlbam_player_id=592450,
            full_name="Juan Soto",
            identity_source="test",
        )

        assert result == 42
        sql_arg = mock_conn.execute.call_args[0][0]
        assert "INSERT INTO stg.player_identity" in sql_arg
        assert "ON CONFLICT" in sql_arg

    @pytest.mark.asyncio
    async def test_handles_null_mlbam(self, ingest_engine, mock_pool):
        """NULL MLBAM ID is handled correctly."""
        mock_conn = AsyncMock()
        mock_pool.connection.return_value.__aenter__.return_value = mock_conn
        mock_conn.execute = AsyncMock(return_value=AsyncMock(fetchone=lambda: [1]))
        mock_conn.commit = AsyncMock()

        result = await ingest_engine.upsert_player_identity(
            mlbam_player_id=None,
            full_name="Historical Player",
        )

        assert result == 1


# ---------------------------------------------------------------------------
# record_ingest_run Tests
# ---------------------------------------------------------------------------


class TestRecordIngestRun:
    """Tests for record_ingest_run() async method."""

    @pytest.mark.asyncio
    async def test_creates_ingest_run(self, ingest_engine, mock_pool):
        """Ingest run record is created."""
        mock_conn = AsyncMock()
        mock_pool.connection.return_value.__aenter__.return_value = mock_conn
        mock_conn.execute = AsyncMock(return_value=AsyncMock(fetchone=lambda: ["run-uuid-123"]))
        mock_conn.commit = AsyncMock()

        result = await ingest_engine.record_ingest_run(
            source_endpoint_id=1,
            status="running",
        )

        assert result == "run-uuid-123"
        sql_arg = mock_conn.execute.call_args[0][0]
        assert "INSERT INTO meta.ingest_run" in sql_arg

    @pytest.mark.asyncio
    async def test_handles_error_message(self, ingest_engine, mock_pool):
        """Error message is stored when provided."""
        mock_conn = AsyncMock()
        mock_pool.connection.return_value.__aenter__.return_value = mock_conn
        mock_conn.execute = AsyncMock(return_value=AsyncMock(fetchone=lambda: ["run-uuid"]))
        mock_conn.commit = AsyncMock()

        await ingest_engine.record_ingest_run(
            source_endpoint_id=1,
            status="failed",
            error_message="Connection failed",
        )

        sql_arg = mock_conn.execute.call_args[0][0]
        assert "error_message" in sql_arg


# ---------------------------------------------------------------------------
# complete_ingest_run Tests
# ---------------------------------------------------------------------------


class TestCompleteIngestRun:
    """Tests for complete_ingest_run() async method."""

    @pytest.mark.asyncio
    async def test_marks_completed(self, ingest_engine, mock_pool):
        """Ingest run is marked completed."""
        mock_conn = AsyncMock()
        mock_pool.connection.return_value.__aenter__.return_value = mock_conn
        mock_conn.execute = AsyncMock()
        mock_conn.commit = AsyncMock()

        await ingest_engine.complete_ingest_run(
            ingest_run_id="run-uuid-123",
            status="succeeded",
        )

        sql_arg = mock_conn.execute.call_args[0][0]
        assert "UPDATE meta.ingest_run" in sql_arg
        assert "finished_at" in sql_arg

    @pytest.mark.asyncio
    async def test_marks_failed_with_error(self, ingest_engine, mock_pool):
        """Ingest run is marked failed with error message."""
        mock_conn = AsyncMock()
        mock_pool.connection.return_value.__aenter__.return_value = mock_conn
        mock_conn.execute = AsyncMock()
        mock_conn.commit = AsyncMock()

        await ingest_engine.complete_ingest_run(
            ingest_run_id="run-uuid-123",
            status="failed",
            error_message="Test error",
        )

        sql_arg = mock_conn.execute.call_args[0][0]
        assert "run_status" in sql_arg
        assert "error_message" in sql_arg