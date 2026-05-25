"""baseball.ingestion.loaders — data loading utilities.

Provides HistoricalLoaderFactory for streaming CSV files and fetching
API JSON responses efficiently.
"""

from __future__ import annotations

import csv
from pathlib import Path
from typing import Iterator, Optional

import aiohttp


class HistoricalLoaderFactory:
    """Factory for loading historical data via CSV streaming and API fetching."""

    @staticmethod
    def stream_csv_file(
        file_path: Path,
        chunk_size: int = 10000,
        encoding: str = "utf-8",
    ) -> Iterator[list[dict]]:
        """Stream a CSV file in chunks for memory-efficient processing.

        Args:
            file_path: Path to the CSV file
            chunk_size: Number of rows per chunk
            encoding: File encoding (default utf-8)

        Yields:
            Lists of row dictionaries, each representing one CSV row
        """
        with file_path.open(newline="", encoding=encoding) as fh:
            reader = csv.DictReader(fh)
            chunk = []
            for row in reader:
                chunk.append(row)
                if len(chunk) >= chunk_size:
                    yield chunk
                    chunk = []
            if chunk:
                yield chunk

    @staticmethod
    async def fetch_api_json_stream(
        url: str,
        params: Optional[dict] = None,
        headers: Optional[dict] = None,
        timeout: float = 30.0,
        session: Optional[aiohttp.ClientSession] = None,
    ) -> dict:
        """Fetch JSON from an API endpoint.

        Args:
            url: API endpoint URL
            params: Query parameters
            headers: Request headers
            timeout: Request timeout in seconds
            session: Optional aiohttp session to reuse

        Returns:
            Parsed JSON response as dictionary
        """
        close_session = False
        if session is None:
            session = aiohttp.ClientSession()
            close_session = True

        try:
            async with session.get(
                url,
                params=params,
                headers=headers,
                timeout=aiohttp.ClientTimeout(total=timeout),
            ) as response:
                response.raise_for_status()
                return await response.json()
        finally:
            if close_session:
                await session.close()

    @staticmethod
    async def fetch_paginated_json(
        url: str,
        params: Optional[dict] = None,
        headers: Optional[dict] = None,
        session: Optional[aiohttp.ClientSession] = None,
    ) -> list[dict]:
        """Fetch paginated JSON results, yielding each page.

        Handles APIs that use offset/limit, page/cursor, or similar pagination.

        Args:
            url: API endpoint URL
            params: Base query parameters
            headers: Request headers
            session: Optional aiohttp session

        Returns:
            Lists of items from each page
        """
        all_items = []
        offset = 0
        limit = 1000

        close_session = False
        if session is None:
            session = aiohttp.ClientSession()
            close_session = True

        try:
            while True:
                page_params = dict(params or {})
                page_params["offset"] = offset
                page_params["limit"] = limit

                async with session.get(
                    url, params=page_params, headers=headers
                ) as response:
                    response.raise_for_status()
                    data = await response.json()

                    items = data if isinstance(data, list) else data.get("items", [])
                    if not items:
                        break

                    all_items.extend(items)
                    if len(items) < limit:
                        break
                    offset += limit
        finally:
            if close_session:
                await session.close()

        return all_items
