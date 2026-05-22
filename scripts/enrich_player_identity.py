#!/usr/bin/env python3
"""
enrich_player_identity.py
=========================
Player identity enrichment worker for the MLB data warehouse.

Reads stg.v_players_pending_enrichment from the database, attempts to resolve
cross-source player IDs using the following priority chain:

  1. MLB Stats API  xrefId endpoint        (confidence 0.90)  — best for modern players
  2. pybaseball     playerid_lookup()       (confidence 0.80)  — name-based lookup
  3. Chadwick       raw.chadwick_register   (confidence 0.85)  — direct DB lookup
  4. Name fuzzy     pg_trgm similarity      (confidence 0.55)  — last-resort heuristic

For each player resolved, writes a candidate row to stg.player_identity_candidate.
After processing the batch, calls stg.fn_reconcile_candidates() which auto-promotes
candidates with score >= auto_threshold (default 0.85) and flags the rest for
human review in stg.v_candidates_pending_human_review.

Usage:
    python enrich_player_identity.py
    python enrich_player_identity.py --batch-size 200 --dry-run
    python enrich_player_identity.py --min-confidence 0.70 --reconcile-after
    python enrich_player_identity.py --chadwick-refresh /tmp/people.csv

Environment variables (or .env file):
    MLB_DB_DSN          PostgreSQL DSN, e.g. postgresql://user:pass@host:5432/mlb
    MLB_STATS_API_BASE  Base URL for MLB Stats API (default https://statsapi.mlb.com)
    LOG_LEVEL           DEBUG | INFO | WARNING | ERROR (default INFO)

Dependencies:
    psycopg2-binary
    pybaseball
    requests
    python-dotenv
    rapidfuzz          (optional; used for fuzzy name matching fallback)
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import logging
import os
import sys
import time
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import Optional

import psycopg2
import psycopg2.extras
import requests

try:
    import pybaseball
    PYBASEBALL_AVAILABLE = True
except ImportError:
    PYBASEBALL_AVAILABLE = False
    logging.warning("pybaseball not installed — name-lookup fallback disabled")

try:
    from rapidfuzz import fuzz
    RAPIDFUZZ_AVAILABLE = True
except ImportError:
    RAPIDFUZZ_AVAILABLE = False

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

MLB_STATS_API_BASE = os.getenv("MLB_STATS_API_BASE", "https://statsapi.mlb.com")
DB_DSN = os.getenv("MLB_DB_DSN", "")
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format=json.dumps({
        "time": "%(asctime)s",
        "level": "%(levelname)s",
        "msg": "%(message)s",
    }),
    stream=sys.stdout,
)
log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class PendingPlayer:
    player_identity_id: int
    mlbam_player_id: int
    full_name: Optional[str]


@dataclass
class ResolvedCandidate:
    mlbam_player_id: int
    candidate_name: Optional[str]
    retrosheet_player_id: Optional[str] = None
    bbref_player_id: Optional[str] = None
    fangraphs_player_id: Optional[int] = None
    lahman_player_id: Optional[str] = None
    candidate_birth_date: Optional[date] = None
    candidate_score: float = 0.0
    candidate_reason: str = ""
    source_system_code: str = ""


# ---------------------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------------------

def get_connection() -> psycopg2.extensions.connection:
    if not DB_DSN:
        raise RuntimeError(
            "MLB_DB_DSN environment variable not set. "
            "Set it to a valid PostgreSQL DSN before running."
        )
    return psycopg2.connect(DB_DSN, cursor_factory=psycopg2.extras.RealDictCursor)


def fetch_pending_players(
    conn: psycopg2.extensions.connection,
    batch_size: int = 500,
) -> list[PendingPlayer]:
    """Read the enrichment work queue from the database."""
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT player_identity_id, mlbam_player_id, full_name
            FROM   stg.v_players_pending_enrichment
            ORDER  BY times_seen_in_statcast DESC, first_seen_at
            LIMIT  %s
            """,
            (batch_size,),
        )
        rows = cur.fetchall()
    return [
        PendingPlayer(
            player_identity_id=r["player_identity_id"],
            mlbam_player_id=r["mlbam_player_id"],
            full_name=r["full_name"],
        )
        for r in rows
    ]


def write_candidate(
    conn: psycopg2.extensions.connection,
    candidate: ResolvedCandidate,
    dry_run: bool = False,
) -> None:
    """Insert a resolved candidate into stg.player_identity_candidate."""
    if dry_run:
        log.info("[DRY RUN] would write candidate: %s", candidate)
        return

    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO stg.player_identity_candidate (
                mlbam_player_id,
                candidate_name,
                retrosheet_player_id,
                bbref_player_id,
                fangraphs_player_id,
                lahman_player_id,
                candidate_birth_date,
                candidate_score,
                candidate_reason,
                source_system_code,
                reviewed_flag,
                accepted_flag
            ) VALUES (
                %(mlbam)s, %(name)s, %(retro)s, %(bbref)s,
                %(fg)s, %(lahman)s, %(birth)s,
                %(score)s, %(reason)s, %(source)s,
                FALSE, NULL
            )
            ON CONFLICT (mlbam_player_id, source_system_code)
            DO UPDATE SET
                retrosheet_player_id = EXCLUDED.retrosheet_player_id,
                bbref_player_id      = EXCLUDED.bbref_player_id,
                fangraphs_player_id  = EXCLUDED.fangraphs_player_id,
                lahman_player_id     = EXCLUDED.lahman_player_id,
                candidate_score      = GREATEST(
                    stg.player_identity_candidate.candidate_score,
                    EXCLUDED.candidate_score
                ),
                candidate_reason     = EXCLUDED.candidate_reason,
                reviewed_flag        = FALSE,
                accepted_flag        = NULL
            """,
            {
                "mlbam":  candidate.mlbam_player_id,
                "name":   candidate.candidate_name,
                "retro":  candidate.retrosheet_player_id,
                "bbref":  candidate.bbref_player_id,
                "fg":     candidate.fangraphs_player_id,
                "lahman": candidate.lahman_player_id,
                "birth":  candidate.candidate_birth_date,
                "score":  candidate.candidate_score,
                "reason": candidate.candidate_reason,
                "source": candidate.source_system_code,
            },
        )
    conn.commit()


def run_reconcile(
    conn: psycopg2.extensions.connection,
    auto_threshold: float = 0.85,
    dry_run: bool = False,
) -> list[dict]:
    """Call stg.fn_reconcile_candidates() and return results."""
    if dry_run:
        log.info("[DRY RUN] skipping fn_reconcile_candidates()")
        return []
    with conn.cursor() as cur:
        cur.execute(
            "SELECT * FROM stg.fn_reconcile_candidates(%s, 500)",
            (auto_threshold,),
        )
        results = [dict(r) for r in cur.fetchall()]
    conn.commit()
    return results


# ---------------------------------------------------------------------------
# Resolution methods
# ---------------------------------------------------------------------------

def resolve_via_mlb_statsapi(mlbam_id: int) -> Optional[ResolvedCandidate]:
    """
    Query MLB Stats API person xref endpoint.
    Returns cross-source IDs for a known MLBAM person ID.

    Endpoint: GET /api/v1/people/{personId}?hydrate=xrefIds
    Relevant xref types: 'retrosheet', 'bbref', 'fangraphs', 'lahman'
    """
    url = f"{MLB_STATS_API_BASE}/api/v1/people/{mlbam_id}"
    params = {"hydrate": "xrefIds"}

    try:
        resp = requests.get(url, params=params, timeout=10)
        resp.raise_for_status()
        data = resp.json()
    except (requests.RequestException, ValueError) as exc:
        log.debug("StatsAPI request failed for mlbam=%s: %s", mlbam_id, exc)
        return None

    people = data.get("people", [])
    if not people:
        return None

    person = people[0]
    xrefs = {x.get("xrefType", ""): x.get("xrefId") for x in person.get("xrefIds", [])}

    full_name = person.get("fullName") or (
        f"{person.get('firstName', '')} {person.get('lastName', '')}".strip() or None
    )
    birth_date_str = person.get("birthDate")
    birth_date = None
    if birth_date_str:
        try:
            birth_date = date.fromisoformat(birth_date_str[:10])
        except ValueError:
            pass

    fangraphs_id = xrefs.get("fangraphs")
    try:
        fangraphs_id = int(fangraphs_id) if fangraphs_id else None
    except (ValueError, TypeError):
        fangraphs_id = None

    candidate = ResolvedCandidate(
        mlbam_player_id=mlbam_id,
        candidate_name=full_name,
        retrosheet_player_id=xrefs.get("retrosheet"),
        bbref_player_id=xrefs.get("bbref"),
        fangraphs_player_id=fangraphs_id,
        lahman_player_id=xrefs.get("lahman"),
        candidate_birth_date=birth_date,
        candidate_score=0.90,
        candidate_reason="MLB StatsAPI xrefId lookup",
        source_system_code="statsapi",
    )

    # Must have resolved at least one cross-source ID to count
    if not any([
        candidate.retrosheet_player_id,
        candidate.bbref_player_id,
        candidate.fangraphs_player_id,
        candidate.lahman_player_id,
    ]):
        log.debug("StatsAPI returned no xref IDs for mlbam=%s", mlbam_id)
        return None

    return candidate


def resolve_via_pybaseball(full_name: Optional[str], mlbam_id: int) -> Optional[ResolvedCandidate]:
    """
    Use pybaseball.playerid_lookup() for name-based resolution.
    Matches result rows back to the MLBAM id to confirm correctness.
    """
    if not PYBASEBALL_AVAILABLE or not full_name:
        return None

    parts = full_name.strip().split()
    if len(parts) < 2:
        return None

    last = parts[-1]
    first = parts[0]

    try:
        result = pybaseball.playerid_lookup(last, first, fuzzy=False)
    except Exception as exc:
        log.debug("pybaseball lookup failed for '%s': %s", full_name, exc)
        return None

    if result is None or result.empty:
        # Try fuzzy as fallback
        try:
            result = pybaseball.playerid_lookup(last, first, fuzzy=True)
        except Exception:
            return None

    if result is None or result.empty:
        return None

    # Filter to the row matching our MLBAM id
    matched = result[result["key_mlbam"] == mlbam_id]
    if matched.empty:
        # Use first result if MLBAM matches nothing — lower confidence
        row = result.iloc[0]
        score = 0.60
        reason = f"pybaseball name lookup (unconfirmed MLBAM match) for '{full_name}'"
    else:
        row = matched.iloc[0]
        score = 0.80
        reason = f"pybaseball playerid_lookup confirmed MLBAM match for '{full_name}'"

    def safe_int(val) -> Optional[int]:
        try:
            v = int(val)
            return v if v > 0 else None
        except (TypeError, ValueError):
            return None

    def safe_str(val) -> Optional[str]:
        v = str(val).strip() if val is not None else ""
        return v if v and v not in ("nan", "None", "0") else None

    return ResolvedCandidate(
        mlbam_player_id=mlbam_id,
        candidate_name=full_name,
        retrosheet_player_id=safe_str(row.get("key_retro")),
        bbref_player_id=safe_str(row.get("key_bbref")),
        fangraphs_player_id=safe_int(row.get("key_fangraphs")),
        lahman_player_id=safe_str(row.get("key_lahman")),
        candidate_score=score,
        candidate_reason=reason,
        source_system_code="pybaseball",
    )


def resolve_via_chadwick_db(
    conn: psycopg2.extensions.connection,
    mlbam_id: int,
    full_name: Optional[str],
) -> Optional[ResolvedCandidate]:
    """
    Direct lookup against raw.chadwick_register already loaded in the database.
    First tries exact MLBAM match; falls back to name match if available.
    """
    with conn.cursor() as cur:
        # Try exact MLBAM match
        cur.execute(
            """
            SELECT
                NULLIF(TRIM(key_retro),     '') AS retro,
                NULLIF(TRIM(key_bbref),     '') AS bbref,
                NULLIF(TRIM(key_fangraphs), '') AS fangraphs,
                NULLIF(TRIM(key_lahman),    '') AS lahman,
                CONCAT_WS(' ',
                    NULLIF(TRIM(name_first), ''),
                    NULLIF(TRIM(name_last),  '')
                )                               AS full_name,
                birth_year, birth_month, birth_day
            FROM raw.chadwick_register
            WHERE key_mlbam = %s::TEXT
              AND key_mlbam <> ''
            LIMIT 1
            """,
            (str(mlbam_id),),
        )
        row = cur.fetchone()

    if not row:
        # Fallback: name similarity (requires pg_trgm; best-effort)
        if not full_name:
            return None
        parts = full_name.strip().split()
        if len(parts) < 2:
            return None
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    NULLIF(TRIM(key_retro),     '') AS retro,
                    NULLIF(TRIM(key_bbref),     '') AS bbref,
                    NULLIF(TRIM(key_fangraphs), '') AS fangraphs,
                    NULLIF(TRIM(key_lahman),    '') AS lahman,
                    CONCAT_WS(' ',
                        NULLIF(TRIM(name_first), ''),
                        NULLIF(TRIM(name_last),  '')
                    )                               AS full_name,
                    birth_year, birth_month, birth_day
                FROM raw.chadwick_register
                WHERE LOWER(name_last)  = LOWER(%s)
                  AND LOWER(name_first) LIKE LOWER(%s) || '%%'
                LIMIT 1
                """,
                (parts[-1], parts[0]),
            )
            row = cur.fetchone()

        if not row:
            return None
        score = 0.65
        reason = f"Chadwick name match for '{full_name}' (MLBAM not in Chadwick)"
    else:
        score = 0.85
        reason = f"Chadwick direct MLBAM lookup for id={mlbam_id}"

    birth_date = None
    try:
        if all([
            row.get("birth_year"),
            row.get("birth_month"),
            row.get("birth_day"),
        ]):
            birth_date = date(
                int(row["birth_year"]),
                int(row["birth_month"]),
                int(row["birth_day"]),
            )
    except (ValueError, TypeError):
        pass

    fg = row.get("fangraphs")
    try:
        fg = int(fg) if fg else None
    except (ValueError, TypeError):
        fg = None

    return ResolvedCandidate(
        mlbam_player_id=mlbam_id,
        candidate_name=row.get("full_name") or full_name,
        retrosheet_player_id=row.get("retro"),
        bbref_player_id=row.get("bbref"),
        fangraphs_player_id=fg,
        lahman_player_id=row.get("lahman"),
        candidate_birth_date=birth_date,
        candidate_score=score,
        candidate_reason=reason,
        source_system_code="chadwick:db",
    )


def resolve_player(
    conn: psycopg2.extensions.connection,
    player: PendingPlayer,
    min_confidence: float = 0.50,
) -> Optional[ResolvedCandidate]:
    """
    Run the full priority resolution chain for a single player.
    Returns the best candidate found, or None if nothing meets min_confidence.
    """
    # Priority 1: MLB Stats API (most authoritative for modern players)
    candidate = resolve_via_mlb_statsapi(player.mlbam_player_id)
    if candidate and candidate.candidate_score >= min_confidence:
        log.debug(
            "Resolved mlbam=%s via StatsAPI (score=%.2f)",
            player.mlbam_player_id,
            candidate.candidate_score,
        )
        return candidate

    # Priority 2: Chadwick DB (best historical cross-reference)
    candidate = resolve_via_chadwick_db(conn, player.mlbam_player_id, player.full_name)
    if candidate and candidate.candidate_score >= min_confidence:
        log.debug(
            "Resolved mlbam=%s via Chadwick DB (score=%.2f)",
            player.mlbam_player_id,
            candidate.candidate_score,
        )
        return candidate

    # Priority 3: pybaseball name lookup
    if player.full_name:
        candidate = resolve_via_pybaseball(player.full_name, player.mlbam_player_id)
        if candidate and candidate.candidate_score >= min_confidence:
            log.debug(
                "Resolved mlbam=%s via pybaseball (score=%.2f)",
                player.mlbam_player_id,
                candidate.candidate_score,
            )
            return candidate

    # All methods exhausted or confidence too low
    log.info(
        "Could not resolve mlbam=%s name='%s' above min_confidence=%.2f",
        player.mlbam_player_id,
        player.full_name,
        min_confidence,
    )
    return None


# ---------------------------------------------------------------------------
# Chadwick refresh helper
# ---------------------------------------------------------------------------

def load_chadwick_csv(
    conn: psycopg2.extensions.connection,
    csv_path: str,
) -> int:
    """
    Truncates raw.chadwick_register and bulk-loads a new Chadwick people.csv.
    Returns the number of rows loaded.
    """
    path = Path(csv_path)
    if not path.exists():
        raise FileNotFoundError(f"Chadwick CSV not found: {csv_path}")

    log.info("Loading Chadwick CSV from %s", path)
    with conn.cursor() as cur:
        cur.execute("TRUNCATE TABLE raw.chadwick_register")
        with open(path, "r", encoding="utf-8") as f:
            # Use COPY for performance; psycopg2 copy_expert streams the file
            cur.copy_expert(
                "COPY raw.chadwick_register ("
                "  key_person, key_uuid, key_mlbam, key_retro, key_bbref, "
                "  key_bbref_minors, key_fangraphs, key_npb, key_sr_nfl, "
                "  key_sr_nba, key_sr_nhl, key_findagrave, key_lahman, "
                "  name_last, name_first, name_given, name_suffix, "
                "  name_matrilineal, name_nick, "
                "  birth_year, birth_month, birth_day, "
                "  death_year, death_month, death_day, "
                "  pro_played_first, pro_played_last, "
                "  mlb_played_first, mlb_played_last, "
                "  col_played_first, col_played_last, "
                "  pro_managed_first, pro_managed_last, "
                "  pro_umpired_first, pro_umpired_last"
                ") FROM STDIN CSV HEADER",
                f,
            )
        row_count = cur.rowcount
    conn.commit()
    log.info("Loaded %d rows into raw.chadwick_register", row_count)
    return row_count


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="MLB player identity enrichment worker",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=500,
        help="Number of players to process per run (default: 500)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Resolve players but do not write candidates to the database",
    )
    parser.add_argument(
        "--min-confidence",
        type=float,
        default=0.50,
        help="Minimum confidence score to write a candidate (default: 0.50)",
    )
    parser.add_argument(
        "--auto-threshold",
        type=float,
        default=0.85,
        help="Confidence threshold for auto-promotion in fn_reconcile_candidates (default: 0.85)",
    )
    parser.add_argument(
        "--reconcile-after",
        action="store_true",
        default=True,
        help="Call fn_reconcile_candidates() after writing all candidates (default: True)",
    )
    parser.add_argument(
        "--no-reconcile",
        dest="reconcile_after",
        action="store_false",
        help="Skip fn_reconcile_candidates() call at end of run",
    )
    parser.add_argument(
        "--chadwick-refresh",
        metavar="CSV_PATH",
        help="Path to Chadwick people.csv to load before enrichment run",
    )
    parser.add_argument(
        "--sleep-ms",
        type=int,
        default=100,
        help="Milliseconds to sleep between API calls (default: 100ms to avoid rate limits)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if not DB_DSN:
        log.error(
            "MLB_DB_DSN environment variable is required. "
            "Set it to a PostgreSQL DSN before running."
        )
        sys.exit(1)

    conn = get_connection()

    try:
        # Optional: load a fresh Chadwick CSV before enrichment
        if args.chadwick_refresh:
            rows_loaded = load_chadwick_csv(conn, args.chadwick_refresh)
            with conn.cursor() as cur:
                cur.execute("SELECT * FROM stg.fn_refresh_chadwick()")
                result = cur.fetchone()
            conn.commit()
            log.info(
                "Chadwick refresh complete: loaded=%d inspected=%d inserted=%d updated=%d",
                rows_loaded,
                result["rows_inspected"] if result else 0,
                result["rows_inserted"] if result else 0,
                result["rows_updated"] if result else 0,
            )

        # Fetch the pending enrichment work queue
        players = fetch_pending_players(conn, batch_size=args.batch_size)
        log.info("Found %d players pending enrichment", len(players))

        if not players:
            log.info("No players pending enrichment. Exiting.")
            return

        resolved = 0
        unresolved = 0

        for player in players:
            candidate = resolve_player(
                conn=conn,
                player=player,
                min_confidence=args.min_confidence,
            )

            if candidate:
                write_candidate(conn, candidate, dry_run=args.dry_run)
                resolved += 1
            else:
                unresolved += 1

            # Polite sleep between API calls
            if args.sleep_ms > 0:
                time.sleep(args.sleep_ms / 1000.0)

        log.info(
            "Enrichment batch complete: resolved=%d unresolved=%d",
            resolved,
            unresolved,
        )

        # Reconcile: auto-promote high-confidence candidates, flag the rest
        if args.reconcile_after and not args.dry_run:
            results = run_reconcile(conn, auto_threshold=args.auto_threshold)
            promoted = sum(1 for r in results if r.get("action") == "AUTO_PROMOTED")
            flagged = sum(1 for r in results if r.get("action") == "FLAGGED_FOR_REVIEW")
            log.info(
                "Reconcile complete: auto_promoted=%d flagged_for_review=%d",
                promoted,
                flagged,
            )
            if flagged > 0:
                log.warning(
                    "%d candidates need human review. "
                    "Run: SELECT accept_sql FROM stg.v_candidates_pending_human_review;",
                    flagged,
                )

    finally:
        conn.close()


if __name__ == "__main__":
    main()
