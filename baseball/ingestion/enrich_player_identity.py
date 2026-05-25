#!/usr/bin/env python3
"""
baseball/ingestion/enrich_player_identity.py

Player identity enrichment worker.
Reads stg.v_players_pending_enrichment, resolves cross-source IDs via
MLB StatsAPI → pybaseball → Chadwick fallback, inserts candidates into
stg.player_identity_candidate, then calls stg.fn_reconcile_candidates()
to auto-promote high-confidence rows and flag the rest for human review.

Usage (standalone):
    python -m baseball.ingestion.enrich_player_identity
    python -m baseball.ingestion.enrich_player_identity --limit 100 --min-confidence 0.85
    python -m baseball.ingestion.enrich_player_identity --dry-run
    python -m baseball.ingestion.enrich_player_identity --chadwick-seed /tmp/chadwick_people.csv

CLI (via baseball CLI):
    baseball enrich-identities
    baseball enrich-identities --dry-run
    baseball enrich-identities --chadwick-seed /path/to/people.csv

Architecture notes:
  - Fact tables NEVER store external IDs; only core.player_id is used as FK.
  - stg.player_identity is the identity bridge; all external IDs live here.
  - Confidence scores drive auto-promotion:
      0.85+ → auto-promoted to stg.player_identity
      <0.85  → flagged in stg.v_candidates_pending_human_review
  - The trigger on raw_statcast.pitch already creates placeholders (confidence=0).
    This worker fills them in.
  - Chadwick seed is the bulk historical loader; the enrichment loop handles
    new/live players that Chadwick hasn't published yet.
"""

from __future__ import annotations

import csv
import logging
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import typer
from rich.console import Console
from rich.progress import BarColumn, Progress, SpinnerColumn, TaskProgressColumn, TextColumn
from rich.table import Table

# ---------------------------------------------------------------------------
# Optional heavy imports — deferred so the module loads even if pybaseball
# or statsapi aren't installed (fails loudly only when those paths are taken).
# ---------------------------------------------------------------------------
try:
    import psycopg2
    import psycopg2.extras
    HAS_PSYCOPG2 = True
except ImportError:
    HAS_PSYCOPG2 = False

try:
    import statsapi  # pip install python-mlb-statsapi
    HAS_STATSAPI = True
except ImportError:
    HAS_STATSAPI = False

try:
    import pybaseball  # pip install pybaseball
    HAS_PYBASEBALL = True
except ImportError:
    HAS_PYBASEBALL = False

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s  %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
log = logging.getLogger("baseball.enrich_player_identity")
console = Console()

# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass
class PendingPlayer:
    player_identity_id: int
    mlbam_player_id: Optional[int]
    player_name: Optional[str]
    identity_confidence_score: float


@dataclass
class ResolvedIds:
    mlbam_player_id: Optional[int] = None
    retrosheet_player_id: Optional[str] = None
    bbref_player_id: Optional[str] = None
    fangraphs_player_id: Optional[str] = None
    lahman_player_id: Optional[str] = None
    confidence: float = 0.0
    source: str = "unresolved"
    notes: Optional[str] = None


@dataclass
class WorkerStats:
    processed: int = 0
    resolved_statsapi: int = 0
    resolved_pybaseball: int = 0
    resolved_chadwick_cache: int = 0
    flagged_manual: int = 0
    errors: int = 0
    auto_promoted: int = 0
    start_time: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    @property
    def elapsed_seconds(self) -> float:
        return (datetime.now(timezone.utc) - self.start_time).total_seconds()


# ---------------------------------------------------------------------------
# In-process Chadwick cache  (populated once from DB or from CSV)
# ---------------------------------------------------------------------------

_chadwick_cache: dict[int, dict] = {}          # key_mlbam → row dict
_chadwick_name_cache: dict[str, list[dict]] = {}  # "last,first" → list of rows


def _load_chadwick_from_db(conn) -> None:
    """
    Pull stg.chadwick_register_import into memory for fast O(1) lookups
    during the enrichment loop.  Only done once per worker run.
    """
    global _chadwick_cache, _chadwick_name_cache
    _chadwick_cache = {}
    _chadwick_name_cache = {}

    sql = """
        SELECT key_mlbam, key_retro, key_bbref, key_fangraphs, key_lahman,
               name_last, name_first
        FROM   stg.chadwick_register_import
        WHERE  key_mlbam IS NOT NULL
    """
    with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
        cur.execute(sql)
        rows = cur.fetchall()

    for row in rows:
        d = dict(row)
        mlbam = d.get("key_mlbam")
        if mlbam:
            _chadwick_cache[int(mlbam)] = d

        last  = (d.get("name_last")  or "").lower().strip()
        first = (d.get("name_first") or "").lower().strip()
        if last:
            key = f"{last},{first}"
            _chadwick_name_cache.setdefault(key, []).append(d)

    log.info("Chadwick cache loaded: %d players by MLBAM, %d name keys",
             len(_chadwick_cache), len(_chadwick_name_cache))


def _load_chadwick_from_csv(csv_path: Path) -> None:
    """
    Seed stg.chadwick_register_import (and in-process cache) from a downloaded
    Chadwick people.csv file.  Also populates the DB table via COPY so
    fn_cross_validate_identities() works afterwards.
    """
    log.info("Loading Chadwick CSV: %s", csv_path)
    rows = []
    with csv_path.open(newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            rows.append(row)
    log.info("Parsed %d rows from Chadwick CSV", len(rows))
    return rows  # caller handles DB insert


# ---------------------------------------------------------------------------
# Resolution strategies
# ---------------------------------------------------------------------------

def _resolve_via_statsapi(mlbam_id: int) -> Optional[ResolvedIds]:
    """
    MLB StatsAPI people endpoint with xrefId hydration.
    Best source for modern/active players; partial historical xrefs vary.

    Returns None if statsapi not installed or player not found.
    """
    if not HAS_STATSAPI:
        return None

    try:
        people = statsapi.lookup_player(mlbam_id)
        if not people:
            return None

        p = people[0]
        xrefs = p.get("xrefIds", {})

        retro  = xrefs.get("retrosheet") or xrefs.get("retro") or None
        bbref  = xrefs.get("bbref") or xrefs.get("baseball_reference") or None
        lahman = xrefs.get("lahman") or None
        fg     = xrefs.get("fangraphs") or None

        # Only trust this result if we got at least one xref back
        xref_count = sum(1 for v in (retro, bbref, lahman, fg) if v)
        confidence = 0.70 + min(xref_count * 0.07, 0.25)  # 0.70 → 0.95 based on richness

        return ResolvedIds(
            mlbam_player_id=mlbam_id,
            retrosheet_player_id=retro,
            bbref_player_id=bbref,
            fangraphs_player_id=str(fg) if fg else None,
            lahman_player_id=lahman,
            confidence=round(confidence, 3),
            source="mlb_statsapi:xref",
            notes=f"xref_count={xref_count}",
        )
    except Exception as exc:
        log.debug("StatsAPI lookup failed for %s: %s", mlbam_id, exc)
        return None


def _resolve_via_chadwick_cache(mlbam_id: int) -> Optional[ResolvedIds]:
    """
    In-process Chadwick lookup.  O(1) after cache is warm.
    Best single source for historical players.
    """
    row = _chadwick_cache.get(mlbam_id)
    if not row:
        return None

    retro  = row.get("key_retro")  or None
    bbref  = row.get("key_bbref")  or None
    fg     = row.get("key_fangraphs") or None
    lahman = row.get("key_lahman") or None

    xref_count = sum(1 for v in (retro, bbref, fg, lahman) if v)
    confidence = 0.75 + min(xref_count * 0.06, 0.22)  # 0.75 → 0.97

    return ResolvedIds(
        mlbam_player_id=mlbam_id,
        retrosheet_player_id=retro,
        bbref_player_id=bbref,
        fangraphs_player_id=str(int(float(fg))) if fg else None,
        lahman_player_id=lahman,
        confidence=round(confidence, 3),
        source="chadwick_cache:mlbam_lookup",
        notes=f"xref_count={xref_count}",
    )


def _resolve_via_pybaseball(player_name: str, mlbam_id: int) -> Optional[ResolvedIds]:
    """
    pybaseball playerid_lookup — backed by the Smart Fantasy Baseball player
    ID map.  Used when StatsAPI and Chadwick cache both miss.
    Name-based: higher false-positive risk; confidence capped at 0.80.
    """
    if not HAS_PYBASEBALL or not player_name:
        return None

    try:
        parts = player_name.strip().split()
        if len(parts) < 2:
            return None
        last, first = parts[-1], parts[0]

        result = pybaseball.playerid_lookup(last, first)
        if result is None or result.empty:
            return None

        # If multiple hits, prefer exact MLBAM match
        match = result[result["key_mlbam"] == mlbam_id]
        row = match.iloc[0] if not match.empty else result.iloc[0]

        fg_raw = row.get("key_fangraphs")
        fg = str(int(fg_raw)) if fg_raw and str(fg_raw) not in ("", "nan") else None

        return ResolvedIds(
            mlbam_player_id=int(row.get("key_mlbam", mlbam_id)),
            retrosheet_player_id=row.get("key_retro") or None,
            bbref_player_id=row.get("key_bbref") or None,
            fangraphs_player_id=fg,
            lahman_player_id=row.get("key_lahman") or None,
            confidence=0.80,
            source="pybaseball:name_lookup",
            notes=f"matched={len(match)}/{len(result)} rows by MLBAM",
        )
    except Exception as exc:
        log.debug("pybaseball lookup failed for '%s': %s", player_name, exc)
        return None


def _resolve_via_chadwick_name(player_name: str) -> Optional[ResolvedIds]:
    """
    Fallback: Chadwick name cache when MLBAM id is unknown.
    Only used if mlbam_id is NULL in the identity row.
    """
    if not player_name:
        return None

    parts = player_name.strip().split()
    if len(parts) < 2:
        return None

    last  = parts[-1].lower()
    first = parts[0].lower()
    key = f"{last},{first}"
    candidates = _chadwick_name_cache.get(key, [])

    if len(candidates) == 1:
        row = candidates[0]
        fg_raw = row.get("key_fangraphs")
        fg = str(int(float(fg_raw))) if fg_raw else None
        mlbam_raw = row.get("key_mlbam")

        return ResolvedIds(
            mlbam_player_id=int(mlbam_raw) if mlbam_raw else None,
            retrosheet_player_id=row.get("key_retro") or None,
            bbref_player_id=row.get("key_bbref") or None,
            fangraphs_player_id=fg,
            lahman_player_id=row.get("key_lahman") or None,
            confidence=0.65,
            source="chadwick_cache:name_lookup",
            notes="single name match",
        )

    if len(candidates) > 1:
        return ResolvedIds(
            confidence=0.40,
            source="chadwick_cache:name_ambiguous",
            notes=f"{len(candidates)} candidates found for '{player_name}'",
        )

    return None


def resolve_player(player: PendingPlayer) -> ResolvedIds:
    """
    Full resolution pipeline for a single player.
    Priority: Chadwick cache (MLBAM) → StatsAPI → pybaseball → Chadwick (name) → flag.
    """
    mlbam = player.mlbam_player_id

    # 1. Chadwick cache is fastest and most reliable for historical players
    if mlbam:
        result = _resolve_via_chadwick_cache(mlbam)
        if result and result.confidence >= 0.80:
            return result

    # 2. MLB StatsAPI — best for current/active players
    if mlbam:
        result = _resolve_via_statsapi(mlbam)
        if result and result.confidence >= 0.75:
            return result

    # 3. pybaseball name lookup — broader but fuzzier
    if player.player_name and mlbam:
        result = _resolve_via_pybaseball(player.player_name, mlbam)
        if result and result.confidence >= 0.60:
            return result

    # 4. Chadwick name cache — last automated resort
    if player.player_name:
        result = _resolve_via_chadwick_name(player.player_name)
        if result:
            return result

    # 5. Flag for manual review
    return ResolvedIds(
        mlbam_player_id=mlbam,
        confidence=0.30,
        source="unresolved:needs_manual_review",
        notes="all resolution strategies exhausted",
    )


# ---------------------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------------------

def get_pending_players(conn, limit: Optional[int] = None) -> list[PendingPlayer]:
    """Fetch rows from stg.v_players_pending_enrichment."""
    sql = """
        SELECT player_identity_id,
               mlbam_player_id,
               player_name,
               identity_confidence_score
        FROM   stg.v_players_pending_enrichment
        ORDER  BY identity_confidence_score ASC,
                  created_at ASC
    """
    if limit:
        sql += f" LIMIT {int(limit)}"

    with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
        cur.execute(sql)
        rows = cur.fetchall()

    return [
        PendingPlayer(
            player_identity_id=r["player_identity_id"],
            mlbam_player_id=r["mlbam_player_id"],
            player_name=r["player_name"],
            identity_confidence_score=float(r["identity_confidence_score"] or 0),
        )
        for r in rows
    ]


def insert_candidate(conn, player_id: int, resolved: ResolvedIds) -> None:
    """
    Insert a resolved candidate into stg.player_identity_candidate.
    fn_reconcile_candidates() will decide whether to auto-promote or flag.
    """
    sql = """
        INSERT INTO stg.player_identity_candidate
            (player_identity_id, mlbam_player_id, retrosheet_player_id,
             bbref_player_id, fangraphs_player_id, lahman_player_id,
             identity_confidence_score, identity_source, resolution_notes,
             created_at)
        VALUES
            (%(pid)s, %(mlbam)s, %(retro)s, %(bbref)s, %(fg)s, %(lahman)s,
             %(conf)s, %(src)s, %(notes)s, NOW())
        ON CONFLICT (player_identity_id) DO UPDATE
            SET mlbam_player_id           = EXCLUDED.mlbam_player_id,
                retrosheet_player_id      = EXCLUDED.retrosheet_player_id,
                bbref_player_id           = EXCLUDED.bbref_player_id,
                fangraphs_player_id       = EXCLUDED.fangraphs_player_id,
                lahman_player_id          = EXCLUDED.lahman_player_id,
                identity_confidence_score = EXCLUDED.identity_confidence_score,
                identity_source           = EXCLUDED.identity_source,
                resolution_notes          = EXCLUDED.resolution_notes,
                created_at                = NOW()
    """
    with conn.cursor() as cur:
        cur.execute(sql, {
            "pid":    player_id,
            "mlbam":  resolved.mlbam_player_id,
            "retro":  resolved.retrosheet_player_id,
            "bbref":  resolved.bbref_player_id,
            "fg":     resolved.fangraphs_player_id,
            "lahman": resolved.lahman_player_id,
            "conf":   resolved.confidence,
            "src":    resolved.source,
            "notes":  resolved.notes,
        })


def run_reconcile(conn, min_confidence: float = 0.85) -> list[dict]:
    """
    Call stg.fn_reconcile_candidates() to auto-promote and flag.
    Returns reconciliation results as a list of dicts.
    """
    sql = "SELECT * FROM stg.fn_reconcile_candidates(%(threshold)s);"
    with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
        cur.execute(sql, {"threshold": min_confidence})
        return [dict(r) for r in cur.fetchall()]


def run_orphan_check(conn) -> list[dict]:
    """Run the circuit breaker — must always return 0 rows."""
    sql = "SELECT * FROM stg.fn_detect_orphaned_pitches();"
    with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
        cur.execute(sql)
        return [dict(r) for r in cur.fetchall()]


def run_health_report(conn) -> str:
    """Full JSON health report from the DB."""
    sql = "SELECT stg.fn_full_identity_health_report();"
    with conn.cursor() as cur:
        cur.execute(sql)
        return cur.fetchone()[0]


def seed_chadwick_csv(conn, csv_path: Path) -> int:
    """
    Bulk-load a Chadwick people.csv into stg.chadwick_register_import
    using psycopg2 copy_expert (client-side streaming COPY).
    Returns number of rows loaded.
    """
    log.info("Seeding Chadwick from %s ...", csv_path)
    with conn.cursor() as cur:
        cur.execute("TRUNCATE stg.chadwick_register_import;")
        with csv_path.open("r", encoding="utf-8") as fh:
            cur.copy_expert(
                """COPY stg.chadwick_register_import
                   FROM STDIN
                   WITH (FORMAT csv, HEADER true, NULL '')""",
                fh,
            )
        cur.execute("SELECT COUNT(*) FROM stg.chadwick_register_import;")
        count = cur.fetchone()[0]
    conn.commit()
    log.info("Chadwick seed: %d rows loaded", count)
    return count


# ---------------------------------------------------------------------------
# Rich display helpers
# ---------------------------------------------------------------------------

def _print_stats(stats: WorkerStats) -> None:
    table = Table(title="Enrichment Worker — Run Summary", show_header=True, header_style="bold cyan")
    table.add_column("Metric", style="bold")
    table.add_column("Count", justify="right")

    table.add_row("Players processed",          str(stats.processed))
    table.add_row("Resolved via StatsAPI",       str(stats.resolved_statsapi))
    table.add_row("Resolved via pybaseball",     str(stats.resolved_pybaseball))
    table.add_row("Resolved via Chadwick cache", str(stats.resolved_chadwick_cache))
    table.add_row("Flagged for manual review",   str(stats.flagged_manual))
    table.add_row("Auto-promoted",               str(stats.auto_promoted))
    table.add_row("Errors",                      str(stats.errors))
    table.add_row("Elapsed (s)",                 f"{stats.elapsed_seconds:.1f}")

    console.print(table)


def _print_reconcile(results: list[dict]) -> None:
    if not results:
        console.print("[green]No candidates to reconcile.[/green]")
        return

    table = Table(title="Reconciliation Results", show_header=True, header_style="bold magenta")
    for col in ("player_identity_id", "action", "confidence", "source"):
        table.add_column(col)

    for r in results[:50]:
        action = r.get("action", "")
        color = "green" if action == "promoted" else "yellow"
        table.add_row(
            str(r.get("player_identity_id", "")),
            f"[{color}]{action}[/{color}]",
            str(r.get("identity_confidence_score", "")),
            r.get("identity_source", ""),
        )
    console.print(table)
    if len(results) > 50:
        console.print(f"[dim]... {len(results) - 50} more rows omitted[/dim]")


# ---------------------------------------------------------------------------
# Main worker loop
# ---------------------------------------------------------------------------

def run_enrichment(
    database_url: str,
    limit: Optional[int] = None,
    min_confidence: float = 0.85,
    dry_run: bool = False,
    chadwick_csv: Optional[Path] = None,
    skip_chadwick_load: bool = False,
    rate_limit_ms: int = 200,
) -> WorkerStats:
    """
    Core enrichment loop.  Called by CLI and importable by other workers.
    """
    if not HAS_PSYCOPG2:
        log.error("psycopg2 not installed.  Run: pip install psycopg2-binary")
        sys.exit(1)

    stats = WorkerStats()
    conn = psycopg2.connect(database_url)
    conn.autocommit = False

    try:
        # ---------------------------------------------------------------
        # Optional: seed Chadwick from CSV
        # ---------------------------------------------------------------
        if chadwick_csv:
            if dry_run:
                log.info("[DRY RUN] Would seed Chadwick from %s", chadwick_csv)
            else:
                seed_chadwick_csv(conn, chadwick_csv)

        # ---------------------------------------------------------------
        # Load Chadwick cache into memory (fast O(1) lookups during loop)
        # ---------------------------------------------------------------
        if not skip_chadwick_load:
            _load_chadwick_from_db(conn)
        else:
            log.info("Chadwick in-process cache skipped (--skip-chadwick-load)")

        # ---------------------------------------------------------------
        # Orphan check — must be 0
        # ---------------------------------------------------------------
        orphans = run_orphan_check(conn)
        if orphans:
            log.critical(
                "ORPHAN ALERT: %d pitches have no identity placeholder! "
                "Investigate raw_statcast.pitch trigger immediately.", len(orphans)
            )
        else:
            log.info("Orphan check: OK (0 orphaned pitches)")

        # ---------------------------------------------------------------
        # Fetch pending players
        # ---------------------------------------------------------------
        pending = get_pending_players(conn, limit=limit)
        log.info("Pending enrichment queue: %d players", len(pending))

        if not pending:
            console.print("[green]✓ No players pending enrichment.[/green]")
            return stats

        # ---------------------------------------------------------------
        # Enrichment loop with progress bar
        # ---------------------------------------------------------------
        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(),
            TaskProgressColumn(),
            console=console,
        ) as progress:
            task = progress.add_task("Resolving player IDs ...", total=len(pending))

            for player in pending:
                stats.processed += 1
                try:
                    resolved = resolve_player(player)

                    # Track resolution path
                    if "chadwick" in resolved.source:
                        stats.resolved_chadwick_cache += 1
                    elif "statsapi" in resolved.source:
                        stats.resolved_statsapi += 1
                    elif "pybaseball" in resolved.source:
                        stats.resolved_pybaseball += 1
                    else:
                        stats.flagged_manual += 1

                    if dry_run:
                        log.debug(
                            "[DRY RUN] player_id=%s  mlbam=%s  conf=%.2f  src=%s",
                            player.player_identity_id,
                            resolved.mlbam_player_id,
                            resolved.confidence,
                            resolved.source,
                        )
                    else:
                        insert_candidate(conn, player.player_identity_id, resolved)

                except Exception as exc:
                    log.warning("Error processing player_id=%s: %s",
                                player.player_identity_id, exc)
                    stats.errors += 1

                progress.advance(task)

                # Gentle rate limiting to avoid hammering external APIs
                if rate_limit_ms > 0:
                    time.sleep(rate_limit_ms / 1000)

        # ---------------------------------------------------------------
        # Commit candidates and reconcile
        # ---------------------------------------------------------------
        if not dry_run:
            conn.commit()
            log.info("Candidates committed. Running reconciliation (threshold=%.2f) ...",
                     min_confidence)
            reconcile_results = run_reconcile(conn, min_confidence)
            conn.commit()

            promoted = [r for r in reconcile_results if r.get("action") == "promoted"]
            stats.auto_promoted = len(promoted)
            _print_reconcile(reconcile_results)
        else:
            log.info("[DRY RUN] Skipped candidate insert and reconciliation.")

        # ---------------------------------------------------------------
        # Final health report
        # ---------------------------------------------------------------
        if not dry_run:
            health_json = run_health_report(conn)
            log.info("Identity health report: %s", health_json[:400])

    finally:
        conn.close()

    return stats


# ---------------------------------------------------------------------------
# CLI (Typer)
# ---------------------------------------------------------------------------

app = typer.Typer(
    name="enrich-identities",
    help="Player identity enrichment worker for the baseball analytics platform.",
    add_completion=False,
)


@app.command()
def main(
    database_url: str = typer.Option(
        ...,
        envvar="DATABASE_URL",
        help="PostgreSQL connection string (psycopg2 format).",
    ),
    limit: Optional[int] = typer.Option(
        None,
        "--limit", "-n",
        help="Max players to process in this run. Omit for all pending.",
    ),
    min_confidence: float = typer.Option(
        0.85,
        "--min-confidence",
        help="Auto-promotion threshold.  Candidates below this go to manual review.",
    ),
    dry_run: bool = typer.Option(
        False,
        "--dry-run",
        help="Resolve IDs but do not write anything to the database.",
    ),
    chadwick_seed: Optional[Path] = typer.Option(
        None,
        "--chadwick-seed",
        help="Path to a Chadwick people.csv to bulk-load before enrichment.",
        exists=True,
        file_okay=True,
        dir_okay=False,
        readable=True,
    ),
    skip_chadwick_load: bool = typer.Option(
        False,
        "--skip-chadwick-load",
        help="Skip loading the Chadwick DB table into the in-process cache.",
    ),
    rate_limit_ms: int = typer.Option(
        200,
        "--rate-limit-ms",
        help="Milliseconds to sleep between API calls (protects external APIs).",
    ),
    verbose: bool = typer.Option(False, "--verbose", "-v"),
) -> None:
    """
    Resolve cross-source player IDs for all players in the pending enrichment
    queue (stg.v_players_pending_enrichment).

    Resolution priority:
      1. Chadwick Register in-process cache  (historical authority)
      2. MLB StatsAPI xrefId               (modern/active players)
      3. pybaseball playerid_lookup         (name-based fallback)
      4. Flag for human review             (all else fails)

    After enrichment, calls stg.fn_reconcile_candidates() to auto-promote
    candidates above --min-confidence and surfaces the rest in
    stg.v_candidates_pending_human_review.
    """
    if verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    if dry_run:
        console.print("[bold yellow]DRY RUN — no database writes will occur.[/bold yellow]")

    stats = run_enrichment(
        database_url=database_url,
        limit=limit,
        min_confidence=min_confidence,
        dry_run=dry_run,
        chadwick_csv=chadwick_seed,
        skip_chadwick_load=skip_chadwick_load,
        rate_limit_ms=rate_limit_ms,
    )

    _print_stats(stats)

    if stats.errors > 0:
        console.print(f"[bold red]{stats.errors} errors occurred — check logs.[/bold red]")
        raise typer.Exit(code=1)


if __name__ == "__main__":
    app()
