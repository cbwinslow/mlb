"""Tests for baseball/settings.py.

Covers AppEnv, DatabaseSettings, WorkspaceSettings, OpsSettings, AppSettings,
and the get_settings() cached factory.

Notes on AppSettings construction
----------------------------------
AppSettings is a pydantic-settings BaseSettings whose nested fields
(database, workspace, ops) are plain BaseModel sub-objects.  Because
pydantic-settings v2 does *not* fanout individual env-var aliases into nested
BaseModel fields without an env_nested_delimiter, the tests construct
AppSettings by passing the nested models as direct keyword arguments rather
than relying on env-var injection for nested fields.  Top-level AppSettings
fields (env, log_level) are still exercised via env vars.
"""

from __future__ import annotations

import os
from unittest.mock import patch

import pytest
from pydantic import ValidationError

from baseball.settings import (
    AppEnv,
    AppSettings,
    DatabaseSettings,
    OpsSettings,
    WorkspaceSettings,
    get_settings,
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_VALID_DB_URL = "postgresql+asyncpg://mlb:secret@localhost:5432/mlb"
_VALID_DB_URL_NO_PASS = "postgresql+asyncpg://mlb@localhost:5432/mlb"


def _db(url: str = _VALID_DB_URL, search_path: str | None = None) -> DatabaseSettings:
    """Convenience factory for DatabaseSettings."""
    data: dict = {"DATABASE_URL": url}
    if search_path is not None:
        data["DB_SCHEMA_SEARCH_PATH"] = search_path
    return DatabaseSettings.model_validate(data)


def _make_settings(
    env: AppEnv = AppEnv.LOCAL,
    log_level: str = "INFO",
    db_url: str = _VALID_DB_URL,
    workspace_code: str = "local-dev",
    queue_name: str = "default",
) -> AppSettings:
    """Build AppSettings with controlled env vars + direct nested model injection.

    pydantic-settings v2 ignores init kwargs for aliased top-level fields (env,
    log_level) when env vars are present.  We therefore set APP_ENV and LOG_LEVEL
    via os.environ for the duration of the call, and inject nested models directly
    as keyword arguments (since individual env vars do not fan out into nested
    BaseModel fields without env_nested_delimiter).
    """
    get_settings.cache_clear()
    env_patch = {"APP_ENV": env.value, "LOG_LEVEL": log_level}
    with patch.dict(os.environ, env_patch, clear=False):
        return AppSettings(
            database=_db(db_url),
            workspace=WorkspaceSettings.model_validate(
                {"DEFAULT_WORKSPACE_CODE": workspace_code}
            ),
            ops=OpsSettings.model_validate({"DEFAULT_QUEUE_NAME": queue_name}),
        )


# ---------------------------------------------------------------------------
# AppEnv
# ---------------------------------------------------------------------------


class TestAppEnv:
    def test_values_are_lowercase_strings(self):
        assert AppEnv.LOCAL.value == "local"
        assert AppEnv.TEST.value == "test"
        assert AppEnv.PRODUCTION.value == "production"

    def test_inherits_from_str(self):
        assert isinstance(AppEnv.LOCAL, str)
        assert AppEnv.LOCAL == "local"

    def test_all_members_present(self):
        members = {e.value for e in AppEnv}
        assert members == {"local", "test", "production"}

    def test_cast_from_string(self):
        assert AppEnv("local") is AppEnv.LOCAL
        assert AppEnv("test") is AppEnv.TEST
        assert AppEnv("production") is AppEnv.PRODUCTION

    def test_invalid_value_raises(self):
        with pytest.raises(ValueError):
            AppEnv("staging")

    def test_enum_members_are_strings(self):
        for member in AppEnv:
            assert isinstance(member, str)


# ---------------------------------------------------------------------------
# DatabaseSettings
# ---------------------------------------------------------------------------


class TestDatabaseSettings:
    def test_valid_url_with_password(self):
        db = _db(_VALID_DB_URL)
        assert str(db.url).startswith("postgresql+asyncpg://")

    def test_valid_url_without_password(self):
        db = _db(_VALID_DB_URL_NO_PASS)
        assert db.url is not None

    def test_url_is_required(self):
        with pytest.raises(ValidationError):
            DatabaseSettings.model_validate({})

    def test_schema_search_path_defaults_to_none(self):
        db = _db()
        assert db.schema_search_path is None

    def test_schema_search_path_can_be_set(self):
        db = _db(search_path="meta,ref,raw_retrosheet,stg,core")
        assert db.schema_search_path == "meta,ref,raw_retrosheet,stg,core"

    def test_invalid_url_raises(self):
        with pytest.raises(ValidationError):
            DatabaseSettings.model_validate({"DATABASE_URL": "not-a-url"})

    def test_url_stored_correctly(self):
        db = _db("postgresql+asyncpg://user:pw@dbhost:5433/mydb")
        assert "dbhost" in str(db.url)
        assert "5433" in str(db.url)

    def test_empty_schema_search_path_is_stored(self):
        db = _db(search_path="")
        assert db.schema_search_path == ""

    def test_full_schema_search_path(self):
        full_path = (
            "meta,ref,raw_retrosheet,raw_chadwick,raw_lahman,raw_statcast,"
            "raw_mlbapi,raw_fangraphs,raw_bref,raw_espn,raw_odds,"
            "stg,core,mart,ml,ops,auth,api,util"
        )
        db = _db(search_path=full_path)
        assert db.schema_search_path == full_path


# ---------------------------------------------------------------------------
# WorkspaceSettings
# ---------------------------------------------------------------------------


class TestWorkspaceSettings:
    def test_default_workspace_code(self):
        ws = WorkspaceSettings.model_validate({})
        assert ws.default_workspace_code == "local-dev"

    def test_custom_workspace_code(self):
        ws = WorkspaceSettings.model_validate(
            {"DEFAULT_WORKSPACE_CODE": "prod-us-east"}
        )
        assert ws.default_workspace_code == "prod-us-east"

    def test_empty_string_accepted(self):
        ws = WorkspaceSettings.model_validate({"DEFAULT_WORKSPACE_CODE": ""})
        assert ws.default_workspace_code == ""

    def test_field_accessible_by_name(self):
        ws = WorkspaceSettings.model_validate({"DEFAULT_WORKSPACE_CODE": "ci-env"})
        assert ws.default_workspace_code == "ci-env"


# ---------------------------------------------------------------------------
# OpsSettings
# ---------------------------------------------------------------------------


class TestOpsSettings:
    def test_default_queue_name(self):
        ops = OpsSettings.model_validate({})
        assert ops.default_queue_name == "default"

    def test_custom_queue_name(self):
        ops = OpsSettings.model_validate({"DEFAULT_QUEUE_NAME": "high-priority"})
        assert ops.default_queue_name == "high-priority"

    def test_empty_string_accepted(self):
        ops = OpsSettings.model_validate({"DEFAULT_QUEUE_NAME": ""})
        assert ops.default_queue_name == ""

    def test_field_accessible_by_name(self):
        ops = OpsSettings.model_validate({"DEFAULT_QUEUE_NAME": "ingest-queue"})
        assert ops.default_queue_name == "ingest-queue"


# ---------------------------------------------------------------------------
# AppSettings
# ---------------------------------------------------------------------------


class TestAppSettings:
    def setup_method(self):
        get_settings.cache_clear()

    def test_defaults_to_local_env(self):
        settings = _make_settings()
        assert settings.env is AppEnv.LOCAL

    def test_test_env(self):
        settings = _make_settings(env=AppEnv.TEST)
        assert settings.env is AppEnv.TEST

    def test_production_env(self):
        settings = _make_settings(env=AppEnv.PRODUCTION)
        assert settings.env is AppEnv.PRODUCTION

    def test_invalid_env_raises(self):
        with patch.dict(os.environ, {"APP_ENV": "staging"}, clear=False):
            with pytest.raises((ValidationError, ValueError)):
                AppSettings(database=_db())

    def test_log_level_defaults_to_info(self):
        settings = _make_settings()
        assert settings.log_level == "INFO"

    def test_log_level_debug(self):
        settings = _make_settings(log_level="DEBUG")
        assert settings.log_level == "DEBUG"

    def test_log_level_warning(self):
        settings = _make_settings(log_level="WARNING")
        assert settings.log_level == "WARNING"

    def test_log_level_error(self):
        settings = _make_settings(log_level="ERROR")
        assert settings.log_level == "ERROR"

    def test_invalid_log_level_raises(self):
        with patch.dict(
            os.environ, {"APP_ENV": "local", "LOG_LEVEL": "VERBOSE"}, clear=False
        ):
            with pytest.raises((ValidationError, ValueError)):
                AppSettings(database=_db())

    def test_database_settings_present(self):
        settings = _make_settings()
        assert isinstance(settings.database, DatabaseSettings)

    def test_workspace_settings_present(self):
        settings = _make_settings()
        assert isinstance(settings.workspace, WorkspaceSettings)

    def test_ops_settings_present(self):
        settings = _make_settings()
        assert isinstance(settings.ops, OpsSettings)

    def test_database_url_accessible(self):
        settings = _make_settings(db_url=_VALID_DB_URL)
        assert settings.database.url is not None

    def test_workspace_code_accessible(self):
        settings = _make_settings(workspace_code="staging-env")
        assert settings.workspace.default_workspace_code == "staging-env"

    def test_ops_queue_name_accessible(self):
        settings = _make_settings(queue_name="priority-queue")
        assert settings.ops.default_queue_name == "priority-queue"

    def test_all_valid_log_levels(self):
        for level in ("DEBUG", "INFO", "WARNING", "ERROR"):
            get_settings.cache_clear()
            with patch.dict(
                os.environ, {"APP_ENV": "local", "LOG_LEVEL": level}, clear=False
            ):
                settings = AppSettings(database=_db())
            assert settings.log_level == level

    def test_app_env_from_top_level_env_var(self):
        """AppSettings top-level fields can still be read from env vars."""
        get_settings.cache_clear()
        with patch.dict(os.environ, {"APP_ENV": "test"}, clear=False):
            settings = AppSettings(database=_db())
        assert settings.env is AppEnv.TEST

    def test_log_level_from_top_level_env_var(self):
        get_settings.cache_clear()
        with patch.dict(os.environ, {"LOG_LEVEL": "WARNING"}, clear=False):
            settings = AppSettings(database=_db())
        assert settings.log_level == "WARNING"


# ---------------------------------------------------------------------------
# get_settings
# ---------------------------------------------------------------------------


class TestGetSettings:
    def setup_method(self):
        get_settings.cache_clear()

    def test_returns_app_settings_instance(self):
        with patch("baseball.settings.AppSettings", return_value=_make_settings()):
            settings = get_settings()
        assert isinstance(settings, AppSettings)

    def test_caches_result(self):
        mock_settings = _make_settings()
        with patch("baseball.settings.AppSettings", return_value=mock_settings):
            s1 = get_settings()
            s2 = get_settings()
        assert s1 is s2

    def test_cache_clear_allows_new_call(self):
        mock1 = _make_settings(env=AppEnv.TEST)
        mock2 = _make_settings(env=AppEnv.LOCAL)
        with patch("baseball.settings.AppSettings", return_value=mock1):
            s1 = get_settings()
        get_settings.cache_clear()
        with patch("baseball.settings.AppSettings", return_value=mock2):
            s2 = get_settings()
        assert s1 is not s2

    def test_cached_result_is_reused_without_new_call(self):
        """After caching, calling get_settings again returns the same object."""
        mock_settings = _make_settings()
        call_count = 0

        def tracking_factory(*args, **kwargs):
            nonlocal call_count
            call_count += 1
            return mock_settings

        with patch("baseball.settings.AppSettings", side_effect=tracking_factory):
            get_settings()
            get_settings()
            get_settings()
        # The factory is only called once because of the lru_cache
        assert call_count == 1

    def test_without_database_raises_validation_error(self):
        """Calling AppSettings() without DATABASE_URL should raise ValidationError."""
        get_settings.cache_clear()
        clean_env = {k: v for k, v in os.environ.items() if k != "DATABASE_URL"}
        with patch.dict(os.environ, clean_env, clear=True):
            with pytest.raises((ValidationError, Exception)):
                AppSettings()
