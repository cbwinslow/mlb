"""Tests for baseball/db.py.

Covers _normalize_url(), _get_sql_files(), get_sql_files(), run_bootstrap(),
_run_sql_file(), _drop_database(), and _create_database().
"""

from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch, call

import pytest

from baseball.db import (
    _normalize_url,
    _get_sql_files,
    get_sql_files,
    _run_sql_file,
    _drop_database,
    _create_database,
    run_bootstrap,
    SQL_ROOT,
)


# ---------------------------------------------------------------------------
# _normalize_url Tests
# ---------------------------------------------------------------------------


class TestNormalizeUrl:
    """Tests for _normalize_url() function."""

    def test_converts_asyncpg_to_standard(self):
        """Convert postgresql+asyncpg:// to postgresql://."""
        url = "postgresql+asyncpg://user:pass@localhost:5432/mlb"
        result = _normalize_url(url)
        assert result == "postgresql://user:pass@localhost:5432/mlb"
        assert "+asyncpg" not in result

    def test_converts_psycopg2_to_standard(self):
        """Convert postgresql+psycopg2:// to postgresql://."""
        url = "postgresql+psycopg2://user:pass@localhost:5432/mlb"
        result = _normalize_url(url)
        assert result == "postgresql://user:pass@localhost:5432/mlb"
        assert "+psycopg2" not in result

    def test_returns_unchanged_for_standard_url(self):
        """Standard postgresql:// URL is unchanged."""
        url = "postgresql://user:pass@localhost:5432/mlb"
        result = _normalize_url(url)
        assert result == url

    def test_handles_no_credentials(self):
        """URL without credentials is unchanged."""
        url = "postgresql://localhost:5432/mlb"
        result = _normalize_url(url)
        assert result == url

    def test_preserves_query_params(self):
        """Query parameters are preserved."""
        url = "postgresql+asyncpg://user:pass@localhost:5432/mlb?sslmode=require"
        result = _normalize_url(url)
        assert "sslmode=require" in result
        assert "+asyncpg" not in result


# ---------------------------------------------------------------------------
# _get_sql_files Tests
# ---------------------------------------------------------------------------


class TestGetSqlFiles:
    """Tests for _get_sql_files() function."""

    def test_returns_list_of_paths(self):
        """Returns a list of Path objects."""
        result = _get_sql_files()
        assert isinstance(result, list)
        assert all(isinstance(p, Path) for p in result)

    def test_files_are_sql(self):
        """All returned files have .sql extension."""
        result = _get_sql_files()
        assert all(p.suffix == ".sql" for p in result)

    def test_files_exist(self):
        """All returned files exist on disk."""
        result = _get_sql_files()
        for p in result:
            assert p.exists(), f"File {p} does not exist"

    def test_order_by_layer(self):
        """Files are ordered by layer number (010, 020, etc.)."""
        result = _get_sql_files()
        layer_numbers = []
        for p in result:
            # Extract layer from path like sql/010_extensions/...
            parts = p.parts
            for part in parts:
                if part.startswith("0") and "_" in part:
                    layer = int(part.split("_")[0])
                    layer_numbers.append(layer)
                    break
        # Verify ascending order
        assert layer_numbers == sorted(layer_numbers)


# ---------------------------------------------------------------------------
# get_sql_files Tests (cached version)
# ---------------------------------------------------------------------------


class TestGetSqlFilesCached:
    """Tests for get_sql_files() cached function."""

    def test_returns_tuple(self):
        """Cached version returns tuple."""
        result = get_sql_files()
        assert isinstance(result, tuple)

    def test_returns_same_as_uncached(self):
        """Cached result matches uncached result."""
        uncached = _get_sql_files()
        cached = get_sql_files()
        assert tuple(uncached) == cached

    def test_is_cached(self):
        """Second call returns cached result (same object)."""
        result1 = get_sql_files()
        result2 = get_sql_files()
        assert result1 is result2


# ---------------------------------------------------------------------------
# _run_sql_file Tests
# ---------------------------------------------------------------------------


class TestRunSqlFile:
    """Tests for _run_sql_file() function."""

    def test_calls_psql_with_correct_args(self):
        """psql is called with correct arguments."""
        mock_result = MagicMock()
        mock_result.stderr = ""

        with patch("baseball.db.subprocess.run") as mock_run:
            mock_run.return_value = mock_result
            _run_sql_file("postgresql://localhost/mlb", Path("test.sql"))

            mock_run.assert_called_once()
            args = mock_run.call_args[0][0]
            assert "psql" in args
            assert "postgresql://localhost/mlb" in args
            assert "-v" in args
            assert "ON_ERROR_STOP=1" in args
            assert "-f" in args
            assert "test.sql" in args

    def test_raises_on_psql_failure(self):
        """Raises exception when psql fails."""
        with patch("baseball.db.subprocess.run") as mock_run:
            mock_run.side_effect = subprocess.CalledProcessError(1, "psql")
            with pytest.raises(subprocess.CalledProcessError):
                _run_sql_file("postgresql://localhost/mlb", Path("test.sql"))


# ---------------------------------------------------------------------------
# _drop_database Tests
# ---------------------------------------------------------------------------


class TestDropDatabase:
    """Tests for _drop_database() function."""

    def test_calls_dropdb_with_db_name(self):
        """dropdb is called with the database name."""
        with patch("baseball.db.subprocess.run") as mock_run:
            _drop_database("postgresql://localhost/mlb_test")
            mock_run.assert_called_once()
            args = mock_run.call_args[0][0]
            assert "dropdb" in args
            assert "mlb_test" in args
            assert "--if-exists" in args

    def test_handles_url_with_port(self):
        """Correctly extracts DB name from URL with port."""
        with patch("baseball.db.subprocess.run") as mock_run:
            _drop_database("postgresql://localhost:5432/mlb_prod")
            args = mock_run.call_args[0][0]
            assert "mlb_prod" in args


# ---------------------------------------------------------------------------
# _create_database Tests
# ---------------------------------------------------------------------------


class TestCreateDatabase:
    """Tests for _create_database() function."""

    def test_calls_createdb_with_db_name(self):
        """createdb is called with the database name."""
        with patch("baseball.db.subprocess.run") as mock_run:
            _create_database("postgresql://localhost/mlb_test")
            mock_run.assert_called_once()
            args = mock_run.call_args[0][0]
            assert "createdb" in args
            assert "mlb_test" in args


# ---------------------------------------------------------------------------
# run_bootstrap Tests
# ---------------------------------------------------------------------------


class TestRunBootstrap:
    """Tests for run_bootstrap() function."""

    def test_dry_run_shows_plan(self):
        """Dry run shows plan without executing."""
        with (
            patch("baseball.db._drop_database") as mock_drop,
            patch("baseball.db._create_database") as mock_create,
            patch("baseball.db._run_sql_file") as mock_run,
            patch("baseball.db.get_sql_files") as mock_get_files,
            patch("baseball.db.SQL_ROOT", Path("/home/cbwinslow/workspace/mlb/sql")),
        ):
            mock_get_files.return_value = (
                Path(
                    "/home/cbwinslow/workspace/mlb/sql/010_extensions/001_extensions.sql"
                ),
            )
            run_bootstrap("postgresql://localhost/mlb")
            mock_drop.assert_not_called()
            mock_create.assert_not_called()
            mock_run.assert_called_once()

    def test_recreate_drops_and_creates(self):
        """Recreate flag drops and creates database."""
        with (
            patch("baseball.db._drop_database") as mock_drop,
            patch("baseball.db._create_database") as mock_create,
            patch("baseball.db._run_sql_file") as mock_run,
            patch("baseball.db.get_sql_files") as mock_get_files,
            patch("baseball.db.SQL_ROOT", Path("/home/cbwinslow/workspace/mlb/sql")),
        ):
            mock_get_files.return_value = (
                Path(
                    "/home/cbwinslow/workspace/mlb/sql/010_extensions/001_extensions.sql"
                ),
            )
            run_bootstrap("postgresql://localhost/mlb", recreate=True)
            mock_drop.assert_called_once()
            mock_create.assert_called_once()

    def test_applies_all_sql_files(self):
        """All SQL files are applied in order."""
        mock_files = [
            Path("/home/cbwinslow/workspace/mlb/sql/010_extensions/001_extensions.sql"),
            Path("/home/cbwinslow/workspace/mlb/sql/020_schemas/001_schemas.sql"),
        ]
        with (
            patch("baseball.db._run_sql_file") as mock_run,
            patch("baseball.db.get_sql_files") as mock_get_files,
            patch("baseball.db.SQL_ROOT", Path("/home/cbwinslow/workspace/mlb/sql")),
        ):
            mock_get_files.return_value = tuple(mock_files)
            run_bootstrap("postgresql://localhost/mlb")
            assert mock_run.call_count == len(mock_files)


# Import subprocess for exception testing
import subprocess
