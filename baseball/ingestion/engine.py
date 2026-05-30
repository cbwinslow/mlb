"""baseball.ingestion.engine — database ingest engine.

Provides IngestEngine class for bulk COPY operations and JSONB insertion.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Optional

from psycopg_pool import AsyncConnectionPool

log = logging.getLogger(__name__)


class IngestEngine:
    """High-level database ingestion operations.

    Handles bulk CSV loading and JSONB payload insertion for the raw layer.
    """

    def __init__(self, pool: AsyncConnectionPool):
        self.pool = pool

    async def bulk_load_raw_csv(
        self,
        table_name: str,
        file_path: Path,
        columns: Optional[list[str]] = None,
        delimiter: str = ",",
        null: str = "",
        encoding: str = "utf-8",
    ) -> int:
        """Bulk load a CSV file into a raw table using COPY.

        Uses PostgreSQL's COPY command for fast bulk loading of historical
        data files.

        Args:
            table_name: Target table (schema qualified, e.g. 'raw_statcast.pitch')
            file_path: Path to the CSV file
            columns: Optional column list for explicit ordering
            delimiter: CSV field delimiter character
            null: String to treat as SQL NULL
            encoding: File character encoding

        Returns:
            Number of rows loaded
        """
        async with self.pool.connection() as conn:
            col_clause = f"({', '.join(columns)})" if columns else ""
            sql = f"""
                COPY {table_name}{col_clause}
                FROM STDIN
                WITH (
                    FORMAT csv,
                    HEADER true,
                    DELIMITER '{delimiter}',
                    NULL '{null}'
                )
            """
            # psycopg v3 async copy: use cursor.copy() context manager
            async with conn.cursor().copy(sql) as copy:
                with file_path.open("rb") as fh:
                    while data := fh.read(65536):  # Read in 64KB chunks
                        await copy.write(data)
            await conn.commit()

            # Return count
            result = await conn.execute(f"SELECT COUNT(*) FROM {table_name}")
            row = await result.fetchone()
            return row[0]

    async def ingest_raw_jsonb(
        self,
        table_name: str,
        json_data: dict,
        ingest_run_id: Optional[str] = None,
        **extra_columns: dict,
    ) -> int:
        """Insert a JSON blob into a raw JSONB payload table.

        Stores API responses directly as JSONB for later parsing/staging.

        Args:
            table_name: Target payload table (e.g. 'raw_mlbapi.payload')
            json_data: JSON-serializable dictionary
            ingest_run_id: Optional FK to meta.ingest_run
            **extra_columns: Additional columns to set

        Returns:
            The inserted row's primary key value
        """
        async with self.pool.connection() as conn:
            extra_sql = ""
            extra_values = {}
            for key, value in extra_columns.items():
                extra_sql += f", {key} = %({key})s"
                extra_values[key] = value

            extra_sql_values = (
                ", ".join([f"%({k})s" for k in extra_columns]) if extra_columns else ""
            )
            sql = f"""
                INSERT INTO {table_name}
                    (response_json, ingest_run_id{extra_sql}, created_at)
                VALUES
                    (%(json_data)s, %(ingest_run_id)s{extra_sql_values}, NOW())
                RETURNING {self._get_pk_column(table_name)}
            """

            params = {
                "json_data": json.dumps(json_data),
                "ingest_run_id": ingest_run_id,
            }
            params.update(extra_values)

            result = await conn.execute(sql, params)
            pk = (await result.fetchone())[0]
            await conn.commit()
            return pk

    def _get_pk_column(self, table_name: str) -> str:
        """Return the primary key column name for a table."""
        # Common PK patterns in raw tables
        pk_map = {
            "raw_mlbapi": "mlbapi_payload_id",
            "raw_statcast": "statcast_pitch_id",
            "raw_fangraphs": "raw_fangraphs_payload_id",
            "raw_bref": "raw_bref_page_id",
            "raw_espn": "raw_espn_page_id",
            "raw_odds": "raw_odds_provider_payload_id",
        }
        for schema, pk in pk_map.items():
            if schema in table_name:
                return pk
        return "id"

    async def upsert_player_identity(
        self,
        mlbam_player_id: Optional[int],
        full_name: Optional[str],
        identity_source: str = "ingest",
    ) -> int:
        """Upsert a player identity record.

        Creates a placeholder identity record for cross-source ID bridging.
        Used when a new MLBAM ID is encountered.

        Args:
            mlbam_player_id: MLB Stats API player ID
            full_name: Player full name from source
            identity_source: Source identifier (default 'ingest')

        Returns:
            The player_identity_id
        """
        async with self.pool.connection() as conn:
            sql = """
                INSERT INTO stg.player_identity
                    (mlbam_player_id, full_name, identity_source,
                     identity_confidence_score, created_at, updated_at)
                VALUES
                    (%(mlbam_id)s, %(full_name)s, %(source)s, 0, NOW(), NOW())
                ON CONFLICT (mlbam_player_id) DO UPDATE
                    SET full_name = COALESCE(
                        EXCLUDED.full_name, stg.player_identity.full_name
                    ),
                        updated_at = NOW()
                RETURNING player_identity_id
            """
            result = await conn.execute(
                sql,
                {
                    "mlbam_id": mlbam_player_id,
                    "full_name": full_name,
                    "source": identity_source,
                },
            )
            return (await result.fetchone())[0]

    async def record_ingest_run(
        self,
        source_endpoint_id: int,
        status: str = "running",
        error_message: Optional[str] = None,
    ) -> str:
        """Create a new ingest_run record.

        Args:
            source_endpoint_id: FK to meta.source_endpoint
            status: Run status (running, succeeded, failed, partial, cancelled)
            error_message: Optional error details

        Returns:
            The ingest_run_id UUID string
        """
        async with self.pool.connection() as conn:
            sql = """
                INSERT INTO meta.ingest_run
                    (source_endpoint_id, run_status, error_message, started_at)
                VALUES
                    (%(endpoint_id)s, %(status)s, %(error)s, NOW())
                RETURNING ingest_run_id
            """
            result = await conn.execute(
                sql,
                {
                    "endpoint_id": source_endpoint_id,
                    "status": status,
                    "error": error_message,
                },
            )
            return str((await result.fetchone())[0])

    async def complete_ingest_run(
        self,
        ingest_run_id: str,
        status: str = "succeeded",
        error_message: Optional[str] = None,
    ) -> None:
        """Mark an ingest run as complete.

        Args:
            ingest_run_id: UUID of the ingest run
            status: Final status (succeeded, failed, partial, cancelled)
            error_message: Optional error message for failures
        """
        async with self.pool.connection() as conn:
            sql = """
                UPDATE meta.ingest_run
                SET run_status = %(status)s,
                    error_message = %(error)s,
                    finished_at = NOW()
                WHERE ingest_run_id = %(run_id)s
            """
            await conn.execute(
                sql,
                {
                    "status": status,
                    "error": error_message,
                    "run_id": ingest_run_id,
                },
            )
            await conn.commit()
