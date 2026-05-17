from __future__ import annotations

import enum
from functools import lru_cache
from typing import Literal, Optional

from pydantic import AnyUrl, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class AppEnv(str, enum.Enum):
    LOCAL = "local"
    TEST = "test"
    PRODUCTION = "production"


class DatabaseSettings(BaseSettings):
    url: AnyUrl = Field(
        ..., alias="DATABASE_URL",
        description="SQLAlchemy-style database URL for the core PostgreSQL cluster.",
    )
    schema_search_path: Optional[str] = Field(
        None,
        alias="DB_SCHEMA_SEARCH_PATH",
        description="Comma-separated list of schemas to include in the PostgreSQL search_path.",
    )

    model_config = SettingsConfigDict(env_prefix="", extra="ignore")


class WorkspaceSettings(BaseSettings):
    default_workspace_code: str = Field(
        "local-dev",
        alias="DEFAULT_WORKSPACE_CODE",
        description="Logical workspace code used when a specific workspace is not provided.",
    )

    model_config = SettingsConfigDict(env_prefix="", extra="ignore")


class OpsSettings(BaseSettings):
    default_queue_name: str = Field(
        "default",
        alias="DEFAULT_QUEUE_NAME",
        description="Default ops.jobqueue.queuename value for generic jobs.",
    )

    model_config = SettingsConfigDict(env_prefix="", extra="ignore")


class AppSettings(BaseSettings):
    """Top-level application settings shared by CLI, workers, and future APIs."""

    env: AppEnv = Field(
        AppEnv.LOCAL,
        alias="APP_ENV",
        description="Logical environment for this process (local, test, production).",
    )

    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR"] = Field(
        "INFO",
        alias="LOG_LEVEL",
        description="Log level for the application layer.",
    )

    database: DatabaseSettings = Field(default_factory=DatabaseSettings)
    workspace: WorkspaceSettings = Field(default_factory=WorkspaceSettings)
    ops: OpsSettings = Field(default_factory=OpsSettings)

    model_config = SettingsConfigDict(env_prefix="BASEBALL_", extra="ignore")


@lru_cache(maxsize=1)
def get_settings() -> AppSettings:
    """Return a cached AppSettings instance.

    This function should be the single entry point for loading configuration
    in the application layer so that environment resolution is consistent.
    """

    return AppSettings()
