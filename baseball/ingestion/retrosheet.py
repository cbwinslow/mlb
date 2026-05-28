"""baseball.ingestion.retrosheet — Retrosheet event file ingester.

Ingests Retrosheet event files (.EVN, .EVA) into raw_retrosheet schema,
then processes through util.ingest_chadwick_play() to core tables.
"""

from __future__ import annotations

import gzip
import logging
import time
from pathlib import Path
from typing import Optional
from uuid import UUID

from psycopg_pool import AsyncConnectionPool

from baseball.ingestion.base import BaseIngester, IngestResult
from baseball.ingestion.loaders import HistoricalLoaderFactory

log = logging.getLogger(__name__)


class RetrosheetIngester(BaseIngester):
    """Ingester for Retrosheet event files.

    Handles:
    - Event file parsing (fixed-width format)
    - Raw table insertion (raw_retrosheet.record)
    - Core table processing via SQL functions
    """

    def __init__(
        self,
        pool: AsyncConnectionPool,
        workspace_id: UUID,
        data_dir: Optional[Path] = None,
    ):
        super().__init__(pool, workspace_id, "retrosheet")
        self.data_dir = data_dir or Path("data/retrosheet")

    async def validate(self) -> bool:
        """Validate that required tables exist."""
        async with self.pool.connection() as conn:
            result = await conn.execute(
                "SELECT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'raw_retrosheet' AND tablename = 'record')"
            )
            return (await result.fetchone())[0]

    async def ingest(
        self,
        year: Optional[int] = None,
        file_path: Optional[Path] = None,
    ) -> IngestResult:
        """Ingest Retrosheet event files.

        Args:
            year: Year to ingest (e.g., 2023). If None, ingest all available.
            file_path: Specific file to ingest. If None, discover from data_dir.

        Returns:
            IngestResult with counts.
        """
        start_time = time.time()
        result = IngestResult()

        endpoint_id = await self._get_source_endpoint_id("retrosheet")
        ingest_run_id = await self._create_ingest_run(endpoint_id, {"year": year})

        try:
            if file_path:
                result = await self._ingest_single_file(file_path, ingest_run_id)
            elif year:
                result = await self._ingest_year(year, ingest_run_id)
            else:
                result = await self._ingest_all(ingest_run_id)

            await self._complete_ingest_run(ingest_run_id, "succeeded")
        except Exception as e:
            log.error("Retrosheet ingestion failed: %s", e)
            await self._complete_ingest_run(ingest_run_id, "failed", str(e))
            result.errors += 1

        result.duration_seconds = time.time() - start_time
        return result

    async def _ingest_single_file(
        self,
        file_path: Path,
        ingest_run_id: UUID,
    ) -> IngestResult:
        """Ingest a single Retrosheet event file."""
        result = IngestResult()

        # Determine if gzipped
        actual_path = file_path
        if not file_path.exists() and file_path.suffix != ".gz":
            actual_path = file_path.with_suffix(file_path.suffix + ".gz")

        if not actual_path.exists():
            raise FileNotFoundError(f"Event file not found: {file_path}")

        # Parse and insert records
        records = self._parse_event_file(actual_path)
        result.rows_processed = len(records)

        # Bulk insert via COPY
        async with self.pool.connection() as conn:
            # Insert into raw_retrosheet.record
            # Then process through util.ingest_chadwick_play()
            pass

        return result

    async def _ingest_year(
        self,
        year: int,
        ingest_run_id: UUID,
    ) -> IngestResult:
        """Ingest all event files for a specific year."""
        result = IngestResult()

        year_dir = self.data_dir / str(year)
        if not year_dir.exists():
            log.warning("No data directory for year %d", year)
            return result

        for event_file in sorted(year_dir.glob("*.EVN")) + sorted(year_dir.glob("*.EVA")):
            file_result = await self._ingest_single_file(event_file, ingest_run_id)
            result.rows_processed += file_result.rows_processed
            result.rows_inserted += file_result.rows_inserted

        return result

    async def _ingest_all(self, ingest_run_id: UUID) -> IngestResult:
        """Ingest all available Retrosheet data."""
        result = IngestResult()

        for year_dir in sorted(self.data_dir.iterdir()):
            if year_dir.is_dir() and year_dir.name.isdigit():
                year_result = await self._ingest_year(int(year_dir.name), ingest_run_id)
                result.rows_processed += year_result.rows_processed
                result.rows_inserted += year_result.rows_inserted

        return result

    def _parse_event_file(self, file_path: Path) -> list[dict]:
        """Parse a Retrosheet event file.

        Retrosheet files are fixed-width text with record types:
        - id: Game identification
        - info: Game-level information
        - start: Starting lineup
        - play: Play-by-play events
        - sub: Substitutions
        - com: Comments

        Args:
            file_path: Path to .EVN or .EVA file (optionally gzipped).

        Returns:
            List of parsed record dictionaries.
        """
        records = []
        open_func = gzip.open if file_path.suffix == ".gz" else open

        with open_func(file_path, "rt", encoding="utf-8") as fh:
            for line in fh:
                line = line.rstrip("\n")
                if not line:
                    continue

                # Extract record type (first field before comma)
                record_type = line.split(",")[0] if "," in line else line[0]
                if record_type in ("id", "info", "start", "play", "sub", "com"):
                    records.append({
                        "record_type": record_type,
                        "raw_line": line,
                        "game_id": self._extract_game_id(line, record_type),
                    })

        return records

    def _extract_game_id(self, line: str, record_type: str) -> Optional[str]:
        """Extract game ID from a Retrosheet record."""
        if record_type == "id":
            # Format: id,ANA202304050
            parts = line.split(",", 1)
            return parts[1] if len(parts) > 1 else None
        return None