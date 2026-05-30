"""Application settings using pydantic-settings."""

from __future__ import annotations

import enum
from functools import lru_cache
from pathlib import Path
from typing import Literal, Optional

from pydantic import AnyUrl, Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Resolve .env path relative to this file's parent directory (project root)
ENV_FILE = Path(__file__).resolve().parent.parent / ".env"


class AppEnv(str, enum.Enum):
    LOCAL = "local"
    TEST = "test"
    PRODUCTION = "production"


class DatabaseSettings(BaseSettings):
    """Nested database config."""

    url: AnyUrl = Field(
        ...,
        alias="DATABASE_URL",
        description="SQLAlchemy-style database URL for the core PostgreSQL cluster.",
    )
    schema_search_path: Optional[str] = Field(
        None,
        alias="DB_SCHEMA_SEARCH_PATH",
        description="Comma-separated schemas for PostgreSQL search_path.",
    )

    model_config = SettingsConfigDict(
        env_prefix="",
        env_file=str(ENV_FILE) if ENV_FILE.exists() else None,
        extra="ignore",
    )


class WorkspaceSettings(BaseSettings):
    """Nested workspace config."""

    default_workspace_code: str = Field(
        "local-dev",
        alias="DEFAULT_WORKSPACE_CODE",
        description="Default workspace code when not provided.",
    )

    model_config = SettingsConfigDict(
        env_prefix="",
        env_file=str(ENV_FILE) if ENV_FILE.exists() else None,
        extra="ignore",
    )


class OpsSettings(BaseSettings):
    """Nested ops config."""

    default_queue_name: str = Field(
        "default",
        alias="DEFAULT_QUEUE_NAME",
        description="Default ops.jobqueue.queuename value for generic jobs.",
    )

    model_config = SettingsConfigDict(
        env_prefix="",
        env_file=str(ENV_FILE) if ENV_FILE.exists() else None,
        extra="ignore",
    )


class VectorSettings(BaseSettings):
    """Nested vector embedding config."""

    embedding_model: str = Field(
        "text-embedding-3-small",
        alias="EMBEDDING_MODEL",
        description="OpenAI embedding model name.",
    )
    embedding_provider: str = Field(
        "openai",
        alias="EMBEDDING_PROVIDER",
        description="Provider for embedding generation (openai, cohere, etc.).",
    )
    backend: str = Field(
        "pgvector",
        alias="VECTOR_BACKEND",
        description="Vector backend for storage (pgvector or qdrant).",
    )
    openai_api_key: Optional[str] = Field(
        None,
        alias="OPENAI_API_KEY",
        description="OpenAI API key for embedding generation.",
    )
    batch_size: int = Field(
        100,
        alias="EMBEDDING_BATCH_SIZE",
        description="Number of embeddings to generate per batch.",
    )

    model_config = SettingsConfigDict(
        env_prefix="",
        env_file=str(ENV_FILE) if ENV_FILE.exists() else None,
        extra="ignore",
    )


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

    database: DatabaseSettings = Field(default=None)
    workspace: WorkspaceSettings = Field(default=None)
    ops: OpsSettings = Field(default=None)
    vector: VectorSettings = Field(default=None)

    model_config = SettingsConfigDict(
        env_prefix="",
        env_file=str(ENV_FILE) if ENV_FILE.exists() else None,
        env_file_encoding="utf-8",
        extra="ignore",
    )

    @model_validator(mode="before")
    @classmethod
    def init_nested_settings(cls, data):
        """Initialize nested settings from .env if not provided."""
        if data is None:
            data = {}
        # Nested settings classes load from .env via AppSettings' env_file
        if "database" not in data or data["database"] is None:
            data["database"] = DatabaseSettings().model_dump()
        if "workspace" not in data or data["workspace"] is None:
            data["workspace"] = WorkspaceSettings().model_dump()
        if "ops" not in data or data["ops"] is None:
            data["ops"] = OpsSettings().model_dump()
        if "vector" not in data or data["vector"] is None:
            data["vector"] = VectorSettings().model_dump()
        return data


@lru_cache(maxsize=1)
def get_settings() -> AppSettings:
    """Return a cached AppSettings instance.

    This function should be the single entry point for loading configuration
    in the application layer so that environment resolution is consistent.
    """

    return AppSettings()
