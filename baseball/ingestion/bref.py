"""baseball.ingestion.bref — Baseball Reference ingester.

Ingests Baseball Reference data into raw_bref schema.
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
from baseball.ingestion.loaders import HistoricalLoaderFactory

log = logging.getLogger(__name__)


class BRefIngester(BaseIngester):
    """Ingester for Baseball Reference data.

    Uses pybaseball to fetch data from Baseball Reference.
    """

    def __init__(
        self,
        pool: AsyncConnectionPool,
        workspace_id: UUID,
        data_dir: Optional[Path] = None,
    ):
        super().__init__(pool, workspace_id, "bref")
        self.data_dir = data_dir or Path("data/bref")
        self.engine = IngestEngine(pool)

    async def validate(self) -> bool:
        """Validate that required tables exist."""
        async with self.pool.connection() as conn:
            result = await conn.execute(
                "SELECT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'raw_bref' AND tablename = 'batting_standard')"
            )
            return (await result.fetchone())[0]

    async def ingest(
        self,
        season: Optional[int] = None,
        data_type: Optional[str] = None,
    ) -> IngestResult:
        """Ingest Baseball Reference data.

        Args:
            season: Season year (e.g., 2023). If None, current season.
            data_type: Type of data (batting, pitching, fielding, etc.).

        Returns:
            IngestResult with counts.
        """
        start_time = time.time()
        result = IngestResult()

        endpoint_id = await self._get_source_endpoint_id("bref")
        ingest_run_id = await self._create_ingest_run(
            endpoint_id,
            {"season": season, "data_type": data_type},
        )

        try:
            if data_type == "batting":
                result = await self._ingest_batting(season, ingest_run_id)
            elif data_type == "pitching":
                result = await self._ingest_pitching(season, ingest_run_id)
            elif data_type == "fielding":
                result = await self._ingest_fielding(season, ingest_run_id)
            elif data_type == "schedule":
                result = await self._ingest_schedule(season, ingest_run_id)
            elif season:
                result = await self._ingest_season(season, ingest_run_id)
            else:
                result = await self._ingest_all(ingest_run_id)

            await self._complete_ingest_run(ingest_run_id, "succeeded")
        except Exception as e:
            log.error("Baseball Reference ingestion failed: %s", e)
            await self._complete_ingest_run(ingest_run_id, "failed", str(e))
            result.errors += 1

        result.duration_seconds = time.time() - start_time
        return result

    async def _ingest_batting(
        self, season: Optional[int], ingest_run_id: UUID
    ) -> IngestResult:
        """Ingest batting stats from Baseball Reference."""
        result = IngestResult()

        try:
            from pybaseball import batting_stats_bref
        except ImportError:
            raise ImportError(
                "pybaseball is required for Baseball Reference ingestion. "
                "Install with: pip install pybaseball"
            )

        df = batting_stats_bref(season or 2023)
        result.rows_processed = len(df)

        csv_path = self.data_dir / f"batting_{season or 'current'}.csv"
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(csv_path, index=False)

        result.rows_inserted = await self._bulk_load_csv(
            "raw_bref.batting_standard", csv_path
        )
        return result

    async def _ingest_pitching(
        self, season: Optional[int], ingest_run_id: UUID
    ) -> IngestResult:
        """Ingest pitching stats from Baseball Reference."""
        result = IngestResult()

        try:
            from pybaseball import pitching_stats_bref
        except ImportError:
            raise ImportError(
                "pybaseball is required for Baseball Reference ingestion. "
                "Install with: pip install pybaseball"
            )

        df = pitching_stats_bref(season or 2023)
        result.rows_processed = len(df)

        csv_path = self.data_dir / f"pitching_{season or 'current'}.csv"
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(csv_path, index=False)

        result.rows_inserted = await self._bulk_load_csv(
            "raw_bref.pitching_standard", csv_path
        )
        return result

    async def _ingest_fielding(
        self, season: Optional[int], ingest_run_id: UUID
    ) -> IngestResult:
        """Ingest fielding stats from Baseball Reference."""
        result = IngestResult()

        try:
            from pybaseball import fielding_stats
        except ImportError:
            raise ImportError(
                "pybaseball is required for Baseball Reference ingestion. "
                "Install with: pip install pybaseball"
            )

        df = fielding_stats(season or 2023)
        result.rows_processed = len(df)

        csv_path = self.data_dir / f"fielding_{season or 'current'}.csv"
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(csv_path, index=False)

        result.rows_inserted = await self._bulk_load_csv(
            "raw_bref.fielding_standard", csv_path
        )
        return result

    async def _ingest_schedule(
        self, season: Optional[int], ingest_run_id: UUID
    ) -> IngestResult:
        """Ingest schedule data from Baseball Reference."""
        result = IngestResult()

        try:
            from pybaseball import schedule_and_record
        except ImportError:
            raise ImportError(
                "pybaseball is required for Baseball Reference ingestion. "
                "Install with: pip install pybaseball"
            )

        df = schedule_and_record(season or 2023)
        result.rows_processed = len(df)

        csv_path = self.data_dir / f"schedule_{season or 'current'}.csv"
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(csv_path, index=False)

        result.rows_inserted = await self._bulk_load_csv("raw_bref.schedule", csv_path)
        return result

    async def _ingest_season(self, season: int, ingest_run_id: UUID) -> IngestResult:
        """Ingest all Baseball Reference data for a season."""
        result = IngestResult()

        for data_type in ["batting", "pitching", "fielding", "schedule"]:
            type_result = await self.ingest(season=season, data_type=data_type)
            result.rows_processed += type_result.rows_processed
            result.rows_inserted += type_result.rows_inserted

        return result

    async def _ingest_all(self, ingest_run_id: UUID) -> IngestResult:
        """Ingest all available Baseball Reference data."""
        result = IngestResult()

        for data_type in ["batting", "pitching", "fielding", "schedule"]:
            type_result = await self.ingest(data_type=data_type)
            result.rows_processed += type_result.rows_processed
            result.rows_inserted += type_result.rows_inserted

        return result

    async def _bulk_load_csv(self, table_name: str, csv_path: Path) -> int:
        """Bulk load CSV into a table using COPY.

        Delegates to IngestEngine for actual loading.
        """
        return await self.engine.bulk_load_raw_csv(table_name, csv_path)
