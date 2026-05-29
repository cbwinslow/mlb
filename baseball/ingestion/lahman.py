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
        "fielding_of",
        "teams",
        "teams_franchises",
        "teams_half",
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
        "allstar_full",
    ]

    CSV_NAME_MAP = {
        "people": "People.csv",
        "batting": "Batting.csv",
        "pitching": "Pitching.csv",
        "fielding": "Fielding.csv",
        "fielding_of_split": "FieldingOFsplit.csv",
        "fielding_of": "FieldingOF.csv",
        "teams": "Teams.csv",
        "teams_franchises": "TeamsFranchises.csv",
        "teams_half": "TeamsHalf.csv",
        "salaries": "Salaries.csv",
        "awards_players": "AwardsPlayers.csv",
        "awards_managers": "AwardsManagers.csv",
        "awards_share_players": "AwardsSharePlayers.csv",
        "awards_share_managers": "AwardsShareManagers.csv",
        "hall_of_fame": "HallOfFame.csv",
        "schools": "Schools.csv",
        "college_playing": "CollegePlaying.csv",
        "appearances": "Appearances.csv",
        "managers": "Managers.csv",
        "managers_half": "ManagersHalf.csv",
        "batting_post": "BattingPost.csv",
        "pitching_post": "PitchingPost.csv",
        "fielding_post": "FieldingPost.csv",
        "series_post": "SeriesPost.csv",
        "home_games": "HomeGames.csv",
        "parks": "Parks.csv",
        "allstar_full": "AllstarFull.csv",
    }

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

    async def download(
        self,
    ) -> int:
        """Download Lahman database CSV files.

        Downloads the Lahman database. Sources tried in order:
        1. Skip if CSV files already exist in data/lahman/
        2. Extract local zip files in data/lahman/*.zip
        3. pybaseball.download_lahman() (sync, may require manual download)

        Note: Automatic download may fail due to Box.com anti-bot measures.
        Manual download instructions:
        1. Visit: https://sabr.org/lahman-database/
        2. Click "Comma-delimited version" and download the zip file
        3. Save the zip to: data/lahman/

        Returns:
            Number of CSV files extracted.
        """
        self.data_dir.mkdir(parents=True, exist_ok=True)

        # Check if CSVs already exist (skip extraction)
        existing_csvs = list(self.data_dir.glob("*.csv"))
        if existing_csvs:
            log.info("Found %d existing CSV files in %s", len(existing_csvs), self.data_dir)
            return len(existing_csvs)

        # Try local zip files next
        local_zips = list(self.data_dir.glob("*.zip"))
        if local_zips:
            for zip_path in local_zips:
                self._extract_from_local_zip(zip_path)
            extracted_names = [p.stem for p in self.data_dir.glob("*.csv")]
            log.info("Extracted %d CSV files from local zip", len(extracted_names))
            return len(extracted_names)

        # Try pybaseball (sync method)
        try:
            from pybaseball.lahman import download_lahman
            download_lahman()
            import pybaseball.cache as cache
            csv_files = list(Path(cache.config.cache_directory).glob("**/*.csv"))
            for csv_path in csv_files:
                target = self.data_dir / csv_path.name
                target.write_bytes(csv_path.read_bytes())
            log.info("Downloaded %d Lahman CSV files via pybaseball", len(csv_files))
            return len(csv_files)
        except Exception as e:
            log.debug("pybaseball download unavailable: %s", e)

        log.warning("Automatic download failed.")
        log.warning("Manual download instructions:")
        log.warning("  1. Visit: https://sabr.org/lahman-database/")
        log.warning("  2. Click 'Comma-delimited version' (Box.com)")
        log.warning("  3. Download the ZIP file")
        log.warning("  4. Save to: %s", self.data_dir)
        return 0

    def _extract_from_local_zip(self, zip_path: Path) -> list[str]:
        """Extract all CSV files from a local zip file."""
        import zipfile

        extracted = []
        with zipfile.ZipFile(zip_path) as zf:
            for name in zf.namelist():
                if name.lower().endswith(".csv"):
                    stem = Path(name).name
                    dest = self.data_dir / stem
                    dest.write_bytes(zf.open(name).read())
                    extracted.append(stem)
        return extracted

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

        csv_name = self.CSV_NAME_MAP.get(table_name, f"{table_name}.csv")
        csv_path = self.data_dir / csv_name

        if not csv_path.exists():
            log.warning("CSV file not found for table %s: %s", table_name, csv_path)
            return result

        # Get column names from CSV header, exclude source_file_id
        with csv_path.open("r") as f:
            header = f.readline().strip().split(",")
        # Exclude source_file_id - it will be NULL
        columns = [c for c in header if c not in ("source_file_id", "created_at")]

        # Bulk load CSV (source_file_id is NULL, created_at defaults to NOW())
        result.rows_processed = await self.engine.bulk_load_raw_csv(
            f"raw_lahman.{table_name}",
            csv_path,
            columns=columns,
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
            table_result = await self._ingest_table(table_name, ingest_run_id)
            result.rows_processed += table_result.rows_processed
            result.rows_inserted += table_result.rows_inserted

        return result
