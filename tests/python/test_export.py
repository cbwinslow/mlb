"""Tests for baseball/export.py.

Covers feature export to Parquet for ML training workflows.
"""

from __future__ import annotations

from unittest.mock import MagicMock, patch

from baseball.export import MART_VIEWS, fetch_mart_view, export_to_parquet


# ---------------------------------------------------------------------------
# MART_VIEWS Tests
# ---------------------------------------------------------------------------


class TestMartViews:
    """Tests for MART_VIEWS constant."""

    def test_contains_expected_views(self):
        """MART_VIEWS contains the expected materialized views."""
        assert "mv_player_statcast_summary" in MART_VIEWS
        assert "mv_pitch_arsenal_by_season" in MART_VIEWS
        assert "mv_game_score_context" in MART_VIEWS


# ---------------------------------------------------------------------------
# fetch_mart_view Tests
# ---------------------------------------------------------------------------


class TestFetchMartView:
    """Tests for fetch_mart_view function."""

    def test_uses_correct_sql(self):
        """fetch_mart_view constructs correct SQL query."""
        mock_conn = MagicMock()
        mock_df = MagicMock()
        mock_read_sql = MagicMock(return_value=mock_df)

        with patch("psycopg2.connect", return_value=mock_conn):
            with patch("pandas.read_sql", mock_read_sql):
                fetch_mart_view("postgresql://test", "mv_player_statcast_summary")

        mock_read_sql.assert_called_once()
        args = mock_read_sql.call_args[0]
        assert "SELECT * FROM mart.mv_player_statcast_summary" in args[0]


# ---------------------------------------------------------------------------
# export_to_parquet Tests
# ---------------------------------------------------------------------------


class TestExportToParquet:
    """Tests for export_to_parquet function."""

    def test_creates_parent_directories(self):
        """export_to_parquet creates parent directories."""
        df = MagicMock()
        df.__len__ = MagicMock(return_value=100)

        with patch("pathlib.Path.mkdir"):
            with patch.object(df, "to_parquet"):
                count = export_to_parquet(df, "/tmp/test/dir/output.parquet")

        assert count == 100

    def test_uses_partition_cols_without_partition(self):
        """export_to_parquet without partition uses simple write."""
        df = MagicMock()
        df.__len__ = MagicMock(return_value=50)
        df.columns = ["col_a", "col_b"]

        with patch.object(df, "to_parquet") as mock_to_parquet:
            with patch("pathlib.Path.mkdir"):
                export_to_parquet(df, "/tmp/output.parquet")

        mock_to_parquet.assert_called_once()
        call_kwargs = mock_to_parquet.call_args[1]
        assert "partition_cols" not in call_kwargs

    def test_uses_partition_cols_with_partition(self):
        """export_to_parquet with partition uses partition_cols."""
        df = MagicMock()
        df.__len__ = MagicMock(return_value=50)
        df.columns = ["col_a", "season", "col_b"]

        with patch.object(df, "to_parquet") as mock_to_parquet:
            with patch("pathlib.Path.mkdir"):
                export_to_parquet(df, "/tmp/output.parquet", partition_by="season")

        mock_to_parquet.assert_called_once()
        call_kwargs = mock_to_parquet.call_args[1]
        assert call_kwargs["partition_cols"] == ["season"]
