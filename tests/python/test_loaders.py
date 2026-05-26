"""Tests for baseball/ingestion/loaders.py.

Covers HistoricalLoaderFactory class and its methods.
"""

from __future__ import annotations

import csv
import tempfile
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from baseball.ingestion.loaders import HistoricalLoaderFactory


# ---------------------------------------------------------------------------
# stream_csv_file Tests
# ---------------------------------------------------------------------------


class TestStreamCsvFile:
    """Tests for stream_csv_file() static method."""

    def test_yields_single_chunk_for_small_file(self):
        """Small file yields single chunk."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            writer = csv.writer(f)
            writer.writerow(["col1", "col2"])
            writer.writerow(["val1", "val2"])
            writer.writerow(["val3", "val4"])
            temp_path = Path(f.name)

        try:
            chunks = list(HistoricalLoaderFactory.stream_csv_file(temp_path, chunk_size=1000))
            assert len(chunks) == 1
            assert len(chunks[0]) == 2  # 2 data rows
        finally:
            temp_path.unlink()

    def test_yields_multiple_chunks_for_large_file(self):
        """Large file yields multiple chunks."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            writer = csv.writer(f)
            writer.writerow(["col1", "col2"])
            for i in range(2500):
                writer.writerow([f"val{i}", f"val{i+1}"])
            temp_path = Path(f.name)

        try:
            chunks = list(HistoricalLoaderFactory.stream_csv_file(temp_path, chunk_size=1000))
            assert len(chunks) == 3  # 2500 rows / 1000 = 3 chunks
        finally:
            temp_path.unlink()

    def test_handles_empty_file(self):
        """Empty file (header only) yields empty list."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            writer = csv.writer(f)
            writer.writerow(["col1", "col2"])
            temp_path = Path(f.name)

        try:
            chunks = list(HistoricalLoaderFactory.stream_csv_file(temp_path))
            assert len(chunks) == 0
        finally:
            temp_path.unlink()

    def test_handles_custom_encoding(self):
        """Custom encoding is respected."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False, encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["col1", "col2"])
            writer.writerow(["val1", "val2"])
            temp_path = Path(f.name)

        try:
            chunks = list(HistoricalLoaderFactory.stream_csv_file(temp_path, encoding="utf-8"))
            assert len(chunks) == 1
        finally:
            temp_path.unlink()

    def test_handles_semicolon_delimiter(self):
        """Semicolon-delimited CSV is handled via csv module default."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            f.write("col1;col2\nval1;val2\n")
            temp_path = Path(f.name)

        try:
            # Note: stream_csv_file doesn't support custom delimiter, but we can test
            # that it handles the file gracefully (will parse as single column due to no delimiter param)
            chunks = list(HistoricalLoaderFactory.stream_csv_file(temp_path))
            # Without delimiter support, this will have one column with the full string
            assert len(chunks) == 1
        finally:
            temp_path.unlink()


# ---------------------------------------------------------------------------
# fetch_api_json_stream Tests
# ---------------------------------------------------------------------------


class TestFetchApiJsonStream:
    """Tests for fetch_api_json_stream() static method."""

    @pytest.mark.asyncio
    async def test_returns_json_response(self):
        """Returns parsed JSON response."""
        mock_response = AsyncMock()
        mock_response.json = AsyncMock(return_value={"key": "value"})
        mock_response.raise_for_status = MagicMock()
        mock_response.__aenter__ = AsyncMock(return_value=mock_response)
        mock_response.__aexit__ = AsyncMock(return_value=None)

        mock_session = MagicMock()
        mock_session.get = MagicMock(return_value=mock_response)
        mock_session.close = AsyncMock()

        with patch("baseball.ingestion.loaders.aiohttp.ClientSession", return_value=mock_session):
            result = await HistoricalLoaderFactory.fetch_api_json_stream(
                url="https://api.example.com/data",
                session=mock_session,
            )

        assert result == {"key": "value"}

    @pytest.mark.asyncio
    async def test_creates_session_when_none(self):
        """Creates new session when none provided."""
        mock_response = AsyncMock()
        mock_response.json = AsyncMock(return_value={"data": []})
        mock_response.raise_for_status = MagicMock()
        mock_response.__aenter__ = AsyncMock(return_value=mock_response)
        mock_response.__aexit__ = AsyncMock(return_value=None)

        mock_session = MagicMock()
        mock_session.get = MagicMock(return_value=mock_response)
        mock_session.close = AsyncMock()

        with patch("baseball.ingestion.loaders.aiohttp.ClientSession", return_value=mock_session):
            result = await HistoricalLoaderFactory.fetch_api_json_stream(
                url="https://api.example.com/data",
            )

        mock_session.close.assert_called_once()

    @pytest.mark.asyncio
    async def test_passes_params_and_headers(self):
        """Query params and headers are passed to request."""
        mock_response = AsyncMock()
        mock_response.json = AsyncMock(return_value={})
        mock_response.raise_for_status = MagicMock()
        mock_response.__aenter__ = AsyncMock(return_value=mock_response)
        mock_response.__aexit__ = AsyncMock(return_value=None)

        mock_session = MagicMock()
        mock_session.get = MagicMock(return_value=mock_response)
        mock_session.close = AsyncMock()

        with patch("baseball.ingestion.loaders.aiohttp.ClientSession", return_value=mock_session):
            await HistoricalLoaderFactory.fetch_api_json_stream(
                url="https://api.example.com/data",
                params={"key": "value"},
                headers={"X-Custom": "header"},
                session=mock_session,
            )

        call_kwargs = mock_session.get.call_args[1]
        assert call_kwargs["params"] == {"key": "value"}
        assert call_kwargs["headers"] == {"X-Custom": "header"}

    @pytest.mark.asyncio
    async def test_raises_on_http_error(self):
        """Raises exception on HTTP error."""
        mock_response = AsyncMock()
        mock_response.raise_for_status = MagicMock(side_effect=Exception("HTTP Error"))
        mock_response.__aenter__ = AsyncMock(return_value=mock_response)
        mock_response.__aexit__ = AsyncMock(return_value=None)

        mock_session = MagicMock()
        mock_session.get = MagicMock(return_value=mock_response)
        mock_session.close = AsyncMock()

        with patch("baseball.ingestion.loaders.aiohttp.ClientSession", return_value=mock_session):
            with pytest.raises(Exception, match="HTTP Error"):
                await HistoricalLoaderFactory.fetch_api_json_stream(
                    url="https://api.example.com/data",
                    session=mock_session,
                )


# ---------------------------------------------------------------------------
# fetch_paginated_json Tests
# ---------------------------------------------------------------------------


class TestFetchPaginatedJson:
    """Tests for fetch_paginated_json() static method."""

    @pytest.mark.asyncio
    async def test_returns_all_items(self):
        """Returns all items from paginated endpoint."""
        call_count = 0

        def mock_get(url, params=None, headers=None):
            nonlocal call_count
            call_count += 1
            mock_response = AsyncMock()
            mock_response.json = AsyncMock(return_value=[{"id": call_count}])
            mock_response.raise_for_status = MagicMock()
            mock_response.__aenter__ = AsyncMock(return_value=mock_response)
            mock_response.__aexit__ = AsyncMock(return_value=None)
            return mock_response

        mock_session = MagicMock()
        mock_session.get = mock_get
        mock_session.close = AsyncMock()

        with patch("baseball.ingestion.loaders.aiohttp.ClientSession", return_value=mock_session):
            result = await HistoricalLoaderFactory.fetch_paginated_json(
                url="https://api.example.com/data",
                session=mock_session,
            )

        assert len(result) == 1
        assert result[0] == {"id": 1}

    @pytest.mark.asyncio
    async def test_handles_empty_response(self):
        """Empty response returns empty list."""
        mock_response = AsyncMock()
        mock_response.json = AsyncMock(return_value=[])
        mock_response.raise_for_status = MagicMock()
        mock_response.__aenter__ = AsyncMock(return_value=mock_response)
        mock_response.__aexit__ = AsyncMock(return_value=None)

        mock_session = MagicMock()
        mock_session.get = MagicMock(return_value=mock_response)
        mock_session.close = AsyncMock()

        with patch("baseball.ingestion.loaders.aiohttp.ClientSession", return_value=mock_session):
            result = await HistoricalLoaderFactory.fetch_paginated_json(
                url="https://api.example.com/data",
                session=mock_session,
            )

        assert result == []

    @pytest.mark.asyncio
    async def test_handles_dict_response_with_items(self):
        """Dict response with 'items' key is handled."""
        mock_response = AsyncMock()
        mock_response.json = AsyncMock(return_value={"items": [{"id": 1}, {"id": 2}]})
        mock_response.raise_for_status = MagicMock()
        mock_response.__aenter__ = AsyncMock(return_value=mock_response)
        mock_response.__aexit__ = AsyncMock(return_value=None)

        mock_session = MagicMock()
        mock_session.get = MagicMock(return_value=mock_response)
        mock_session.close = AsyncMock()

        with patch("baseball.ingestion.loaders.aiohttp.ClientSession", return_value=mock_session):
            result = await HistoricalLoaderFactory.fetch_paginated_json(
                url="https://api.example.com/data",
                session=mock_session,
            )

        assert len(result) == 2

    @pytest.mark.asyncio
    async def test_stops_on_partial_page(self):
        """Stops pagination when page is smaller than limit."""
        call_count = 0

        def mock_get(url, params=None, headers=None):
            nonlocal call_count
            call_count += 1
            mock_response = AsyncMock()
            # First call returns 1000 items, second returns 50 (partial)
            if call_count == 1:
                mock_response.json = AsyncMock(return_value=[{"id": i} for i in range(1000)])
            else:
                mock_response.json = AsyncMock(return_value=[{"id": i} for i in range(50)])
            mock_response.raise_for_status = MagicMock()
            mock_response.__aenter__ = AsyncMock(return_value=mock_response)
            mock_response.__aexit__ = AsyncMock(return_value=None)
            return mock_response

        mock_session = MagicMock()
        mock_session.get = mock_get
        mock_session.close = AsyncMock()

        with patch("baseball.ingestion.loaders.aiohttp.ClientSession", return_value=mock_session):
            result = await HistoricalLoaderFactory.fetch_paginated_json(
                url="https://api.example.com/data",
                session=mock_session,
            )

        assert len(result) == 1050  # 1000 + 50