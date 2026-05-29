"""baseball.vector — Vector embedding workflows for the MLB analytics platform.

Provides embedding providers, document store integration, and CLI commands.
"""

from __future__ import annotations

from baseball.vector.document_store import (
    VectorStoreManager,
    create_player_document,
    create_game_document,
)

__all__ = [
    "VectorStoreManager",
    "create_player_document",
    "create_game_document",
]
