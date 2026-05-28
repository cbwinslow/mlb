"""baseball.ingestion.espn — ESPN data ingester.

Ingests ESPN data (schedule, scores, standings) into raw_espn schema.
"""

from __future__ import annotations

import json
import logging
import time
from datetime import date
from pathlib import Path
from typing import Optional
from uuid import UUID

from psycopg_pool import AsyncConnectionPool

from baseball.ingestion.base import BaseIngester, IngestResult
from baseball.ingestion.loaders import HistoricalLoaderFactory

log = logging.getLogger(__name__)


class ESPNIngester(BaseIngester):
    """Ingester for ESPN baseball data.

    Fetches schedule, scores, and standings from ESPN.
    """

    BASE_URL = "https://site.api.espn.com/apis/site/v2/sports/baseball/mlb"

    def __init__(
        self,
        pool: AsyncConnectionPool,
        workspace_id: UUID,
        data_dir: Optional[Path] = None,
    ):
        super().__init__(pool, workspace_id, "espn")
        self.data_dir = data_dir or Path("data/espn")

    async def validate(self) -> bool:
        """Validate that required tables exist."""
        async with self.pool.connection() as conn:
            result = await conn.execute(
                "SELECT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'raw_espn' AND tablename = 'schedule')"
            )
            return (await result.fetchone())[0]

    async def ingest(
        self,
        season: Optional[int] = None,
        date_val: Optional[date] = None,
        data_type: Optional[str] = None,
    ) -> IngestResult:
        """Ingest ESPN data.

        Args:
            season: Season year (e.g., 2023).
            date_val: Date for schedule/scores.
            data_type: Type of data (schedule, scores, standings).

        Returns:
            IngestResult with counts.
        """
        start_time = time.time()
        result = IngestResult()

        endpoint_id = await self._get_source_endpoint_id("espn")
        ingest_run_id = await self._create_ingest_run(
            endpoint_id,
            {"season": season, "date": date_val, "data_type": data_type},
        )

        try:
            if data_type == "schedule":
                result = await self._ingest_schedule(season, ingest_run_id)
            elif data_type == "scores":
                result = await self._ingest_scores(date_val, ingest_run_id)
            elif data_type == "standings":
                result = await self._ingest_standings(season, ingest_run_id)
            elif season:
                result = await self._ingest_season(season, ingest_run_id)
            else:
                result = await self._ingest_all(ingest_run_id)

            await self._complete_ingest_run(ingest_run_id, "succeeded")
        except Exception as e:
            log.error("ESPN ingestion failed: %s", e)
            await self._complete_ingest_run(ingest_run_id, "failed", str(e))
            result.errors += 1

        result.duration_seconds = time.time() - start_time
        return result

    async def _ingest_schedule(self, season: Optional[int], ingest_run_id: UUID) -> IngestResult:
        """Ingest schedule data from ESPN."""
        result = IngestResult()

        url = f"{self.BASE_URL}/teams"
        data = await HistoricalLoaderFactory.fetch_api_json_stream(url)

        # Extract schedule from teams data
        teams = data.get("teams", [])
        result.rows_processed = len(teams)

        async with self.pool.connection() as conn:
            for team in teams:
                await conn.execute(
                    """
                    INSERT INTO raw_espn.schedule (
                        espn_team_id, season, schedule_json, created_at
                    ) VALUES (
                        %s, %s, %s, NOW()
                    )
                    """,
                    (team.get("id"), season, json.dumps(team.get("schedule", {}))),
                )
            await conn.commit()

        result.rows_inserted = result.rows_processed
        return result

    async def _ingest_scores(self, game_date: date, ingest_run_id: UUID) -> IngestResult:
        """Ingest scores for a specific date."""
        result = IngestResult()

        url = f"{self.BASE_URL}/scoreboard"
        params = {"dates": game_date.isoformat()}

        data = await HistoricalLoaderFactory.fetch_api_json_stream(url, params=params)
        events = data.get("events", [])
        result.rows_processed = len(events)

        async with self.pool.connection() as conn:
            for event in events:
                await conn.execute(
                    """
                    INSERT INTO raw_espn.scores (
                        espn_event_id, game_date, score_json, created_at
                    ) VALUES (
                        %s, %s, %s, NOW()
                    )
                    """,
                    (event.get("id"), game_date, json.dumps(event)),
                )
            await conn.commit()

        result.rows_inserted = result.rows_processed
        return result

    async def _ingest_standings(self, season: Optional[int], ingest_run_id: UUID) -> IngestResult:
        """Ingest standings data from ESPN."""
        result = IngestResult()

        url = f"{self.BASE_URL}/standings"
        data = await HistoricalLoaderFactory.fetch_api_json_stream(url)

        # Standings are typically one record per season
        result.rows_processed = 1

        async with self.pool.connection() as conn:
            await conn.execute(
                """
                INSERT INTO raw_espn.standings (
                    season, standings_json, created_at
                ) VALUES (
                    %s, %s, NOW()
                )
                """,
                (season, json.dumps(data)),
            )
            await conn.commit()

        result.rows_inserted = 1
        return result

    async def _ingest_season(self, season: int, ingest_run_id: UUID) -> IngestResult:
        """Ingest all ESPN data for a season."""
        result = IngestResult()

        # Ingest schedule
        schedule_result = await self._ingest_schedule(season, ingest_run_id)
        result.rows_processed += schedule_result.rows_processed
        result.rows_inserted += schedule_result.rows_inserted

        # Ingest standings
        standings_result = await self._ingest_standings(season, ingest_run_id)
        result.rows_processed += standings_result.rows_processed
        result.rows_inserted += standings_result.rows_inserted

        return result

    async def _ingest_all(self, ingest_run_id: UUID) -> IngestResult:
        """Ingest all available ESPN data."""
        result = IngestResult()

        # Ingest current season schedule and standings
        schedule_result = await self._ingest_schedule(None, ingest_run_id)
        result.rows_processed += schedule_result.rows_processed
        result.rows_inserted += schedule_result.rows_inserted

        standings_result = await self._ingest_standings(None, ingest_run_id)
        result.rows_processed += standings_result.rows_processed
        result.rows_inserted += standings_result.rows_inserted

        return result