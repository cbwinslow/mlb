"""baseball.ingestion.statcast — Statcast pitch telemetry ingester.

Ingests Statcast data via pybaseball into raw_statcast schema,
then processes through util.ingest_statcast_play() to core tables.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from datetime import date
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
        workspace_id: Optional[UUID] = None,
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

    async def _get_endpoint_if_exists(self, endpoint_code: str) -> int | None:
        """Get source_endpoint_id if it exists."""
        async with self.pool.connection() as conn:
            result = await conn.execute(
                "SELECT source_endpoint_id FROM meta.source_endpoint WHERE endpoint_code = %s",
                (endpoint_code,),
            )
            row = await result.fetchone()
            return row[0] if row else None

    async def _get_source_endpoint_id(self, endpoint_code: str) -> int:
        """Get source_endpoint_id for tracking, trying both 'statcast' and 'search_csv'."""
        # First try statcast, then fall back to search_csv
        for code in [endpoint_code, "search_csv", "statcast"]:
            result = await self._get_endpoint_if_exists(code)
            if result:
                return result
        # Create if neither exists
        return await super()._get_source_endpoint_id("search_csv")

    async def ingest(
        self,
        start_date: Optional[date] = None,
        end_date: Optional[date] = None,
        season: Optional[int] = None,
        process_to_core: bool = False,
    ) -> IngestResult:
        """Ingest Statcast data.

        Args:
            start_date: Start date (YYYY-MM-DD).
            end_date: End date (YYYY-MM-DD).
            season: Season year (alternative to date range).
            process_to_core: Whether to process raw data to core tables.

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

        result.ingest_run_id = ingest_run_id

        try:
            if season:
                inserted = await self._ingest_season(season, ingest_run_id)
            elif start_date and end_date:
                inserted = await self._ingest_range(start_date, end_date, ingest_run_id)
            else:
                raise ValueError(
                    "Either season or start_date/end_date must be provided"
                )

            result.rows_inserted = inserted

            if process_to_core:
                result.rows_processed = await self._process_to_core(ingest_run_id)

            await self._complete_ingest_run(ingest_run_id, "succeeded")
        except Exception as e:
            log.error("Statcast ingestion failed: %s", e)
            await self._complete_ingest_run(ingest_run_id, "failed", str(e))
            result.errors += 1

        result.duration_seconds = time.time() - start_time
        return result

    async def _ingest_season(self, season: int, ingest_run_id: UUID) -> int:
        """Ingest all Statcast data for a season."""
        # Statcast season runs roughly March-October
        start_dt = date(season, 3, 1)
        end_dt = date(season, 10, 31)
        return await self._ingest_range(start_dt, end_dt, ingest_run_id)

    async def _create_search_file(
        self,
        ingest_run_id: UUID,
        start_date: date,
        end_date: date,
    ) -> UUID:
        """Create a search_file record for this Statcast extraction."""
        async with self.pool.connection() as conn:
            result = await conn.execute(
                """
                INSERT INTO raw_statcast.search_file (
                    ingest_run_id,
                    query_start_date, query_end_date,
                    query_params, export_source
                )
                VALUES (%(ingest_run_id)s, %(start_date)s,
                    %(end_date)s, %(params)s, 'pybaseball')
                RETURNING statcast_search_file_id
                """,
                {
                    "ingest_run_id": ingest_run_id,
                    "start_date": start_date,
                    "end_date": end_date,
                    "params": json.dumps({"source": "pybaseball"}),
                },
            )
            row = await result.fetchone()
            return row[0]

    async def _ingest_range(
        self,
        start_date: date,
        end_date: date,
        ingest_run_id: UUID,
    ) -> int:
        """Ingest Statcast data for a date range."""
        # Fetch via pybaseball
        try:
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

        if df is None or df.empty:
            log.warning("No data returned for date range %s to %s", start_date, end_date)
            return 0

        # Create search_file record for tracking
        search_file_id = await self._create_search_file(ingest_run_id, start_date, end_date)

        # Add statcast_search_file_id column to the dataframe for FK
        df["statcast_search_file_id"] = str(search_file_id)

        # Add ingest_run_id column to the dataframe
        df["ingest_run_id"] = str(ingest_run_id)

        # Save to CSV for bulk loading
        csv_path = self.data_dir / f"statcast_{start_date}_{end_date}.csv"
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(csv_path, index=False)

        # Bulk load via COPY - specify columns explicitly for mapping
        columns = df.columns.tolist()
        rows_loaded = await self.engine.bulk_load_raw_csv(
            "raw_statcast.pitch",
            csv_path,
            columns=columns,
        )

        return rows_loaded

    async def _process_to_core(self, ingest_run_id: UUID) -> int:
        """Process raw Statcast data to core tables.

        Calls util.ingest_statcast_play() for each row.
        Returns count of processed rows.
        """
        processed = 0
        team_cache: dict[str, int] = {}

        async with self.pool.connection() as conn:
            # Get all raw statcast rows with all columns for complete field coverage
            result = await conn.execute(
                """
                SELECT *
                FROM raw_statcast.pitch
                WHERE ingest_run_id = %s
                """,
                (ingest_run_id,),
            )
            rows = await result.fetchall()
            columns = [desc[0] for desc in result.description]

            # Build team cache for all unique team codes in this batch
            home_idx = columns.index("home_team")
            away_idx = columns.index("away_team")
            for row in rows:
                for team_code in [str(row[home_idx]), str(row[away_idx])]:
                    if team_code and team_code not in team_cache:
                        team_result = await conn.execute(
                            "SELECT team_id FROM core.team WHERE statcast_team_id = %s",
                            (team_code,),
                        )
                        team_row = await team_result.fetchone()
                        team_cache[team_code] = team_row[0] if team_row else None

            for row in rows:
                row_dict = dict(zip(columns, row))
                
                home_team_code = str(row_dict.get("home_team", ""))
                away_team_code = str(row_dict.get("away_team", ""))
                
                await conn.execute(
                    """
                    SELECT util.ingest_statcast_play(
                        %(game_pk)s, %(at_bat_number)s, %(pitch_number)s,
                        %(batter_id)s, %(pitcher_id)s, %(inning)s,
                        %(half_inning)s, %(outs_before)s, %(pa_sequence_order)s,
                        %(event_result_code)s, %(data_source_lineage)s,
                        %(workspace_id)s, %(balls_before)s, %(strikes_before)s,
                        %(pitch_type)s, %(pitch_call)s, %(release_velocity)s,
                        %(spin_rate)s, %(vert_break)s, %(horiz_break)s,
                        %(plate_x)s, %(plate_z)s, %(game_date)s,
                        %(home_team_code)s, %(away_team_code)s,
                        %(venue_id)s, %(home_team_id)s, %(away_team_id)s,
                        %(hit_location)s, %(hit_coordinate_x)s, %(hit_coordinate_y)s,
                        %(launch_speed)s, %(launch_angle)s, %(zone)s,
                        %(arm_angle)s, %(effective_speed)s, %(spin_axis)s,
                        %(bat_speed)s, %(swing_length)s
                    )
                    """,
                    {
                        "game_pk": row_dict.get("game_pk"),
                        "at_bat_number": row_dict.get("at_bat_number"),
                        "pitch_number": row_dict.get("pitch_number"),
                        "batter_id": row_dict.get("batter"),
                        "pitcher_id": row_dict.get("pitcher"),
                        "inning": row_dict.get("inning"),
                        "half_inning": "T" if row_dict.get("inning_topbot") == "Top" else "B",
                        "outs_before": row_dict.get("outs_when_up"),
                        "pa_sequence_order": row_dict.get("at_bat_number"),
                        "event_result_code": row_dict.get("events") or "unknown",
                        "data_source_lineage": "statcast",
                        "workspace_id": self.workspace_id,
                        "balls_before": row_dict.get("balls"),
                        "strikes_before": row_dict.get("strikes"),
                        "pitch_type": row_dict.get("pitch_type"),
                        "pitch_call": (row_dict.get("type") or "X")[0] if row_dict.get("type") else "X",
                        "release_velocity": row_dict.get("release_speed"),
                        "spin_rate": row_dict.get("release_spin_rate"),
                        "vert_break": row_dict.get("pfx_z"),
                        "horiz_break": row_dict.get("pfx_x"),
                        "plate_x": row_dict.get("plate_x"),
                        "plate_z": row_dict.get("plate_z"),
                        "game_date": row_dict.get("game_date"),
                        "home_team_code": home_team_code,
                        "away_team_code": away_team_code,
                        "venue_id": None,
                        "home_team_id": team_cache.get(home_team_code, None) if home_team_code else None,
                        "away_team_id": team_cache.get(away_team_code, None) if away_team_code else None,
                        "hit_location": row_dict.get("hit_location"),
                        "hit_coordinate_x": row_dict.get("hc_x"),
                        "hit_coordinate_y": row_dict.get("hc_y"),
                        "launch_speed": row_dict.get("launch_speed"),
                        "launch_angle": row_dict.get("launch_angle"),
                        "zone": row_dict.get("zone"),
                        "arm_angle": row_dict.get("arm_angle"),
                        "effective_speed": row_dict.get("effective_speed"),
                        "spin_axis": row_dict.get("spin_axis"),
                        "bat_speed": row_dict.get("bat_speed"),
                        "swing_length": row_dict.get("swing_length"),
                    },
                )
                processed += 1

            await conn.commit()

        return processed

    def _to_lahman_code(self, team_code: str) -> str:
        """Convert Statcast team code to Lahman team code."""
        statcast_to_lahman = {
            "NYY": "NYA", "LAD": "LAN", "CHC": "CHN", "CHW": "CHA", "KCR": "KCA",
            "SFG": "SFN", "STL": "SLN", "SDP": "SDN", "LAA": "ANA", "MIA": "FLA",
            "TBR": "TBA", "WSN": "WAS",
        }
        return statcast_to_lahman.get(team_code, team_code)


class StatcastFullIngester(StatcastIngester):
    """Ingester for full Statcast historical backfill.

    Ingests all Statcast data from 2015-present in chunks.
    """

    async def ingest_all(self, process_to_core: bool = False, max_concurrent: int = 3) -> IngestResult:
        """Ingest all Statcast data from 2015-present with parallel processing.

        Statcast launched in 2015 and runs March-October each season.
        
        Args:
            process_to_core: Whether to process raw data to core tables after ingest.
            max_concurrent: Maximum number of concurrent seasons to process (rate-limit friendly).
        """
        start_time = time.time()
        total_result = IngestResult()

        current_year = date.today().year
        seasons = list(range(2015, current_year + 1))
        semaphore = asyncio.Semaphore(max_concurrent)

        async def ingest_season(season: int) -> IngestResult:
            async with semaphore:
                log.info("Ingesting Statcast season %d", season)
                result = await self.ingest(season=season, process_to_core=process_to_core)
                # Rate limiting between seasons
                await asyncio.sleep(0.1)
                return result

        # Process seasons in parallel batches
        tasks = [ingest_season(season) for season in seasons]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        for r in results:
            if isinstance(r, IngestResult):
                total_result.rows_inserted += r.rows_inserted
                total_result.rows_processed += r.rows_processed
                total_result.duration_seconds += r.duration_seconds
            elif isinstance(r, Exception):
                log.warning("Season ingest failed: %s", r)

        total_result.duration_seconds = time.time() - start_time
        return total_result