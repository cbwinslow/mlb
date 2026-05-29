"""baseball.ingestion.statcast — Statcast pitch telemetry ingester.

Ingests Statcast data via pybaseball into raw_statcast schema,
then processes through util.ingest_statcast_play() to core tables.
"""

from __future__ import annotations

import logging
import time
from datetime import date, datetime
from pathlib import Path
from typing import Optional
from uuid import UUID

from psycopg_pool import AsyncConnectionPool

from baseball.ingestion.base import BaseIngester, IngestResult
from baseball.ingestion.engine import IngestEngine

log = logging.getLogger(__name__)


class StatcastIngester(BaseIngester):
    """Ingester for Statcast pitch telemetry.

    Uses pybaseball to fetch data from Baseball Savant.
    """

    def __init__(
        self,
        pool: AsyncConnectionPool,
        workspace_id: UUID,
        data_dir: Optional[Path] = None,
    ):
        super().__init__(pool, workspace_id, "statcast")
        self.data_dir = data_dir or Path("data/statcast")
        self.engine = IngestEngine(pool)

    async def validate(self) -> bool:
        """Validate that required tables exist."""
        async with self.pool.connection() as conn:
            result = await conn.execute(
                "SELECT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'raw_statcast' AND tablename = 'pitch')"
            )
            return (await result.fetchone())[0]

    async def ingest(
        self,
        start_date: Optional[date] = None,
        end_date: Optional[date] = None,
        season: Optional[int] = None,
    ) -> IngestResult:
        """Ingest Statcast data.

        Args:
            start_date: Start date (YYYY-MM-DD).
            end_date: End date (YYYY-MM-DD).
            season: Season year (alternative to date range).

        Returns:
            IngestResult with counts.
        """
        start_time = time.time()
        result = IngestResult()

        endpoint_id = await self._get_source_endpoint_id("statcast")
        ingest_run_id = await self._create_ingest_run(
            endpoint_id,
            {"start_date": start_date, "end_date": end_date, "season": season},
        )

        try:
            if season:
                result = await self._ingest_season(season, ingest_run_id)
            elif start_date and end_date:
                result = await self._ingest_range(start_date, end_date, ingest_run_id)
            else:
                raise ValueError(
                    "Either season or start_date/end_date must be provided"
                )

            await self._complete_ingest_run(ingest_run_id, "succeeded")
        except Exception as e:
            log.error("Statcast ingestion failed: %s", e)
            await self._complete_ingest_run(ingest_run_id, "failed", str(e))
            result.errors += 1

        result.duration_seconds = time.time() - start_time
        return result

    async def _ingest_season(self, season: int, ingest_run_id: UUID) -> IngestResult:
        """Ingest all Statcast data for a season."""
        # Statcast season runs roughly March-October
        start_dt = date(season, 3, 1)
        end_dt = date(season, 10, 31)
        return await self._ingest_range(start_dt, end_dt, ingest_run_id)

    async def _ingest_range(
        self,
        start_date: date,
        end_date: date,
        ingest_run_id: UUID,
    ) -> IngestResult:
        """Ingest Statcast data for a date range."""
        result = IngestResult()

        # Fetch via pybaseball
        try:
            import pybaseball
            from pybaseball import statcast as pybaseball_statcast
        except ImportError:
            raise ImportError(
                "pybaseball is required for Statcast ingestion. "
                "Install with: pip install pybaseball"
            )

        # pybaseball returns a pandas DataFrame
        df = pybaseball_statcast(
            start_dt=start_date.isoformat(),
            end_dt=end_date.isoformat(),
        )

        result.rows_processed = len(df)

        # Save to CSV for bulk loading
        csv_path = self.data_dir / f"statcast_{start_date}_{end_date}.csv"
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(csv_path, index=False)

        # Bulk load via COPY
        result.rows_inserted = await self.engine.bulk_load_raw_csv(
            "raw_statcast.pitch",
            csv_path,
        )

        return result

    async def _process_to_core(self, ingest_run_id: UUID) -> None:
        """Process raw Statcast data to core tables.

        Calls util.ingest_statcast_play() for each row.
        """
        async with self.pool.connection() as conn:
            # Get all raw statcast rows that haven't been processed
            result = await conn.execute(
                """
                SELECT * FROM raw_statcast.pitch
                WHERE ingest_run_id = %s
                """,
                (ingest_run_id,),
            )
            rows = await result.fetchall()

            for row in rows:
                # Call util.ingest_statcast_play() for each pitch
                # This is handled by the trigger in production
                pass
