#!/usr/bin/env python3
"""
enrich_player_identity.py

Player identity enrichment worker for the MLB warehouse.

Modes:
  --mode seed-chadwick   Download Chadwick register CSV and COPY into
                         stg.chadwick_register_import, then bulk-upsert
                         known IDs into stg.player_identity.

  --mode enrich          Poll stg.v_players_pending_enrichment and attempt
                         to resolve each player's cross-source IDs via:
                           1. MLB StatsAPI xrefIds
                           2. pybaseball.playerid_lookup (exact name match)
                           3. pybaseball.playerid_lookup (fuzzy match)
                         Inserts candidates into stg.player_identity_candidate;
                         high-confidence candidates are auto-promoted by
                         stg.fn_reconcile_candidates().

  --mode reconcile       Call stg.fn_reconcile_candidates() to promote
                         high-confidence candidates and flag low-confidence
                         ones for human review.

  --mode health          Print the JSON health report from
                         stg.fn_full_identity_health_report().

Environment variables:
  DATABASE_URL           PostgreSQL DSN (required)
                         e.g. postgresql://user:pass@host:5432/mlb

Usage:
  python scripts/enrich_player_identity.py --mode enrich --limit 500
  python scripts/enrich_player_identity.py --mode seed-chadwick
  python scripts/enrich_player_identity.py --mode health
"""

from __future__ import annotations

import argparse
import io
import json
import logging
import os
import sys
from typing import Optional

import psycopg2
import psycopg2.extras
import requests

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
log = logging.getLogger(__name__)

CHADWICK_URL = (
    "https://raw.githubusercontent.com/chadwickbureau/register/master/data/people.csv"
)

AUTO_THRESHOLD = 0.85  # candidates >= this are auto-promoted by fn_reconcile_candidates
FUZZY_THRESHOLD = 0.60  # below this, candidate is flagged for human review


# ---------------------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------------------


def get_connection() -> psycopg2.extensions.connection:
    dsn = os.environ.get("DATABASE_URL")
    if not dsn:
        log.error("DATABASE_URL environment variable is not set.")
        sys.exit(1)
    return psycopg2.connect(dsn)


# ---------------------------------------------------------------------------
# Source 1: MLB Stats API
# ---------------------------------------------------------------------------


def resolve_via_mlb_api(mlbam_id: int) -> dict:
    """
    Query the MLB Stats API for a player by MLBAM ID.
    Returns a dict with resolved cross-source IDs or {} on failure.
    Confidence: 0.90 when xrefIds present, 0.75 when MLBAM-only.
    """
    try:
        import statsapi  # python-mlb-statsapi

        people = statsapi.lookup_player(mlbam_id)
        if not people:
            return {}
        person = people[0]
        xref = person.get("xrefIds") or {}
        score = 0.90 if any(xref.values()) else 0.75
        return {
            "key_mlbam": person["id"],
            "full_name": person.get("fullName"),
            "birth_date": person.get("birthDate"),
            "key_retro": xref.get("retrosheet"),
            "key_lahman": xref.get("lahman"),
            "key_bbref": xref.get("bbref"),
            "key_fangraphs": xref.get("fangraphs"),
            "score": score,
            "source": "mlb_statsapi:xref",
            "reason": f"MLB StatsAPI lookup for mlbam_id={mlbam_id}",
        }
    except Exception as exc:
        log.debug("MLB StatsAPI lookup failed for %s: %s", mlbam_id, exc)
        return {}


# ---------------------------------------------------------------------------
# Source 2 & 3: pybaseball playerid_lookup
# ---------------------------------------------------------------------------


def resolve_via_pybaseball(
    last_name: str, first_name: str, fuzzy: bool = False
) -> dict:
    """
    Query pybaseball.playerid_lookup by name.
    Returns a dict with resolved IDs or {} on no match.
    Confidence: 0.85 exact, 0.60 fuzzy.
    """
    if not last_name:
        return {}
    try:
        import pandas as pd
        from pybaseball import playerid_lookup

        df = playerid_lookup(last_name, first_name, fuzzy=fuzzy)
        if df.empty:
            return {}
        row = df.iloc[0]
        score = 0.60 if fuzzy else 0.85

        def safe_int(val) -> Optional[int]:
            try:
                return int(val) if pd.notna(val) else None
            except (ValueError, TypeError):
                return None

        def safe_str(val) -> Optional[str]:
            try:
                return str(int(val)) if pd.notna(val) else None
            except (ValueError, TypeError):
                return str(val) if pd.notna(val) else None

        return {
            "key_mlbam": safe_int(row.get("key_mlbam")),
            "key_retro": safe_str(row.get("key_retro")),
            "key_bbref": safe_str(row.get("key_bbref")),
            "key_fangraphs": safe_str(row.get("key_fangraphs")),
            "key_lahman": safe_str(row.get("key_lahmanid")),
            "score": score,
            "source": f"pybaseball:{'fuzzy' if fuzzy else 'exact'}",
            "reason": f"pybaseball.playerid_lookup('{last_name}', '{first_name}', fuzzy={fuzzy})",
        }
    except Exception as exc:
        log.debug("pybaseball lookup failed for %s %s: %s", first_name, last_name, exc)
        return {}


def name_to_parts(full_name: Optional[str]) -> tuple[str, str]:
    """Split 'Firstname Lastname' into (last, first). Handles None gracefully."""
    if not full_name:
        return ("", "")
    parts = full_name.strip().split()
    if len(parts) == 1:
        return (parts[0], "")
    return (parts[-1], parts[0])


# ---------------------------------------------------------------------------
# Mode: enrich
# ---------------------------------------------------------------------------


def run_enrich(conn, limit: int = 500) -> None:
    """
    Poll stg.v_players_pending_enrichment and attempt to resolve each player.
    Writes candidates to stg.player_identity_candidate.
    Then calls fn_reconcile_candidates() to auto-promote high-confidence rows.
    """
    with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
        cur.execute(
            """
            SELECT player_identity_id, mlbam_player_id, full_name
            FROM   stg.v_players_pending_enrichment
            LIMIT  %s
            """,
            (limit,),
        )
        pending = cur.fetchall()

    log.info("Enriching %d pending players.", len(pending))
    resolved = 0
    flagged = 0

    with conn.cursor() as cur:
        for row in pending:
            mlbam_id = row["mlbam_player_id"]
            full_name = row["full_name"]
            last, first = name_to_parts(full_name)

            # --- Resolution cascade ---
            result = (
                resolve_via_mlb_api(mlbam_id)
                or resolve_via_pybaseball(last, first, fuzzy=False)
                or resolve_via_pybaseball(last, first, fuzzy=True)
            )

            if not result:
                log.warning(
                    "No resolution found for mlbam_id=%s name=%r — flagging for manual review.",
                    mlbam_id,
                    full_name,
                )
                # Insert a zero-score candidate so it appears in v_candidates_pending_human_review
                cur.execute(
                    """
                    INSERT INTO stg.player_identity_candidate (
                        source_system_code, source_natural_key,
                        mlbam_player_id, candidate_name,
                        candidate_score, candidate_reason,
                        reviewed_flag, accepted_flag
                    ) VALUES (
                        'enrichment_worker', %s::TEXT,
                        %s, %s,
                        0.0, 'All resolution methods exhausted — manual lookup required',
                        TRUE, NULL
                    )
                    ON CONFLICT DO NOTHING
                    """,
                    (mlbam_id, mlbam_id, full_name),
                )
                # Write to resolution log
                cur.execute(
                    """
                    INSERT INTO stg.player_identity_resolution_log (
                        trigger_source, mlbam_player_id, player_name,
                        action_taken, player_identity_id, note
                    ) VALUES (
                        'enrich_player_identity.py', %s, %s,
                        'ENRICHMENT_FAILED_MANUAL_REVIEW_REQUIRED',
                        %s,
                        'All sources exhausted. Check stg.v_candidates_pending_human_review.'
                    )
                    """,
                    (mlbam_id, full_name, row["player_identity_id"]),
                )
                flagged += 1
                conn.commit()
                continue

            score = result.get("score", 0.70)
            source = result.get("source", "unknown")
            reason = result.get("reason", "")

            # Insert candidate row
            cur.execute(
                """
                INSERT INTO stg.player_identity_candidate (
                    source_system_code, source_natural_key,
                    mlbam_player_id,
                    retrosheet_player_id,
                    lahman_player_id,
                    bbref_player_id,
                    fangraphs_player_id,
                    candidate_name,
                    candidate_birth_date,
                    candidate_score,
                    candidate_reason,
                    reviewed_flag
                ) VALUES (
                    %s, %s::TEXT,
                    %s, %s, %s, %s, %s,
                    %s, %s::DATE,
                    %s, %s,
                    FALSE
                )
                ON CONFLICT DO NOTHING
                """,
                (
                    source,
                    mlbam_id,
                    result.get("key_mlbam") or mlbam_id,
                    result.get("key_retro"),
                    result.get("key_lahman"),
                    result.get("key_bbref"),
                    result.get("key_fangraphs"),
                    result.get("full_name") or full_name,
                    result.get("birth_date"),
                    score,
                    reason,
                ),
            )
            resolved += 1
            conn.commit()
            log.debug(
                "Candidate inserted: mlbam=%s name=%r score=%.2f source=%s",
                mlbam_id,
                full_name,
                score,
                source,
            )

    log.info(
        "Enrichment complete. Resolved: %d  Flagged for manual review: %d",
        resolved,
        flagged,
    )

    # Auto-promote high-confidence candidates
    log.info("Running fn_reconcile_candidates()...")
    with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
        cur.execute(
            "SELECT * FROM stg.fn_reconcile_candidates(%s, %s)", (AUTO_THRESHOLD, limit)
        )
        results = cur.fetchall()
        promoted = sum(1 for r in results if r["action"] == "AUTO_PROMOTED")
        review = sum(1 for r in results if r["action"] == "FLAGGED_FOR_REVIEW")
        log.info("Reconcile: auto-promoted=%d flagged_for_review=%d", promoted, review)
    conn.commit()


# ---------------------------------------------------------------------------
# Mode: seed-chadwick
# ---------------------------------------------------------------------------


def run_seed_chadwick(conn) -> None:
    """
    Download the Chadwick register CSV, TRUNCATE stg.chadwick_register_import,
    bulk-load it, then upsert known IDs into stg.player_identity.
    """
    log.info("Downloading Chadwick register from %s", CHADWICK_URL)
    resp = requests.get(CHADWICK_URL, timeout=60)
    resp.raise_for_status()
    csv_bytes = resp.content
    log.info("Downloaded %.1f KB", len(csv_bytes) / 1024)

    with conn.cursor() as cur:
        # Reload import staging table
        cur.execute("TRUNCATE stg.chadwick_register_import")
        cur.copy_expert(
            """
            COPY stg.chadwick_register_import (
                key_mlbam, key_retro, key_bbref, key_fangraphs, key_lahman,
                name_first, name_last, name_given,
                birth_year, birth_month, birth_day,
                mlb_played_first, mlb_played_last
            )
            FROM STDIN
            WITH (FORMAT CSV, HEADER TRUE, NULL '')
            """,
            io.BytesIO(csv_bytes),
        )
        cur.execute("SELECT COUNT(*) FROM stg.chadwick_register_import")
        count = cur.fetchone()[0]
        log.info("Loaded %d rows into stg.chadwick_register_import", count)

        # Bulk-upsert into stg.player_identity for all rows that have an MLBAM ID
        cur.execute(
            """
            INSERT INTO stg.player_identity (
                mlbam_player_id,
                retrosheet_player_id,
                bbref_player_id,
                fangraphs_player_id,
                lahman_player_id,
                first_name,
                last_name,
                full_name,
                identity_confidence_score,
                identity_source
            )
            SELECT
                key_mlbam,
                key_retro,
                key_bbref,
                key_fangraphs::TEXT,
                key_lahman,
                name_first,
                name_last,
                TRIM(COALESCE(name_first,'') || ' ' || COALESCE(name_last,'')),
                0.90,
                'chadwick:seed'
            FROM stg.chadwick_register_import
            WHERE key_mlbam IS NOT NULL
            ON CONFLICT (mlbam_player_id)
            WHERE mlbam_player_id IS NOT NULL
            DO UPDATE SET
                retrosheet_player_id   = COALESCE(EXCLUDED.retrosheet_player_id,  stg.player_identity.retrosheet_player_id),
                bbref_player_id        = COALESCE(EXCLUDED.bbref_player_id,        stg.player_identity.bbref_player_id),
                fangraphs_player_id    = COALESCE(EXCLUDED.fangraphs_player_id,    stg.player_identity.fangraphs_player_id),
                lahman_player_id       = COALESCE(EXCLUDED.lahman_player_id,       stg.player_identity.lahman_player_id),
                first_name             = COALESCE(EXCLUDED.first_name,             stg.player_identity.first_name),
                last_name              = COALESCE(EXCLUDED.last_name,              stg.player_identity.last_name),
                full_name              = COALESCE(EXCLUDED.full_name,              stg.player_identity.full_name),
                identity_confidence_score = GREATEST(
                    EXCLUDED.identity_confidence_score,
                    stg.player_identity.identity_confidence_score
                ),
                identity_source        = 'chadwick:seed',
                updated_at             = NOW()
            WHERE stg.player_identity.identity_confidence_score < 0.90
            """
        )
        seeded = cur.rowcount
        log.info("Upserted %d rows into stg.player_identity from Chadwick seed", seeded)

    conn.commit()
    log.info("Chadwick seed complete. Run stg.fn_cross_validate_identities() to diff.")


# ---------------------------------------------------------------------------
# Mode: reconcile
# ---------------------------------------------------------------------------


def run_reconcile(conn, threshold: float = AUTO_THRESHOLD, limit: int = 500) -> None:
    with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
        cur.execute(
            "SELECT * FROM stg.fn_reconcile_candidates(%s, %s)", (threshold, limit)
        )
        results = cur.fetchall()
    conn.commit()
    promoted = sum(1 for r in results if r["action"] == "AUTO_PROMOTED")
    review = sum(1 for r in results if r["action"] == "FLAGGED_FOR_REVIEW")
    log.info(
        "Reconcile: total=%d auto_promoted=%d flagged_for_review=%d",
        len(results),
        promoted,
        review,
    )
    if review:
        log.info(
            "Run: SELECT * FROM stg.v_candidates_pending_human_review; to see flagged rows."
        )


# ---------------------------------------------------------------------------
# Mode: health
# ---------------------------------------------------------------------------


def run_health(conn) -> None:
    with conn.cursor() as cur:
        cur.execute("SELECT stg.fn_full_identity_health_report()")
        report = cur.fetchone()[0]
    conn.commit()
    print(json.dumps(report, indent=2, default=str))
    critical = report.get("critical_alert", False)
    if critical:
        log.error(
            "CRITICAL ALERT: orphaned_pitches_48h=%s — trigger may be broken!",
            report.get("orphaned_pitches_48h"),
        )
        sys.exit(2)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(description="Player identity enrichment worker")
    parser.add_argument(
        "--mode",
        choices=["enrich", "seed-chadwick", "reconcile", "health"],
        required=True,
        help="Operation mode",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=500,
        help="Max rows to process (enrich/reconcile modes)",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=AUTO_THRESHOLD,
        help="Auto-promote confidence threshold (reconcile mode, default 0.85)",
    )
    args = parser.parse_args()

    conn = get_connection()
    try:
        if args.mode == "enrich":
            run_enrich(conn, limit=args.limit)
        elif args.mode == "seed-chadwick":
            run_seed_chadwick(conn)
        elif args.mode == "reconcile":
            run_reconcile(conn, threshold=args.threshold, limit=args.limit)
        elif args.mode == "health":
            run_health(conn)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
