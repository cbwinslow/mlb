"""baseball.export — Feature export for ML training workflows.

Provides commands to export materialized views to Parquet format
for use in Python/R ML training pipelines.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Optional

import pandas as pd
import psycopg2
from rich.console import Console
from rich.progress import BarColumn, Progress, SpinnerColumn, TaskProgressColumn, TextColumn

log = logging.getLogger(__name__)
console = Console()


MART_VIEWS = [
    "mv_player_statcast_summary",
    "mv_pitch_arsenal_by_season",
    "mv_game_score_context",
]


def fetch_mart_view(database_url: str, view_name: str) -> pd.DataFrame:
    """Fetch a materialized view as a DataFrame.

    Args:
        database_url: PostgreSQL connection string
        view_name: Name of the materialized view (without schema)

    Returns:
        DataFrame with view data
    """
    sql = f"SELECT * FROM mart.{view_name}"

    conn = psycopg2.connect(database_url)
    try:
        df = pd.read_sql(sql, conn)
    finally:
        conn.close()

    return df


def export_to_parquet(
    df: pd.DataFrame,
    output_path: str,
    partition_by: Optional[str] = None,
) -> int:
    """Export DataFrame to Parquet format.

    Args:
        df: DataFrame to export
        output_path: Output file path (local or S3)
        partition_by: Optional column to partition by

    Returns:
        Number of rows exported
    """
    path = Path(output_path)

    if partition_by and partition_by in df.columns:
        df.to_parquet(
            output_path,
            partition_cols=[partition_by],
            index=False,
        )
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        df.to_parquet(output_path, index=False)

    return len(df)


def export_features(
    database_url: str,
    views: Optional[list[str]] = None,
    output_dir: str = "./exports",
    partition_by: Optional[str] = None,
) -> tuple[int, int]:
    """Export all mart views to Parquet for ML training.

    Args:
        database_url: PostgreSQL connection string
        views: Optional list of views to export (defaults to all MART_VIEWS)
        output_dir: Output directory path
        partition_by: Optional column to partition by

    Returns:
        Tuple of (views_exported, total_rows)
    """
    views_to_export = views or MART_VIEWS
    output_path = Path(output_dir)

    total_views = 0
    total_rows = 0

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        TaskProgressColumn(),
        console=console,
    ) as progress:
        task = progress.add_task("Exporting mart views...", total=len(views_to_export))

        for view_name in views_to_export:
            try:
                df = fetch_mart_view(database_url, view_name)
                rows = export_to_parquet(
                    df,
                    str(output_path / f"{view_name}.parquet"),
                    partition_by=partition_by,
                )
                total_views += 1
                total_rows += rows
                console.print(f"[green]Exported {view_name}: {rows} rows[/green]")
            except Exception as exc:
                console.print(f"[red]Failed to export {view_name}: {exc}[/red]")

            progress.advance(task)

    return total_views, total_rows