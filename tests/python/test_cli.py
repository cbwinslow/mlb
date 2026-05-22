"""Tests for baseball/cli.py.

Covers _mask_db_url(), the db-init command, and the db-smoke command.
"""
from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch

from typer.testing import CliRunner

from baseball.cli import SQL_ROOT, TEST_SQL_ROOT, _mask_db_url, app
from baseball.settings import AppEnv, AppSettings, DatabaseSettings, OpsSettings, WorkspaceSettings

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

runner = CliRunner()


def _make_mock_settings(
    env: AppEnv = AppEnv.LOCAL,
    db_url: str = "postgresql+asyncpg://mlb:secret@localhost:5432/mlb",
    workspace_code: str = "local-dev",
    queue_name: str = "default",
    log_level: str = "INFO",
) -> MagicMock:
    """Build a minimal mock AppSettings object for CLI tests."""
    mock = MagicMock(spec=AppSettings)
    mock.env = env
    mock.log_level = log_level

    db = MagicMock(spec=DatabaseSettings)
    db.url = db_url
    mock.database = db

    ws = MagicMock(spec=WorkspaceSettings)
    ws.default_workspace_code = workspace_code
    mock.workspace = ws

    ops = MagicMock(spec=OpsSettings)
    ops.default_queue_name = queue_name
    mock.ops = ops

    return mock


# ---------------------------------------------------------------------------
# _mask_db_url
# ---------------------------------------------------------------------------

class TestMaskDbUrl:
    def test_password_is_masked(self):
        url = "postgresql+asyncpg://mlb:mysecret@localhost:5432/mlb"
        result = _mask_db_url(url)
        assert "mysecret" not in result
        assert ":***@" in result

    def test_username_preserved(self):
        url = "postgresql+asyncpg://mlb:mysecret@localhost:5432/mlb"
        result = _mask_db_url(url)
        assert "mlb:" in result or "mlb:***" in result

    def test_host_and_port_preserved(self):
        url = "postgresql+asyncpg://mlb:secret@db.example.com:5432/mlbdb"
        result = _mask_db_url(url)
        assert "db.example.com" in result
        assert "5432" in result

    def test_database_name_preserved(self):
        url = "postgresql+asyncpg://mlb:secret@localhost:5432/mlb_prod"
        result = _mask_db_url(url)
        assert "mlb_prod" in result

    def test_no_password_returns_unchanged(self):
        url = "postgresql+asyncpg://mlb@localhost:5432/mlb"
        result = _mask_db_url(url)
        assert result == url

    def test_no_credentials_at_all_returns_unchanged(self):
        url = "postgresql+asyncpg://localhost:5432/mlb"
        result = _mask_db_url(url)
        assert result == url

    def test_masking_is_not_partial_exposure(self):
        """The raw password must never appear anywhere in the result."""
        raw_password = "super$3cr3t!P@ss"
        url = f"postgresql+asyncpg://user:{raw_password}@host:5432/db"
        result = _mask_db_url(url)
        assert raw_password not in result

    def test_masked_url_still_valid_structure(self):
        """After masking, the result should retain the scheme and path."""
        url = "postgresql+asyncpg://user:pass@localhost:5432/mydb"
        result = _mask_db_url(url)
        assert result.startswith("postgresql+asyncpg://")
        assert result.endswith("/mydb")

    def test_colon_in_password_masked_correctly(self):
        """Passwords containing colons should still be masked without corruption."""
        url = "postgresql+asyncpg://user:pa:ss@localhost:5432/db"
        result = _mask_db_url(url)
        # The raw password must be gone
        assert "pa:ss" not in result

    def test_returns_string(self):
        url = "postgresql+asyncpg://user:pass@localhost:5432/db"
        result = _mask_db_url(url)
        assert isinstance(result, str)

    def test_url_without_password_returns_string(self):
        url = "postgresql+asyncpg://localhost:5432/db"
        result = _mask_db_url(url)
        assert isinstance(result, str)

    def test_special_chars_in_password(self):
        """Special characters in the password must be masked."""
        url = "postgresql+asyncpg://user:abc%40xyz@localhost:5432/db"
        result = _mask_db_url(url)
        # The password portion is masked
        assert "abc" not in result or ":***@" in result

    def test_production_url_with_complex_host(self):
        url = "postgresql+asyncpg://mlb_prod:prod-password@prod-db.internal:5432/mlb"
        result = _mask_db_url(url)
        assert "prod-password" not in result
        assert "prod-db.internal" in result


# ---------------------------------------------------------------------------
# SQL_ROOT and TEST_SQL_ROOT constants
# ---------------------------------------------------------------------------

class TestPathConstants:
    def test_sql_root_is_path(self):
        assert isinstance(SQL_ROOT, Path)

    def test_test_sql_root_is_path(self):
        assert isinstance(TEST_SQL_ROOT, Path)

    def test_sql_root_ends_with_sql(self):
        assert SQL_ROOT.name == "sql"

    def test_test_sql_root_ends_with_sql(self):
        assert TEST_SQL_ROOT.name == "sql"

    def test_test_sql_root_parent_is_tests(self):
        assert TEST_SQL_ROOT.parent.name == "tests"

    def test_sql_root_and_test_sql_root_share_same_repo_root(self):
        assert SQL_ROOT.parent == TEST_SQL_ROOT.parent.parent


# ---------------------------------------------------------------------------
# CLI: db-init command
# ---------------------------------------------------------------------------

class TestDbInitCommand:
    def test_exit_code_zero(self):
        mock_settings = _make_mock_settings()
        with patch("baseball.cli.get_settings", return_value=mock_settings):
            result = runner.invoke(app, ["db-init"])
        assert result.exit_code == 0

    def test_output_contains_db_init_plan(self):
        mock_settings = _make_mock_settings()
        with patch("baseball.cli.get_settings", return_value=mock_settings):
            result = runner.invoke(app, ["db-init"])
        assert "DB Init Plan" in result.output

    def test_output_contains_environment(self):
        mock_settings = _make_mock_settings(env=AppEnv.TEST)
        with patch("baseball.cli.get_settings", return_value=mock_settings):
            result = runner.invoke(app, ["db-init"])
        assert "test" in result.output

    def test_output_contains_sql_root(self):
        mock_settings = _make_mock_settings()
        with patch("baseball.cli.get_settings", return_value=mock_settings):
            result = runner.invoke(app, ["db-init"])
        assert "sql" in result.output

    def test_password_not_exposed_in_output(self):
        mock_settings = _make_mock_settings(db_url="postgresql+asyncpg://mlb:supersecret@localhost:5432/mlb")
        with patch("baseball.cli.get_settings", return_value=mock_settings):
            result = runner.invoke(app, ["db-init"])
        assert "supersecret" not in result.output

    def test_password_masked_as_stars(self):
        mock_settings = _make_mock_settings(db_url="postgresql+asyncpg://mlb:topsecret@localhost:5432/mlb")
        with patch("baseball.cli.get_settings", return_value=mock_settings):
            result = runner.invoke(app, ["db-init"])
        assert "***" in result.output

    def test_output_contains_dry_run_note(self):
        mock_settings = _make_mock_settings()
        with patch("baseball.cli.get_settings", return_value=mock_settings):
            result = runner.invoke(app, ["db-init"])
        assert "dry run" in result.output.lower() or "stub" in result.output.lower()

    def test_production_env_shown_in_output(self):
        mock_settings = _make_mock_settings(env=AppEnv.PRODUCTION)
        with patch("baseball.cli.get_settings", return_value=mock_settings):
            result = runner.invoke(app, ["db-init"])
        assert "production" in result.output

    def test_url_without_password_printed_as_is(self):
        url_no_pass = "postgresql+asyncpg://mlb@localhost:5432/mlb"
        mock_settings = _make_mock_settings(db_url=url_no_pass)
        with patch("baseball.cli.get_settings", return_value=mock_settings):
            result = runner.invoke(app, ["db-init"])
        assert "mlb@localhost" in result.output


# ---------------------------------------------------------------------------
# CLI: db-smoke command
# ---------------------------------------------------------------------------

class TestDbSmokeCommand:
    def test_exit_code_zero(self):
        mock_settings = _make_mock_settings()
        with patch("baseball.cli.get_settings", return_value=mock_settings):
            result = runner.invoke(app, ["db-smoke"])
        assert result.exit_code == 0

    def test_output_contains_smoke_test_plan(self):
        mock_settings = _make_mock_settings()
        with patch("baseball.cli.get_settings", return_value=mock_settings):
            result = runner.invoke(app, ["db-smoke"])
        assert "Smoke" in result.output or "smoke" in result.output.lower()

    def test_output_contains_environment(self):
        mock_settings = _make_mock_settings(env=AppEnv.LOCAL)
        with patch("baseball.cli.get_settings", return_value=mock_settings):
            result = runner.invoke(app, ["db-smoke"])
        assert "local" in result.output

    def test_output_contains_tests_root(self):
        mock_settings = _make_mock_settings()
        with patch("baseball.cli.get_settings", return_value=mock_settings):
            result = runner.invoke(app, ["db-smoke"])
        assert "tests" in result.output

    def test_password_not_exposed_in_output(self):
        mock_settings = _make_mock_settings(db_url="postgresql+asyncpg://mlb:topsecret@localhost:5432/mlb")
        with patch("baseball.cli.get_settings", return_value=mock_settings):
            result = runner.invoke(app, ["db-smoke"])
        assert "topsecret" not in result.output

    def test_password_masked_as_stars(self):
        mock_settings = _make_mock_settings(db_url="postgresql+asyncpg://mlb:p4ssw0rd@localhost:5432/mlb")
        with patch("baseball.cli.get_settings", return_value=mock_settings):
            result = runner.invoke(app, ["db-smoke"])
        assert "***" in result.output

    def test_output_contains_dry_run_note(self):
        mock_settings = _make_mock_settings()
        with patch("baseball.cli.get_settings", return_value=mock_settings):
            result = runner.invoke(app, ["db-smoke"])
        assert "dry run" in result.output.lower() or "stub" in result.output.lower()

    def test_test_env_shown_in_output(self):
        mock_settings = _make_mock_settings(env=AppEnv.TEST)
        with patch("baseball.cli.get_settings", return_value=mock_settings):
            result = runner.invoke(app, ["db-smoke"])
        assert "test" in result.output


# ---------------------------------------------------------------------------
# CLI: general / help
# ---------------------------------------------------------------------------

class TestCliHelp:
    def test_help_exits_cleanly(self):
        result = runner.invoke(app, ["--help"])
        assert result.exit_code == 0

    def test_help_mentions_db_init(self):
        result = runner.invoke(app, ["--help"])
        assert "db-init" in result.output

    def test_help_mentions_db_smoke(self):
        result = runner.invoke(app, ["--help"])
        assert "db-smoke" in result.output

    def test_db_init_help_exits_cleanly(self):
        result = runner.invoke(app, ["db-init", "--help"])
        assert result.exit_code == 0

    def test_db_smoke_help_exits_cleanly(self):
        result = runner.invoke(app, ["db-smoke", "--help"])
        assert result.exit_code == 0

    def test_unknown_command_exits_nonzero(self):
        result = runner.invoke(app, ["not-a-command"])
        assert result.exit_code != 0