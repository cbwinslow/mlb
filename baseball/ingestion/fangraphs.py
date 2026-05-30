"""baseball.ingestion.fangraphs — FanGraphs data ingester.

Ingests FanGraphs data (batting, pitching, fielding, splits) into
raw_fangraphs schema.
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


class FanGraphsIngester(BaseIngester):
    """Ingester for FanGraphs data.

    Uses pybaseball to fetch data from FanGraphs.
    """

    def __init__(
        self,
        pool: AsyncConnectionPool,
        workspace_id: UUID,
        data_dir: Optional[Path] = None,
    ):
        super().__init__(pool, workspace_id, "fangraphs")
        self.data_dir = data_dir or Path("data/fangraphs")
        self.engine = IngestEngine(pool)

    async def validate(self) -> bool:
        """Validate that required tables exist."""
        async with self.pool.connection() as conn:
            result = await conn.execute(
                "SELECT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'raw_fangraphs' AND tablename = 'batting_standard')"
            )
            return (await result.fetchone())[0]

    async def ingest(
        self,
        season: Optional[int] = None,
        data_type: Optional[str] = None,
    ) -> IngestResult:
        """Ingest FanGraphs data.

        Args:
            season: Season year (e.g., 2023). If None, current season.
            data_type: Type of data (batting, pitching, fielding, splits, etc.).

        Returns:
            IngestResult with counts.
        """
        start_time = time.time()
        result = IngestResult()

        endpoint_id = await self._get_source_endpoint_id("fangraphs")
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
            elif data_type == "batter_splits":
                result = await self._ingest_batter_splits(season, ingest_run_id)
            elif data_type == "pitcher_splits":
                result = await self._ingest_pitcher_splits(season, ingest_run_id)
            elif data_type == "baserunning":
                result = await self._ingest_baserunning(season, ingest_run_id)
            elif data_type == "plate_discipline":
                result = await self._ingest_plate_discipline(season, ingest_run_id)
            elif season:
                result = await self._ingest_season(season, ingest_run_id)
            else:
                result = await self._ingest_all(ingest_run_id)

            await self._complete_ingest_run(ingest_run_id, "succeeded")
        except Exception as e:
            log.error("FanGraphs ingestion failed: %s", e)
            await self._complete_ingest_run(ingest_run_id, "failed", str(e))
            result.errors += 1

        result.duration_seconds = time.time() - start_time
        return result

    async def _ingest_batting(
        self, season: Optional[int], ingest_run_id: UUID
    ) -> IngestResult:
        """Ingest batting stats."""
        result = IngestResult()

        try:
            from pybaseball import batting_stats
        except ImportError:
            raise ImportError(
                "pybaseball is required for FanGraphs ingestion. "
                "Install with: pip install pybaseball"
            )

        df = batting_stats(season or 2023)
        result.rows_processed = len(df)

        # Save to CSV
        csv_path = self.data_dir / f"batting_{season or 'current'}.csv"
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(csv_path, index=False)

        # Bulk load
        result.rows_inserted = await self._bulk_load_csv(
            "raw_fangraphs.batting_standard", csv_path
        )
        return result

    async def _ingest_pitching(
        self, season: Optional[int], ingest_run_id: UUID
    ) -> IngestResult:
        """Ingest pitching stats."""
        result = IngestResult()

        try:
            from pybaseball import pitching_stats
        except ImportError:
            raise ImportError(
                "pybaseball is required for FanGraphs ingestion. "
                "Install with: pip install pybaseball"
            )

        df = pitching_stats(season or 2023)
        result.rows_processed = len(df)

        csv_path = self.data_dir / f"pitching_{season or 'current'}.csv"
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(csv_path, index=False)

        result.rows_inserted = await self._bulk_load_csv(
            "raw_fangraphs.pitching_standard", csv_path
        )
        return result

    async def _ingest_fielding(
        self, season: Optional[int], ingest_run_id: UUID
    ) -> IngestResult:
        """Ingest fielding stats."""
        result = IngestResult()

        try:
            from pybaseball import fielding_stats
        except ImportError:
            raise ImportError(
                "pybaseball is required for FanGraphs ingestion. "
                "Install with: pip install pybaseball"
            )

        df = fielding_stats(season or 2023)
        result.rows_processed = len(df)

        csv_path = self.data_dir / f"fielding_{season or 'current'}.csv"
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(csv_path, index=False)

        result.rows_inserted = await self._bulk_load_csv(
            "raw_fangraphs.fielding_standard", csv_path
        )
        return result

    async def _ingest_batter_splits(
        self, season: Optional[int], ingest_run_id: UUID
    ) -> IngestResult:
        """Ingest batter splits data."""
        result = IngestResult()

        try:
            # Try to use FanGraphs split endpoints if available in pybaseball
            from pybaseball import batting_stats_bref
        except ImportError:
            raise ImportError(
                "pybaseball is required for FanGraphs ingestion. "
                "Install with: pip install pybaseball"
            )

        # Note: pybaseball's split functions may require different parameters
        # For now, using batting_stats_bref which provides split-like data
        df = batting_stats_bref(season or 2023)
        result.rows_processed = len(df)

        csv_path = self.data_dir / f"batter_splits_{season or 'current'}.csv"
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(csv_path, index=False)

        result.rows_inserted = await self._bulk_load_csv(
            "raw_fangraphs.batter_splits", csv_path
        )
        return result

    async def _ingest_pitcher_splits(
        self, season: Optional[int], ingest_run_id: UUID
    ) -> IngestResult:
        """Ingest pitcher splits data."""
        result = IngestResult()

        try:
            from pybaseball import pitching_stats_bref
        except ImportError:
            raise ImportError(
                "pybaseball is required for FanGraphs ingestion. "
                "Install with: pip install pybaseball"
            )

        df = pitching_stats_bref(season or 2023)
        result.rows_processed = len(df)

        csv_path = self.data_dir / f"pitcher_splits_{season or 'current'}.csv"
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(csv_path, index=False)

        result.rows_inserted = await self._bulk_load_csv(
            "raw_fangraphs.pitcher_splits", csv_path
        )
        return result

    async def _ingest_baserunning(
        self, season: Optional[int], ingest_run_id: UUID
    ) -> IngestResult:
        """Ingest baserunning stats using fg_batting_data with baserunning columns."""
        result = IngestResult()

        try:
            from pybaseball import fg_batting_data
        except ImportError:
            raise ImportError(
                "pybaseball is required for FanGraphs ingestion. "
                "Install with: pip install pybaseball"
            )

        # Use fg_batting_data with baserunning-related stat columns
        df = fg_batting_data(
            start_season=season or 2023,
            stat_columns=["SB", "CS", "wSB", "BsR"],
        )
        result.rows_processed = len(df)

        csv_path = self.data_dir / f"baserunning_{season or 'current'}.csv"
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(csv_path, index=False)

        result.rows_inserted = await self._bulk_load_csv(
            "raw_fangraphs.baserunning", csv_path
        )
        return result

    async def _ingest_plate_discipline(
        self, season: Optional[int], ingest_run_id: UUID
    ) -> IngestResult:
        """Ingest plate discipline stats using fg_batting_data with plate discipline columns."""
        result = IngestResult()

        try:
            from pybaseball import fg_batting_data
        except ImportError:
            raise ImportError(
                "pybaseball is required for FanGraphs ingestion. "
                "Install with: pip install pybaseball"
            )

        # Use fg_batting_data with plate discipline stat columns
        df = fg_batting_data(
            start_season=season or 2023,
            stat_columns=[
                "O-Swing%",
                "Z-Swing%",
                "Swing%",
                "O-Contact%",
                "Z-Contact%",
                "Contact%",
                "Zone%",
                "F-Strike%",
                "BB%",
                "K%",
            ],
        )
        result.rows_processed = len(df)

        csv_path = self.data_dir / f"plate_discipline_{season or 'current'}.csv"
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(csv_path, index=False)

        result.rows_inserted = await self._bulk_load_csv(
            "raw_fangraphs.plate_discipline", csv_path
        )
        return result

    async def _ingest_season(self, season: int, ingest_run_id: UUID) -> IngestResult:
        """Ingest all FanGraphs data for a season."""
        result = IngestResult()

        for data_type in [
            "batting",
            "pitching",
            "fielding",
            "batter_splits",
            "pitcher_splits",
            "baserunning",
            "plate_discipline",
        ]:
            type_result = await self.ingest(season=season, data_type=data_type)
            result.rows_processed += type_result.rows_processed
            result.rows_inserted += type_result.rows_inserted

        return result

    async def _ingest_all(self, ingest_run_id: UUID) -> IngestResult:
        """Ingest all available FanGraphs data."""
        result = IngestResult()

        # Ingest current season data
        for data_type in [
            "batting",
            "pitching",
            "fielding",
            "batter_splits",
            "pitcher_splits",
            "baserunning",
            "plate_discipline",
        ]:
            type_result = await self.ingest(data_type=data_type)
            result.rows_processed += type_result.rows_processed
            result.rows_inserted += type_result.rows_inserted

        return result

    async def _bulk_load_csv(self, table_name: str, csv_path: Path) -> int:
        """Bulk load CSV into a table using COPY.

        Delegates to IngestEngine for actual loading.
        """
        return await self.engine.bulk_load_raw_csv(table_name, csv_path)
