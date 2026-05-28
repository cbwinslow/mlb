"""baseball.ingestion.lahman — Lahman database ingester.

Ingests Lahman database CSV files into raw_lahman schema.
"""

from __future__ import annotations

import logging
import time
from pathlib import Path
from typing import Optional
from uuid import UUID

from psycopg_pool import AsyncConnectionPool

from baseball.ingestion.base import BaseIngester, IngestResult
from baseball.ingestion.engine import IngestEngine

log = logging.getLogger(__name__)


class LahmanIngester(BaseIngester):
    """Ingester for Lahman Baseball Database CSV files.

    The Lahman database provides historical player, team, and season data
    in CSV format. This ingester loads the CSV files directly into the
    raw_lahman schema tables.
    """

    LAHMAN_TABLES = [
        "people",
        "batting",
        "pitching",
        "fielding",
        "fielding_of_split",
        "teams",
        "salaries",
        "awards_players",
        "awards_managers",
        "awards_share_players",
        "awards_share_managers",
        "hall_of_fame",
        "schools",
        "college_playing",
        "appearances",
        "managers",
        "managers_half",
        "batting_post",
        "pitching_post",
        "fielding_post",
        "series_post",
        "home_games",
        "parks",
    ]

    def __init__(
        self,
        pool: AsyncConnectionPool,
        workspace_id: UUID,
        data_dir: Optional[Path] = None,
    ):
        super().__init__(pool, workspace_id, "lahman")
        self.data_dir = data_dir or Path("data/lahman")
        self.engine = IngestEngine(pool)

    async def validate(self) -> bool:
        """Validate that required tables exist."""
        async with self.pool.connection() as conn:
            result = await conn.execute(
                "SELECT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'raw_lahman' AND tablename = 'people')"
            )
            return (await result.fetchone())[0]

    async def ingest(
        self,
        season: Optional[int] = None,
        data_type: Optional[str] = None,
    ) -> IngestResult:
        """Ingest Lahman database tables.

        Args:
            season: Optional season filter (not typically used for Lahman).
            data_type: Specific table to ingest, or None for all.

        Returns:
            IngestResult with counts.
        """
        start_time = time.time()
        result = IngestResult()

        endpoint_id = await self._get_source_endpoint_id("lahman")
        ingest_run_id = await self._create_ingest_run(
            endpoint_id,
            {"season": season, "data_type": data_type},
        )

        try:
            if data_type:
                if data_type in self.LAHMAN_TABLES:
                    result = await self._ingest_table(data_type, ingest_run_id)
                else:
                    log.warning("Unknown data type: %s", data_type)
            else:
                result = await self._ingest_all(ingest_run_id)

            await self._complete_ingest_run(ingest_run_id, "succeeded")
        except Exception as e:
            log.error("Lahman ingestion failed: %s", e)
            await self._complete_ingest_run(ingest_run_id, "failed", str(e))
            result.errors += 1

        result.duration_seconds = time.time() - start_time
        return result

    async def _ingest_table(self, table_name: str, ingest_run_id: UUID) -> IngestResult:
        """Ingest a specific Lahman table.

        Args:
            table_name: Name of the table (e.g., 'people', 'batting')
            ingest_run_id: Ingest run ID for tracking

        Returns:
            IngestResult with counts
        """
        result = IngestResult()

        csv_path = self.data_dir / f"{table_name}.csv"
        if not csv_path.exists():
            log.warning("CSV file not found for table %s: %s", table_name, csv_path)
            return result

        csv_path.parent.mkdir(parents=True, exist_ok=True)

        result.rows_processed = await self.engine.bulk_load_raw_csv(
            f"raw_lahman.{table_name}",
            csv_path,
        )
        result.rows_inserted = result.rows_processed

        return result

    async def _ingest_all(self, ingest_run_id: UUID) -> IngestResult:
        """Ingest all Lahman tables.

        Args:
            ingest_run_id: Ingest run ID for tracking

        Returns:
            IngestResult with aggregated counts
        """
        result = IngestResult()

        for table_name in self.LAHMAN_TABLES:
            table_result = await self.ingest(data_type=table_name)
            result.rows_processed += table_result.rows_processed
            result.rows_inserted += table_result.rows_inserted

        return result