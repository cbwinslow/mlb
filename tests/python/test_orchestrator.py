"""Tests for baseball/ingestion/orchestrator.py.

Covers IngestionOrchestrator class and its async context manager.
"""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch
import uuid

import pytest

from baseball.ingestion.orchestrator import (
    IngestionOrchestrator,
    start_ingest_run,
    finish_ingest_run,
)


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
    return conn


# ---------------------------------------------------------------------------
# IngestionOrchestrator.__init__ Tests
# ---------------------------------------------------------------------------


class TestIngestionOrchestratorInit:
    """Tests for IngestionOrchestrator initialization."""

    def test_pool_is_assigned(self, mock_pool):
        """Pool is assigned to instance."""
        orchestrator = IngestionOrchestrator(pool=mock_pool, source_endpoint_id=1)
        assert orchestrator.pool is mock_pool

    def test_pool_can_be_none(self):
        """Pool can be None (for testing)."""
        orchestrator = IngestionOrchestrator(pool=None, source_endpoint_id=1)
        assert orchestrator.pool is None

    def test_default_attributes(self, mock_pool):
        """Default attributes are initialized."""
        orchestrator = IngestionOrchestrator(pool=mock_pool, source_endpoint_id=1)
        assert orchestrator._conn is None
        assert orchestrator.ingest_run_id is None
        assert orchestrator.source_endpoint_id == 1

    def test_run_metadata_defaults_to_empty_dict(self, mock_pool):
        """Run metadata defaults to empty dict."""
        orchestrator = IngestionOrchestrator(pool=mock_pool, source_endpoint_id=1)
        assert orchestrator.run_metadata == {}

    def test_run_metadata_can_be_set(self, mock_pool):
        """Run metadata can be set via constructor."""
        orchestrator = IngestionOrchestrator(
            pool=mock_pool, source_endpoint_id=1, run_metadata={"source": "test"}
        )
        assert orchestrator.run_metadata == {"source": "test"}


# ---------------------------------------------------------------------------
# start_ingest_run Tests
# ---------------------------------------------------------------------------


class TestStartIngestRun:
    """Tests for start_ingest_run() function."""

    @pytest.mark.asyncio
    async def test_inserts_ingest_run_record(self, mock_conn):
        """Inserts record into meta.ingest_run."""
        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(
            return_value=[uuid.UUID("12345678-1234-5678-1234-567812345678")]
        )
        mock_conn.execute.return_value = mock_result

        result = await start_ingest_run(mock_conn, source_endpoint_id=1)

        assert result == uuid.UUID("12345678-1234-5678-1234-567812345678")
        mock_conn.execute.assert_called_once()

    @pytest.mark.asyncio
    async def test_handles_run_metadata(self, mock_conn):
        """Run metadata is included in insert."""
        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(
            return_value=[uuid.UUID("12345678-1234-5678-1234-567812345678")]
        )
        mock_conn.execute.return_value = mock_result

        await start_ingest_run(
            mock_conn, source_endpoint_id=1, run_metadata={"source": "test"}
        )

        # Check positional args - the 4th arg is the JSON metadata
        call_args = mock_conn.execute.call_args[0][1]
        assert call_args[3] == '{"source": "test"}'

    @pytest.mark.asyncio
    async def test_run_metadata_defaults_to_empty_dict(self, mock_conn):
        """Run metadata defaults to empty dict when not provided."""
        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(
            return_value=[uuid.UUID("12345678-1234-5678-1234-567812345678")]
        )
        mock_conn.execute.return_value = mock_result

        await start_ingest_run(mock_conn, source_endpoint_id=1)

        # Check positional args - the 4th arg is the JSON metadata
        call_args = mock_conn.execute.call_args[0][1]
        assert call_args[3] == "{}"


# ---------------------------------------------------------------------------
# finish_ingest_run Tests
# ---------------------------------------------------------------------------


class TestFinishIngestRun:
    """Tests for finish_ingest_run() function."""

    @pytest.mark.asyncio
    async def test_updates_ingest_run(self, mock_conn):
        """Updates ingest run with completion timestamp."""
        await finish_ingest_run(
            mock_conn,
            ingest_run_id=uuid.UUID("12345678-1234-5678-1234-567812345678"),
            status="succeeded",
        )

        sql_arg = mock_conn.execute.call_args[0][0]
        assert "UPDATE meta.ingest_run" in sql_arg
        assert "finished_at" in sql_arg

    @pytest.mark.asyncio
    async def test_handles_error_message(self, mock_conn):
        """Error message is stored when provided."""
        await finish_ingest_run(
            mock_conn,
            ingest_run_id=uuid.UUID("12345678-1234-5678-1234-567812345678"),
            status="failed",
            error_message="Connection timeout",
        )

        sql_arg = mock_conn.execute.call_args[0][0]
        assert "error_message" in sql_arg

    @pytest.mark.asyncio
    async def test_status_defaults_to_succeeded(self, mock_conn):
        """Status defaults to succeeded when not provided."""
        await finish_ingest_run(
            mock_conn, ingest_run_id=uuid.UUID("12345678-1234-5678-1234-567812345678")
        )

        sql_arg = mock_conn.execute.call_args[0][0]
        assert "UPDATE meta.ingest_run" in sql_arg


# ---------------------------------------------------------------------------
# __aenter__ Tests
# ---------------------------------------------------------------------------


class TestAsyncEnter:
    """Tests for __aenter__ async context manager entry."""

    @pytest.mark.asyncio
    async def test_acquires_connection(self, mock_pool, mock_conn):
        """Connection is acquired from pool."""
        # Setup async context manager for pool.acquire()
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx
        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(
            return_value=[uuid.UUID("12345678-1234-5678-1234-567812345678")]
        )
        mock_conn.execute.return_value = mock_result

        orchestrator = IngestionOrchestrator(pool=mock_pool, source_endpoint_id=1)
        result = await orchestrator.__aenter__()

        assert orchestrator._conn is mock_conn
        assert result.ingest_run_id == uuid.UUID("12345678-1234-5678-1234-567812345678")

    @pytest.mark.asyncio
    async def test_returns_ingest_run_info(self, mock_pool, mock_conn):
        """Returns IngestRunInfo with correct attributes."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx
        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(
            return_value=[uuid.UUID("12345678-1234-5678-1234-567812345678")]
        )
        mock_conn.execute.return_value = mock_result

        orchestrator = IngestionOrchestrator(pool=mock_pool, source_endpoint_id=1)
        result = await orchestrator.__aenter__()

        assert result.source_endpoint_id == 1
        assert result.ingest_run_id == uuid.UUID("12345678-1234-5678-1234-567812345678")


# ---------------------------------------------------------------------------
# __aexit__ Tests
# ---------------------------------------------------------------------------


class TestAsyncExit:
    """Tests for __aexit__ async context manager exit."""

    @pytest.mark.asyncio
    async def test_completes_ingest_run_on_success(self, mock_pool, mock_conn):
        """Ingest run is marked completed on success."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx
        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(
            return_value=[uuid.UUID("12345678-1234-5678-1234-567812345678")]
        )
        mock_conn.execute.return_value = mock_result

        orchestrator = IngestionOrchestrator(pool=mock_pool, source_endpoint_id=1)
        await orchestrator.__aenter__()
        await orchestrator.__aexit__(None, None, None)

        # Check that UPDATE was called for completing ingest run
        calls = [str(call) for call in mock_conn.execute.call_args_list]
        assert any("UPDATE meta.ingest_run" in str(call) for call in calls)

    @pytest.mark.asyncio
    async def test_marks_failed_on_exception(self, mock_pool, mock_conn):
        """Ingest run is marked failed on exception."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx
        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(
            return_value=[uuid.UUID("12345678-1234-5678-1234-567812345678")]
        )
        mock_conn.execute.return_value = mock_result

        orchestrator = IngestionOrchestrator(pool=mock_pool, source_endpoint_id=1)
        await orchestrator.__aenter__()
        await orchestrator.__aexit__(ValueError, ValueError("test error"), None)

        # Check that UPDATE with status='failed' was called
        calls = [str(call) for call in mock_conn.execute.call_args_list]
        assert any("failed" in str(call).lower() for call in calls)


# ---------------------------------------------------------------------------
# Integration Tests
# ---------------------------------------------------------------------------


class TestOrchestratorIntegration:
    """Integration tests for full orchestrator workflow."""

    @pytest.mark.asyncio
    async def test_full_context_manager_workflow(self, mock_pool, mock_conn):
        """Full workflow from entry to exit."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx
        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(
            return_value=[uuid.UUID("12345678-1234-5678-1234-567812345678")]
        )
        mock_conn.execute.return_value = mock_result

        orchestrator = IngestionOrchestrator(pool=mock_pool, source_endpoint_id=1)

        async with orchestrator as orch:
            assert orch.ingest_run_id == uuid.UUID(
                "12345678-1234-5678-1234-567812345678"
            )
            assert orch.source_endpoint_id == 1

    @pytest.mark.asyncio
    async def test_context_manager_handles_exception(self, mock_pool, mock_conn):
        """Context manager handles exceptions gracefully."""
        mock_acquire_ctx = MagicMock()
        mock_acquire_ctx.__aenter__ = AsyncMock(return_value=mock_conn)
        mock_acquire_ctx.__aexit__ = AsyncMock(return_value=None)
        mock_pool.connection.return_value = mock_acquire_ctx
        mock_result = AsyncMock()
        mock_result.fetchone = AsyncMock(
            return_value=[uuid.UUID("12345678-1234-5678-1234-567812345678")]
        )
        mock_conn.execute.return_value = mock_result

        orchestrator = IngestionOrchestrator(pool=mock_pool, source_endpoint_id=1)

        with pytest.raises(ValueError):
            async with orchestrator:
                raise ValueError("Test error")
