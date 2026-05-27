# Ingestion Procedures & Vector Database Integration Plan

> **Date:** 2026-05-26
> **Issue:** #37 (to be created)
> **Status:** Planning

---

## Overview

This plan covers:
1. Completing ingestion procedures for all historical baseball data sources
2. Setting up Qdrant and pgvector for vector database support
3. Integrating Haystack for document store and RAG capabilities

---

## Phase 1: Ingestion Procedures Implementation

### 1.1 Source-Specific Ingestion Functions

| Source | Status | Implementation |
|--------|--------|----------------|
| Retrosheet | ✅ SQL functions exist (`util.ingest_chadwick_play`) | Add Python loader in `baseball/ingestion/retrosheet.py` |
| Statcast | ✅ SQL functions exist (`util.ingest_statcast_play`) | Add Python loader in `baseball/ingestion/statcast.py` |
| MLB StatsAPI | ✅ SQL tables exist | Add Python loader in `baseball/ingestion/mlbam.py` |
| FanGraphs | ✅ SQL tables exist | Add Python loader in `baseball/ingestion/fangraphs.py` |
| Baseball Reference | ✅ SQL tables exist | Add Python loader in `baseball/ingestion/bref.py` |
| ESPN | ✅ SQL tables exist | Add Python loader in `baseball/ingestion/espn.py` |
| Odds | ✅ SQL tables exist | Add Python loader in `baseball/ingestion/odds.py` |

### 1.2 Python Ingestion Module Structure

```
baseball/ingestion/
├── __init__.py
├── base.py           # BaseIngester ABC with common patterns
├── orchestrator.py   # Already exists - context manager
├── engine.py         # Already exists - bulk COPY operations
├── loaders.py        # Already exists - CSV streaming, API fetching
├── mlbam.py          # MLB StatsAPI ingester
├── retrosheet.py     # Retrosheet file ingester
├── statcast.py       # Statcast / pybaseball ingester
├── fangraphs.py      # FanGraphs data ingester
├── bref.py           # Baseball Reference ingester
├── espn.py           # ESPN data ingester
├── odds.py           # Odds data ingester
└── models.py         # Pydantic models for validation
```

### 1.3 BaseIngester ABC Pattern

```python
class BaseIngester(ABC):
    """Abstract base class for all data source ingesters."""

    def __init__(self, pool: AsyncConnectionPool, workspace_id: UUID):
        self.pool = pool
        self.workspace_id = workspace_id

    @abstractmethod
    async def ingest(self, **kwargs) -> IngestRunInfo:
        """Run the ingestion process."""
        ...

    @abstractmethod
    async def validate(self) -> bool:
        """Validate data before ingestion."""
        ...

    async def _get_source_endpoint_id(self, endpoint_code: str) -> int:
        """Get source_endpoint_id for tracking."""
        ...
```

---

## Phase 2: Vector Database Integration

### 2.1 pgvector Setup

Add to `pyproject.toml`:
```toml
[project.optional-dependencies]
vector = [
    "pgvector>=0.3.0",
    "haystack-ai>=2.0.0",
    "qdrant-client>=1.10.0",
]
```

### 2.2 SQL Schema for Vector Storage

Create `sql/040_raw/007_raw_vector.sql`:
```sql
-- Vector embedding storage for player descriptions, game narratives, etc.
CREATE TABLE IF NOT EXISTS raw_vector.embedding (
    embedding_id BIGSERIAL PRIMARY KEY,
    source_table TEXT NOT NULL,
    source_id TEXT NOT NULL,
    embedding_vector VECTOR(1536),  -- OpenAI embedding dimension
    model_name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (source_table, source_id, model_name)
);

COMMENT ON TABLE raw_vector.embedding IS
    'Vector embeddings for semantic search across baseball entities.';
```

### 2.3 Haystack Document Store Integration

- `QdrantDocumentStore` for production vector search
- `PgVectorDocumentStore` for PostgreSQL-native vector storage
- `SuperProcess` for document processing pipelines

---

## Phase 3: Haystack Integration

### 3.1 Document Store Configuration

```python
# baseball/vector/document_store.py
from haystack_integrations.document_stores.qdrant import QdrantDocumentStore
from haystack_integrations.document_stores.pgvector import PgVectorDocumentStore

def get_qdrant_store(url: str, api_key: str) -> QdrantDocumentStore:
    return QdrantDocumentStore(
        url=url,
        api_key=api_key,
        index="baseball_documents",
        embedding_dim=1536,
    )

def get_pgvector_store(conn_str: str) -> PgVectorDocumentStore:
    return PgVectorDocumentStore(
        connection_string=conn_str,
        table_name="raw_vector.embedding",
        embedding_dimension=1536,
    )
```

### 3.2 Document Processing Pipelines

```python
# baseball/vector/pipelines.py
from haystack import Pipeline, Document
from haystack.document_stores import InMemoryDocumentStore

def create_player_embedding_pipeline(store) -> Pipeline:
    """Create pipeline for player biography embeddings."""
    pipeline = Pipeline()
    # Add document writer, embedding retriever, etc.
    return pipeline
```

---

## Phase 4: CLI Integration

Add to `baseball/cli.py`:
```python
# Vector database commands
vector_app = typer.Typer(help="Vector database operations")

@vector_app.command("init")
def vector_init():
    """Initialize vector database tables and indexes."""

@vector_app.command("embed-players")
def embed_players():
    """Generate embeddings for player biographies."""

@vector_app.command("search")
def vector_search(query: str):
    """Semantic search across baseball documents."""
```

---

## Implementation Checklist

- [ ] Create `baseball/ingestion/base.py` with BaseIngester ABC
- [ ] Implement `baseball/ingestion/retrosheet.py`
- [ ] Implement `baseball/ingestion/statcast.py`
- [ ] Implement `baseball/ingestion/mlbam.py`
- [ ] Implement `baseball/ingestion/fangraphs.py`
- [ ] Implement `baseball/ingestion/bref.py`
- [ ] Implement `baseball/ingestion/espn.py`
- [ ] Implement `baseball/ingestion/odds.py`
- [ ] Create `sql/040_raw/007_raw_vector.sql`
- [ ] Create `baseball/vector/document_store.py`
- [ ] Create `baseball/vector/pipelines.py`
- [ ] Update `pyproject.toml` with vector dependencies
- [ ] Add vector CLI commands
- [ ] Create tests for all ingestion modules
- [ ] Create tests for vector integration