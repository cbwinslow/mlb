-- ===========================================================================
-- Vector Storage Tables for Haystack Integration
-- ===========================================================================

BEGIN;

-- Enable pgvector extension if not already enabled
CREATE EXTENSION IF NOT EXISTS vector;

-- Raw vector embeddings storage
CREATE TABLE IF NOT EXISTS raw_vector.embeddings (
    raw_vector_embedding_id BIGSERIAL PRIMARY KEY,
    source_table TEXT NOT NULL,
    source_id TEXT NOT NULL,
    source_schema TEXT NOT NULL,
    embedding_vector VECTOR(1536) NOT NULL,
    embedding_model TEXT NOT NULL,
    embedding_provider TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_vector_embeddings_unique
        UNIQUE (source_schema, source_table, source_id, embedding_model)
);

COMMENT ON TABLE raw_vector.embeddings IS
    'Raw vector embeddings from any source table for similarity search.';

COMMENT ON COLUMN raw_vector.embeddings.embedding_vector IS
    'Vector embedding (1536 dims for OpenAI text-embedding-3-small).';

COMMENT ON COLUMN raw_vector.embeddings.source_table IS
    'Name of the source table (e.g., core_player, core_games).';

COMMENT ON COLUMN raw_vector.embeddings.source_id IS
    'Primary key value of the source record.';

-- Vector metadata for retrieval
CREATE TABLE IF NOT EXISTS raw_vector.embedding_metadata (
    raw_vector_metadata_id BIGSERIAL PRIMARY KEY,
    raw_vector_embedding_id BIGINT NOT NULL
        REFERENCES raw_vector.embeddings(raw_vector_embedding_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    metadata_key TEXT NOT NULL,
    metadata_value TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_vector_metadata_unique
        UNIQUE (raw_vector_embedding_id, metadata_key)
);

COMMENT ON TABLE raw_vector.embedding_metadata IS
    'Key-value metadata for vector embeddings (player_name, season, etc.).';

-- Qdrant collection mapping
CREATE TABLE IF NOT EXISTS raw_vector.qdrant_collections (
    qdrant_collection_id BIGSERIAL PRIMARY KEY,
    collection_name TEXT NOT NULL UNIQUE,
    source_schema TEXT NOT NULL,
    source_table TEXT NOT NULL,
    embedding_model TEXT NOT NULL,
    vector_size INT NOT NULL,
    distance_metric TEXT NOT NULL DEFAULT 'cosine',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_vector.qdrant_collections IS
    'Mapping of Qdrant collections to source tables and embedding models.';

COMMIT;