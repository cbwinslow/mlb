"""baseball.ingestion.base — Abstract base class for data source ingesters.

Provides common patterns for all ingestion implementations.
"""

from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path
from typing import Any, Optional
from uuid import UUID

import psycopg
from psycopg_pool import AsyncConnectionPool

log = logging.getLogger(__name__)


@dataclass
class IngestResult:
    """Result of an ingestion operation."""

    rows_processed: int = 0
    rows_inserted: int = 0
    rows_updated: int = 0
    errors: int = 0
    ingest_run_id: Optional[UUID] = None
    duration_seconds: float = 0.0


class BaseIngester(ABC):
    """Abstract base class for all data source ingesters.

    Provides common patterns for:
    - Source endpoint tracking
    - Ingest run management
    - Error handling and logging
    - Progress reporting
    """

    def __init__(
        self,
        pool: AsyncConnectionPool,
        workspace_id: UUID,
        source_code: str,
    ):
        self.pool = pool
        self.workspace_id = workspace_id
        self.source_code = source_code

    @abstractmethod
    async def ingest(self, **kwargs: Any) -> IngestResult:
        """Run the ingestion process.

        Returns:
            IngestResult with counts and metadata.
        """
        ...

    @abstractmethod
    async def validate(self) -> bool:
        """Validate that required tables/columns exist.

        Returns:
            True if validation passes.
        """
        ...

    async def _create_request_id(self, ingest_run_id: UUID) -> UUID:
        """Create a request record for raw data ingestion.

        Args:
            ingest_run_id: UUID of the ingest run.

        Returns:
            The raw request UUID for the specific source.
        """
        result = await self.pool.execute(
            """
            INSERT INTO meta.source_file (file_path, file_hash, ingest_run_id)
            VALUES (%s, %s, %s)
            RETURNING source_file_id
            """,
            (f"{self.source_code}_ingest", None, ingest_run_id),
        )
        row = await result.fetchone()
        return row[0] if row else ingest_run_id

    async def _get_source_endpoint_id(self, endpoint_code: str) -> int:
        """Get source_endpoint_id for tracking.

        Args:
            endpoint_code: Code from meta.source_endpoint.

        Returns:
            The source_endpoint_id integer.
        """
        async with self.pool.connection() as conn:
            result = await conn.execute(
                "SELECT source_endpoint_id FROM meta.source_endpoint WHERE endpoint_code = %s",
                (endpoint_code,),
            )
            row = await result.fetchone()
            if row:
                return row[0]
            # Create if not exists
            result = await conn.execute(
                """
                INSERT INTO meta.source_endpoint (endpoint_code, endpoint_name, source_system_id)
                VALUES (%s, %s, (SELECT source_system_id FROM meta.source_system WHERE source_code = %s))
                ON CONFLICT (source_system_id, endpoint_code) DO UPDATE
                    SET endpoint_name = EXCLUDED.endpoint_name
                RETURNING source_endpoint_id
                """,
                (endpoint_code, endpoint_code, self.source_code),
            )
            return (await result.fetchone())[0]

    async def _create_ingest_run(
        self,
        source_endpoint_id: int,
        metadata: Optional[dict] = None,
    ) -> UUID:
        """Create a new ingest_run record.

        Args:
            source_endpoint_id: FK to meta.source_endpoint.
            metadata: Optional JSON metadata.

        Returns:
            The ingest_run_id UUID.
        """
        from baseball.ingestion.orchestrator import start_ingest_run

        async with self.pool.connection() as conn:
            return await start_ingest_run(conn, source_endpoint_id, metadata)

    async def _complete_ingest_run(
        self,
        ingest_run_id: UUID,
        status: str = "succeeded",
        error_message: Optional[str] = None,
    ) -> None:
        """Mark an ingest run as complete.

        Args:
            ingest_run_id: UUID of the ingest run.
            status: Final status.
            error_message: Optional error message.
        """
        from baseball.ingestion.orchestrator import finish_ingest_run

        async with self.pool.connection() as conn:
            await finish_ingest_run(conn, ingest_run_id, status, error_message)

    def _get_season_from_date(self, game_date: date) -> int:
        """Extract season year from a date."""
        return game_date.year

    def _format_date(self, date_val: date | datetime | str) -> str:
        """Format date for SQL queries."""
        if isinstance(date_val, str):
            return date_val
        return date_val.isoformat()

    async def _bulk_load_csv(
        self,
        table_name: str,
        csv_path: Path,
    ) -> int:
        """Bulk load CSV into a table using IngestEngine.

        Args:
            table_name: Fully qualified table name (e.g., 'raw_fangraphs.batting_standard').
            csv_path: Path to the CSV file to load.

        Returns:
            Number of rows loaded.
        """
        engine = IngestEngine(self.pool)
        return await engine.bulk_load_raw_csv(table_name, csv_path)
