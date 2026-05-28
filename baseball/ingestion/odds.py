"""baseball.ingestion.odds — Odds data ingester.

Ingests betting odds data into raw_odds schema.
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


class OddsIngester(BaseIngester):
    """Ingester for betting odds data.

    Fetches odds from various providers (The Odds API, etc.).
    """

    def __init__(
        self,
        pool: AsyncConnectionPool,
        workspace_id: UUID,
        data_dir: Optional[Path] = None,
        api_key: Optional[str] = None,
    ):
        super().__init__(pool, workspace_id, "odds")
        self.data_dir = data_dir or Path("data/odds")
        self.api_key = api_key

    async def validate(self) -> bool:
        """Validate that required tables exist."""
        async with self.pool.connection() as conn:
            result = await conn.execute(
                "SELECT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'raw_odds' AND tablename = 'market_lines')"
            )
            return (await result.fetchone())[0]

    async def ingest(
        self,
        season: Optional[int] = None,
        date_val: Optional[date] = None,
        sport: Optional[str] = "baseball",
    ) -> IngestResult:
        """Ingest odds data.

        Args:
            season: Season year (e.g., 2023).
            date_val: Date for odds data.
            sport: Sport key for odds API (default: baseball).

        Returns:
            IngestResult with counts.
        """
        start_time = time.time()
        result = IngestResult()

        endpoint_id = await self._get_source_endpoint_id("odds")
        ingest_run_id = await self._create_ingest_run(
            endpoint_id,
            {"season": season, "date": date_val, "sport": sport},
        )

        try:
            if date_val:
                result = await self._ingest_date(date_val, sport, ingest_run_id)
            elif season:
                result = await self._ingest_season(season, sport, ingest_run_id)
            else:
                result = await self._ingest_all(sport, ingest_run_id)

            await self._complete_ingest_run(ingest_run_id, "succeeded")
        except Exception as e:
            log.error("Odds ingestion failed: %s", e)
            await self._complete_ingest_run(ingest_run_id, "failed", str(e))
            result.errors += 1

        result.duration_seconds = time.time() - start_time
        return result

    async def _ingest_date(
        self,
        game_date: date,
        sport: str,
        ingest_run_id: UUID,
    ) -> IngestResult:
        """Ingest odds for a specific date."""
        result = IngestResult()

        if not self.api_key:
            raise ValueError("API key required for odds ingestion")

        url = "https://api.the-odds-api.com/v4/sports/{sport}/odds-history"
        params = {
            "apiKey": self.api_key,
            "date": game_date.isoformat(),
        }

        data = await HistoricalLoaderFactory.fetch_api_json_stream(url, params=params)
        result.rows_processed = len(data)

        async with self.pool.connection() as conn:
            for market in data:
                await conn.execute(
                    """
                    INSERT INTO raw_odds.market_lines (
                        odds_request_id, sport_key, game_date,
                        market_json, created_at
                    ) VALUES (
                        gen_random_uuid(), %s, %s,
                        %s, NOW()
                    )
                    """,
                    (sport, game_date, json.dumps(market)),
                )
            await conn.commit()

        result.rows_inserted = result.rows_processed
        return result

    async def _ingest_season(
        self,
        season: int,
        sport: str,
        ingest_run_id: UUID,
    ) -> IngestResult:
        """Ingest odds for an entire season."""
        result = IngestResult()

        # MLB season runs roughly March-October
        start_date = date(season, 3, 1)
        end_date = date(season, 10, 31)

        current = start_date
        while current <= end_date:
            date_result = await self._ingest_date(current, sport, ingest_run_id)
            result.rows_processed += date_result.rows_processed
            result.rows_inserted += date_result.rows_inserted
            current = date.fromordinal(current.toordinal() + 1)

        return result

    async def _ingest_all(self, sport: str, ingest_run_id: UUID) -> IngestResult:
        """Ingest all available odds data."""
        result = IngestResult()

        # Ingest current date
        today = date.today()
        date_result = await self._ingest_date(today, sport, ingest_run_id)
        result.rows_processed += date_result.rows_processed
        result.rows_inserted += date_result.rows_inserted

        return result