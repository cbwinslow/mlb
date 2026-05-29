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
from baseball.ingestion.engine import IngestEngine
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
        self.engine = IngestEngine(pool)

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

    async def _ingest_schedule(
        self, season: Optional[int], ingest_run_id: UUID
    ) -> IngestResult:
        """Ingest schedule data from ESPN."""
        result = IngestResult()

        url = f"{self.BASE_URL}/teams"
        data = await HistoricalLoaderFactory.fetch_api_json_stream(url)

        # Extract schedule from teams data
        teams = data.get("teams", [])
        result.rows_processed = len(teams)

        async with self.pool.connection() as conn:
            # Create request record for this ingestion
            request_result = await conn.execute(
                """
                INSERT INTO raw_espn.request (
                    raw_espn_request_id, ingest_run_id, source_endpoint_id,
                    request_url, requested_at
                ) VALUES (
                    gen_random_uuid(), %s, (SELECT source_endpoint_id FROM meta.source_endpoint WHERE endpoint_code = 'espn'),
                    %s, NOW()
                )
                RETURNING raw_espn_request_id
                """,
                (ingest_run_id, url),
            )
            request_id = (await request_result.fetchone())[0]

            for team in teams:
                team_schedule = team.get("schedule", {})
                # ESPN API returns schedule entries; we need to iterate them
                schedule_entries = (
                    team_schedule.get("entries", [team_schedule])
                    if isinstance(team_schedule, dict)
                    else []
                )
                for entry in schedule_entries:
                    await conn.execute(
                        """
                        INSERT INTO raw_espn.schedule (
                            raw_espn_schedule_id, raw_espn_request_id, season, game_date, home_team_id,
                            away_team_id, venue_id, game_type, status, raw_schedule_json
                        ) VALUES (
                            gen_random_uuid(), %s, %s, %s, %s, %s, %s, %s, %s
                        )
                        """,
                        (
                            request_id,
                            season,
                            entry.get("date"),
                            entry.get("homeTeam", {}).get("id")
                            if isinstance(entry.get("homeTeam"), dict)
                            else entry.get("homeTeam", {}).get("team", {}).get("id"),
                            entry.get("awayTeam", {}).get("id")
                            if isinstance(entry.get("awayTeam"), dict)
                            else entry.get("awayTeam", {}).get("team", {}).get("id"),
                            entry.get("venue", {}).get("id")
                            if isinstance(entry.get("venue"), dict)
                            else None,
                            entry.get("gameType"),
                            entry.get("status"),
                            json.dumps(entry),
                        ),
                    )
            await conn.commit()

        result.rows_inserted = result.rows_processed
        return result

    async def _ingest_scores(
        self, game_date: date, ingest_run_id: UUID
    ) -> IngestResult:
        """Ingest scores for a specific date."""
        result = IngestResult()

        url = f"{self.BASE_URL}/scoreboard"
        params = {"dates": game_date.isoformat()}

        data = await HistoricalLoaderFactory.fetch_api_json_stream(url, params=params)
        events = data.get("events", [])
        result.rows_processed = len(events)

        async with self.pool.connection() as conn:
            # Create request record for this ingestion
            request_result = await conn.execute(
                """
                INSERT INTO raw_espn.request (
                    raw_espn_request_id, ingest_run_id, source_endpoint_id,
                    request_url, request_params, requested_at
                ) VALUES (
                    gen_random_uuid(), %s, (SELECT source_endpoint_id FROM meta.source_endpoint WHERE endpoint_code = 'espn'),
                    %s, %s, NOW()
                )
                RETURNING raw_espn_request_id
                """,
                (ingest_run_id, url, json.dumps(params)),
            )
            request_id = (await request_result.fetchone())[0]

            for event in events:
                # Find home and away teams from competitors
                competitions = event.get("competitions", [])
                if not competitions:
                    continue
                competitors = competitions[0].get("competitors", [])
                home_team = next(
                    (c for c in competitors if c.get("homeAway") == "home"), {}
                )
                away_team = next(
                    (c for c in competitors if c.get("homeAway") == "away"), {}
                )
                home_score = home_team.get("score")
                away_score = away_team.get("score")

                await conn.execute(
                    """
                    INSERT INTO raw_espn.scores (
                        raw_espn_scores_id, raw_espn_request_id, game_date, game_pk, home_team_id,
                        away_team_id, home_score, away_score, status, quarter_scores, raw_scores_json
                    ) VALUES (
                        gen_random_uuid(), %s, %s, %s, %s, %s, %s, %s, %s, %s
                    )
                    """,
                    (
                        request_id,
                        game_date,
                        event.get("id"),
                        home_team.get("id"),
                        away_team.get("id"),
                        int(home_score) if home_score else None,
                        int(away_score) if away_score else None,
                        event.get("status", {}).get("type", {}).get("description"),
                        None,  # quarter_scores - would need more parsing
                        json.dumps(event),
                    ),
                )
            await conn.commit()

        result.rows_inserted = result.rows_processed
        return result

    async def _ingest_standings(
        self, season: Optional[int], ingest_run_id: UUID
    ) -> IngestResult:
        """Ingest standings data from ESPN."""
        result = IngestResult()

        url = f"{self.BASE_URL}/standings"
        data = await HistoricalLoaderFactory.fetch_api_json_stream(url)

        # Standings are typically one record per season
        result.rows_processed = 1

        async with self.pool.connection() as conn:
            # Create request record for this ingestion
            request_result = await conn.execute(
                """
                INSERT INTO raw_espn.request (
                    raw_espn_request_id, ingest_run_id, source_endpoint_id,
                    request_url, requested_at
                ) VALUES (
                    gen_random_uuid(), %s, (SELECT source_endpoint_id FROM meta.source_endpoint WHERE endpoint_code = 'espn'),
                    %s, NOW()
                )
                RETURNING raw_espn_request_id
                """,
                (ingest_run_id, url),
            )
            request_id = (await request_result.fetchone())[0]

            await conn.execute(
                """
                INSERT INTO raw_espn.standings (
                    raw_espn_request_id, season, standings_json
                ) VALUES (
                    %s, %s, %s
                )
                """,
                (request_id, season, json.dumps(data)),
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
