"""baseball.ingestion.orchestrator — orchestration context manager.

Manages ingest_run tracking via meta.ingest_run with utility functions for
start/end timestamps. Designed to be used as an async context manager.
"""

from __future__ import annotations

import uuid
from contextlib import asynccontextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import AsyncIterator, Optional

import psycopg
from psycopg_pool import AsyncConnectionPool


@dataclass
class IngestRunInfo:
    """Container for ingest run metadata."""

    ingest_run_id: uuid.UUID
    source_endpoint_id: int
    started_at: datetime
    completed_at: Optional[datetime] = None


async def startingestrun(
    conn: psycopg.AsyncConnection,
    source_endpoint_id: int,
    run_metadata: Optional[dict] = None,
) -> uuid.UUID:
    """Create a new ingest_run record and return its ID.

    Args:
        conn: Active database connection
        source_endpoint_id: Foreign key to meta.source_endpoint
        run_metadata: Optional JSON metadata to store with the run

    Returns:
        UUID of the created ingest_run record
    """
    ingest_run_id = uuid.uuid4()
    sql = """
        INSERT INTO meta.ingest_run (
            ingest_run_id, source_endpoint_id, run_metadata, started_at
        )
        VALUES (%(ingest_run_id)s, %(source_endpoint_id)s, %(run_metadata)s, NOW())
        RETURNING ingest_run_id
    """
    run_metadata_json = run_metadata or {}
    result = await conn.execute(
        sql,
        {
            "ingest_run_id": ingest_run_id,
            "source_endpoint_id": source_endpoint_id,
            "run_metadata": run_metadata_json,
        },
    )
    return (await result.fetchone())[0]


async def finishingestrun(
    conn: psycopg.AsyncConnection,
    ingest_run_id: uuid.UUID,
    status: str = "completed",
    error_message: Optional[str] = None,
) -> None:
    """Mark an ingest run as completed or failed.

    Args:
        conn: Active database connection
        ingest_run_id: UUID of the ingest run to complete
        status: 'completed' or 'failed'
        error_message: Optional error details if status is 'failed'
    """
    sql = """
        UPDATE meta.ingest_run
        SET completed_at = NOW(),
            status = %(status)s,
            error_message = %(error_message)s
        WHERE ingest_run_id = %(ingest_run_id)s
    """
    await conn.execute(
        sql,
        {
            "ingest_run_id": ingest_run_id,
            "status": status,
            "error_message": error_message,
        },
    )
    await conn.commit()


class IngestionOrchestrator:
    """Orchestration context manager for data ingestion runs.

    Usage:
        async with IngestionOrchestrator(conn, endpoint_id) as run_info:
            # Perform ingestion
            pass
    """

    def __init__(
        self,
        pool: AsyncConnectionPool,
        source_endpoint_id: int,
        run_metadata: Optional[dict] = None,
    ):
        self.pool = pool
        self.source_endpoint_id = source_endpoint_id
        self.run_metadata = run_metadata or {}
        self.ingest_run_id: Optional[uuid.UUID] = None
        self._conn: Optional[psycopg.AsyncConnection] = None

    async def __aenter__(self) -> IngestRunInfo:
        async with self.pool.acquire() as conn:
            self._conn = conn
            self.ingest_run_id = await startingestrun(
                conn, self.source_endpoint_id, self.run_metadata
            )
            return IngestRunInfo(
                ingest_run_id=self.ingest_run_id,
                source_endpoint_id=self.source_endpoint_id,
                started_at=datetime.now(timezone.utc),
            )

    async def __aexit__(self, exc_type, exc_val, exc_tb) -> None:
        async with self.pool.acquire() as conn:
            if exc_type is not None:
                await finishingestrun(
                    conn,
                    self.ingest_run_id,
                    status="failed",
                    error_message=str(exc_val) if exc_val else None,
                )
            else:
                await finishingestrun(conn, self.ingest_run_id, status="completed")

    @asynccontextmanager
    async def track_run(
        self,
        pool: AsyncConnectionPool,
        endpoint_id: int,
        metadata: Optional[dict] = None,
    ) -> AsyncIterator[IngestRunInfo]:
        """Create an ingest_run context without storing state on self."""
        async with pool.acquire() as conn:
            run_id = await startingestrun(conn, endpoint_id, metadata or {})
            run_info = IngestRunInfo(
                ingest_run_id=run_id,
                source_endpoint_id=endpoint_id,
                started_at=datetime.now(timezone.utc),
            )
        try:
            yield run_info
        finally:
            async with pool.acquire() as conn:
                await finishingestrun(conn, run_id, status="completed")
