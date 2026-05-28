"""baseball.ingestion.mlbam — MLB StatsAPI ingester.

Ingests data from MLB StatsAPI (schedule, teams, players, boxscores)
into raw_mlbapi schema.
"""

from __future__ import annotations

import json
import logging
import time
from datetime import date, datetime
from pathlib import Path
from typing import Optional
from uuid import UUID

from psycopg_pool import AsyncConnectionPool

from baseball.ingestion.base import BaseIngester, IngestResult
from baseball.ingestion.loaders import HistoricalLoaderFactory

log = logging.getLogger(__name__)


class MLBAMIngester(BaseIngester):
    """Ingester for MLB StatsAPI data.

    Handles:
    - Schedule data
    - Team rosters
    - Player information
    - Boxscores
    - Live game feeds
    """

    BASE_URL = "https://statsapi.mlb.com/api/v1"

    def __init__(
        self,
        pool: AsyncConnectionPool,
        workspace_id: UUID,
        data_dir: Optional[Path] = None,
    ):
        super().__init__(pool, workspace_id, "mlbapi")
        self.data_dir = data_dir or Path("data/mlbapi")

    async def validate(self) -> bool:
        """Validate that required tables exist."""
        async with self.pool.connection() as conn:
            result = await conn.execute(
                "SELECT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'raw_mlbapi' AND tablename = 'payload')"
            )
            return (await result.fetchone())[0]

    async def ingest(
        self,
        endpoint: Optional[str] = None,
        date_val: Optional[date] = None,
        season: Optional[int] = None,
    ) -> IngestResult:
        """Ingest MLB StatsAPI data.

        Args:
            endpoint: Specific endpoint to ingest (schedule, teams, people).
            date_val: Date for schedule endpoint.
            season: Season for seasonal data.

        Returns:
            IngestResult with counts.
        """
        start_time = time.time()
        result = IngestResult()

        endpoint_id = await self._get_source_endpoint_id("mlbapi")
        ingest_run_id = await self._create_ingest_run(
            endpoint_id,
            {"endpoint": endpoint, "date": date_val, "season": season},
        )

        try:
            if endpoint == "schedule" and date_val:
                result = await self._ingest_schedule(date_val, ingest_run_id)
            elif endpoint == "teams":
                result = await self._ingest_teams(ingest_run_id)
            elif endpoint == "people":
                result = await self._ingest_people(ingest_run_id)
            elif season:
                result = await self._ingest_season(season, ingest_run_id)
            else:
                result = await self._ingest_all(ingest_run_id)

            await self._complete_ingest_run(ingest_run_id, "succeeded")
        except Exception as e:
            log.error("MLBAM ingestion failed: %s", e)
            await self._complete_ingest_run(ingest_run_id, "failed", str(e))
            result.errors += 1

        result.duration_seconds = time.time() - start_time
        return result

    async def _ingest_schedule(self, game_date: date, ingest_run_id: UUID) -> IngestResult:
        """Ingest schedule for a specific date."""
        result = IngestResult()

        url = f"{self.BASE_URL}/schedule"
        params = {
            "sportId": 1,
            "date": game_date.isoformat(),
        }

        data = await HistoricalLoaderFactory.fetch_api_json_stream(url, params=params)
        result.rows_processed = len(data.get("dates", []))

        # Store in raw_mlbapi.request and payload
        async with self.pool.connection() as conn:
            # First insert into request table
            request_result = await conn.execute(
                """
                INSERT INTO raw_mlbapi.request (
                    mlbapi_request_id, ingest_run_id, source_endpoint_id,
                    request_url, request_method, request_params, requested_at
                ) VALUES (
                    gen_random_uuid(), %s, (SELECT source_endpoint_id FROM meta.source_endpoint WHERE endpoint_code = 'mlbapi'),
                    %s, 'GET', %s, NOW()
                )
                RETURNING mlbapi_request_id
                """,
                (ingest_run_id, url, json.dumps(params)),
            )
            request_id = (await request_result.fetchone())[0]

            # Then insert into payload with the request_id
            await conn.execute(
                """
                INSERT INTO raw_mlbapi.payload (
                    mlbapi_request_id, endpoint_code, endpoint_group,
                    response_json, created_at
                ) VALUES (
                    %s, 'schedule', 'schedule',
                    %s, NOW()
                )
                """,
                (request_id, json.dumps(data)),
            )
            await conn.commit()

        result.rows_inserted = 1
        return result

    async def _ingest_teams(self, ingest_run_id: UUID) -> IngestResult:
        """Ingest all MLB teams."""
        result = IngestResult()

        url = f"{self.BASE_URL}/teams"
        data = await HistoricalLoaderFactory.fetch_api_json_stream(url)
        result.rows_processed = len(data.get("teams", []))

        async with self.pool.connection() as conn:
            # First insert into request table
            request_result = await conn.execute(
                """
                INSERT INTO raw_mlbapi.request (
                    mlbapi_request_id, ingest_run_id, source_endpoint_id,
                    request_url, request_method, requested_at
                ) VALUES (
                    gen_random_uuid(), %s, (SELECT source_endpoint_id FROM meta.source_endpoint WHERE endpoint_code = 'mlbapi'),
                    %s, 'GET', NOW()
                )
                RETURNING mlbapi_request_id
                """,
                (ingest_run_id, url),
            )
            request_id = (await request_result.fetchone())[0]

            for team in data.get("teams", []):
                await conn.execute(
                    """
                    INSERT INTO raw_mlbapi.payload (
                        mlbapi_request_id, endpoint_code, endpoint_group,
                        team_id, response_json, created_at
                    ) VALUES (
                        %s, 'teams', 'teams',
                        %s, %s, NOW()
                    )
                    """,
                    (request_id, team.get("id"), json.dumps(team)),
                )
            await conn.commit()

        result.rows_inserted = result.rows_processed
        return result

    async def _ingest_people(self, ingest_run_id: UUID) -> IngestResult:
        """Ingest all MLB people (players, coaches, etc.)."""
        result = IngestResult()

        url = f"{self.BASE_URL}/people"
        data = await HistoricalLoaderFactory.fetch_paginated_json(url)
        result.rows_processed = len(data)

        async with self.pool.connection() as conn:
            # First insert into request table
            request_result = await conn.execute(
                """
                INSERT INTO raw_mlbapi.request (
                    mlbapi_request_id, ingest_run_id, source_endpoint_id,
                    request_url, request_method, requested_at
                ) VALUES (
                    gen_random_uuid(), %s, (SELECT source_endpoint_id FROM meta.source_endpoint WHERE endpoint_code = 'mlbapi'),
                    %s, 'GET', NOW()
                )
                RETURNING mlbapi_request_id
                """,
                (ingest_run_id, url),
            )
            request_id = (await request_result.fetchone())[0]

            for person in data:
                await conn.execute(
                    """
                    INSERT INTO raw_mlbapi.payload (
                        mlbapi_request_id, endpoint_code, endpoint_group,
                        person_id, response_json, created_at
                    ) VALUES (
                        %s, 'people', 'people',
                        %s, %s, NOW()
                    )
                    """,
                    (request_id, person.get("id"), json.dumps(person)),
                )
            await conn.commit()

        result.rows_inserted = result.rows_processed
        return result

    async def _ingest_season(self, season: int, ingest_run_id: UUID) -> IngestResult:
        """Ingest all data for a season."""
        result = IngestResult()

        # Ingest schedule for each day of the season
        start_date = date(season, 3, 1)
        end_date = date(season, 10, 31)

        current = start_date
        while current <= end_date:
            day_result = await self._ingest_schedule(current, ingest_run_id)
            result.rows_processed += day_result.rows_processed
            result.rows_inserted += day_result.rows_inserted
            current = date.fromordinal(current.toordinal() + 1)

        return result

    async def _ingest_all(self, ingest_run_id: UUID) -> IngestResult:
        """Ingest all available MLB StatsAPI data."""
        result = IngestResult()

        # Ingest teams first
        teams_result = await self._ingest_teams(ingest_run_id)
        result.rows_processed += teams_result.rows_processed
        result.rows_inserted += teams_result.rows_inserted

        # Ingest people
        people_result = await self._ingest_people(ingest_run_id)
        result.rows_processed += people_result.rows_processed
        result.rows_inserted += people_result.rows_inserted

        return result