"""Shared pytest fixtures for baseball tests."""

from __future__ import annotations

import os
from unittest.mock import MagicMock
from pathlib import Path

import pytest

from baseball.settings import (
    AppEnv,
    AppSettings,
    DatabaseSettings,
    OpsSettings,
    WorkspaceSettings,
)


# ---------------------------------------------------------------------------
# Settings Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def valid_db_url() -> str:
    """A valid PostgreSQL connection URL for testing."""
    return "postgresql+asyncpg://mlb:testpass@localhost:5432/mlb_test"


@pytest.fixture
def mock_settings(valid_db_url: str) -> AppSettings:
    """Build a minimal mock AppSettings object for CLI tests."""
    db = MagicMock(spec=DatabaseSettings)
    db.url = valid_db_url

    ws = MagicMock(spec=WorkspaceSettings)
    ws.default_workspace_code = "test-workspace"

    ops = MagicMock(spec=OpsSettings)
    ops.default_queue_name = "test-queue"

    mock = MagicMock(spec=AppSettings)
    mock.env = AppEnv.TEST
    mock.log_level = "INFO"
    mock.database = db
    mock.workspace = ws
    mock.ops = ops

    return mock


@pytest.fixture
def settings_dict(valid_db_url: str) -> dict:
    """Settings dictionary for AppSettings construction."""
    return {
        "database": DatabaseSettings.model_validate({"DATABASE_URL": valid_db_url}),
        "workspace": WorkspaceSettings.model_validate(
            {"DEFAULT_WORKSPACE_CODE": "test"}
        ),
        "ops": OpsSettings.model_validate({"DEFAULT_QUEUE_NAME": "test"}),
    }


# ---------------------------------------------------------------------------
# Path Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def sql_root() -> Path:
    """Path to the SQL directory."""
    return Path(__file__).parent.parent.parent / "sql"


@pytest.fixture
def test_sql_root() -> Path:
    """Path to the test SQL directory."""
    return Path(__file__).parent / "sql"


# ---------------------------------------------------------------------------
# PendingPlayer Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def sample_pending_player() -> dict:
    """Sample pending player data for testing."""
    return {
        "player_identity_id": 1,
        "mlbam_player_id": 592450,
        "player_name": "Juan Soto",
        "identity_confidence_score": 0.0,
    }


@pytest.fixture
def sample_pending_player_no_mlbam() -> dict:
    """Sample pending player without MLBAM ID."""
    return {
        "player_identity_id": 2,
        "mlbam_player_id": None,
        "player_name": "Historical Player",
        "identity_confidence_score": 0.0,
    }


# ---------------------------------------------------------------------------
# ResolvedIds Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def resolved_ids_full() -> dict:
    """Fully resolved player IDs."""
    return {
        "mlbam_player_id": 592450,
        "retrosheet_player_id": "sotjua01",
        "bbref_player_id": "sotoju01",
        "fangraphs_player_id": "19755",
        "lahman_player_id": "sotoju01",
        "confidence": 0.95,
        "source": "chadwick_cache:mlbam_lookup",
        "notes": "xref_count=4",
    }


@pytest.fixture
def resolved_ids_partial() -> dict:
    """Partially resolved player IDs."""
    return {
        "mlbam_player_id": 592450,
        "retrosheet_player_id": None,
        "bbref_player_id": "sotoju01",
        "fangraphs_player_id": None,
        "lahman_player_id": None,
        "confidence": 0.70,
        "source": "mlb_statsapi:xref",
        "notes": "xref_count=1",
    }


@pytest.fixture
def resolved_ids_unresolved() -> dict:
    """Unresolved player IDs."""
    return {
        "mlbam_player_id": 999999,
        "retrosheet_player_id": None,
        "bbref_player_id": None,
        "fangraphs_player_id": None,
        "lahman_player_id": None,
        "confidence": 0.30,
        "source": "unresolved:needs_manual_review",
        "notes": "all resolution strategies exhausted",
    }


# ---------------------------------------------------------------------------
# Mock Database Connection
# ---------------------------------------------------------------------------


@pytest.fixture
def mock_db_connection():
    """Mock database connection for testing."""
    import psycopg2.extras

    mock_conn = MagicMock()
    mock_cursor = MagicMock()
    mock_conn.cursor.return_value = MagicMock(
        __enter__=MagicMock(return_value=mock_cursor),
        __exit__=MagicMock(return_value=False),
    )
    mock_conn.cursor.return_value.__enter__.return_value = mock_cursor
    mock_cursor.__enter__ = MagicMock(return_value=mock_cursor)
    mock_cursor.__exit__ = MagicMock(return_value=False)

    return mock_conn, mock_cursor


# ---------------------------------------------------------------------------
# Environment Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def clean_env(monkeypatch):
    """Clean environment variables before each test."""
    # Remove test-specific env vars that might interfere
    for key in list(os.environ.keys()):
        if (
            key.startswith("APP_")
            or key.startswith("DATABASE_")
            or key.startswith("LOG_")
        ):
            monkeypatch.delenv(key, raising=False)
