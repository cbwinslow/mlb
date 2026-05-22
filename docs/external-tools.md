# External Data Sources & Player ID Reference

## Overview

All external IDs are attributes on `stg.player_identity`. The internal
`player_identity_id` is the warehouse's permanent business key — never store
an external ID as a foreign key in fact tables.

Resolution priority order:

1. **Chadwick Register** — seed historical crosswalk (bulk, one-time + weekly refresh)
2. **MLB StatsAPI `people/xrefId`** — resolve modern/active players by MLBAM id
3. **pybaseball `playerid_lookup()`** — name-based fallback when StatsAPI returns no xref
4. **Manual review via `stg.v_candidates_pending_human_review`** — last resort

---

## Source Reference Table

| Source | What it provides | Key IDs | Update frequency | How we load it |
|---|---|---|---|---|
| [Chadwick Bureau Register](https://github.com/chadwickbureau/register) | Comprehensive cross-source player authority. Historical + active players. | `key_mlbam`, `key_retro`, `key_bbref`, `key_fangraphs`, `key_lahman`, birth info | Weekly (GitHub release) | `COPY stg.chadwick_register_import FROM 'people.csv' CSV HEADER;` then `stg.fn_cross_validate_identities()` |
| [MLB StatsAPI](https://statsapi.mlb.com/api/v1/people/{id}?hydrate=xrefId) | Official MLBAM IDs, active roster metadata, xref to Retrosheet/Lahman where MLB has them | `mlbam_player_id`, partial xrefs | Real-time | Python `statsapi.lookup_player(mlbam_id)` |
| [pybaseball `playerid_lookup`](https://github.com/jldbc/pybaseball) | Name -> all IDs crosswalk backed by Smart Fantasy Baseball player ID map | All five ID systems | Pulled on demand | Python `pybaseball.playerid_lookup(last, first)` |
| [Lahman Database `People` table](http://www.seanlahman.com/baseball-archive/statistics/) | Historical player bio (birth date, bats/throws, debut, career span) | `lahman_player_id` (e.g. `ruthba01`) | Annual release | Bulk CSV load into `raw_lahman.people` |
| [Retrosheet Game Logs / Bio](https://www.retrosheet.org/biofile.htm) | Historical game-level event data, player bio file | `retrosheet_player_id` (e.g. `ruthb101`) | Annual/event file | Bulk CSV load into `raw_retrosheet.*` |
| [Baseball Reference](https://www.baseball-reference.com/) | Comprehensive stats, WAR | `bbref_player_id` (e.g. `ruthba01`) | Via Chadwick; never scraped directly | Chadwick `key_bbref` column |
| [FanGraphs](https://www.fangraphs.com/) | Advanced metrics (FIP, xFIP, wRC+, etc.) | `fangraphs_player_id` (numeric string) | Via Chadwick or pybaseball | Chadwick `key_fangraphs` column |

---

## ID Format Reference

| ID system | Column in `stg.player_identity` | Format | Example |
|---|---|---|---|
| MLBAM / Statcast | `mlbam_player_id` | Integer | `592450` |
| Retrosheet | `retrosheet_player_id` | `last5first2NN` | `ruthba01` |
| Baseball Reference | `bbref_player_id` | Same as Retrosheet in most cases | `ruthba01` |
| FanGraphs | `fangraphs_player_id` | Numeric string | `1234` |
| Lahman | `lahman_player_id` | `last5first2NN` | `ruthba01` |

> **Note:** Retrosheet, BRef, and Lahman IDs are often identical for the same
> player but are maintained as separate columns because they can diverge,
> particularly for players active before systematic cross-referencing.

---

## Chadwick Register — Seed & Refresh Procedure

```bash
# 1. Download latest release
curl -L https://github.com/chadwickbureau/register/releases/latest/download/people.csv \
     -o /tmp/chadwick_people.csv

# 2. Truncate staging import table
psql $DATABASE_URL -c "TRUNCATE stg.chadwick_register_import;"

# 3. Bulk load
psql $DATABASE_URL -c "\\COPY stg.chadwick_register_import FROM '/tmp/chadwick_people.csv' CSV HEADER;"

# 4. Cross-validate and review divergences
psql $DATABASE_URL -c "SELECT * FROM stg.fn_cross_validate_identities() LIMIT 50;"

# 5. Apply clean matches (review suggested_action column first)
# psql $DATABASE_URL -c "SELECT suggested_action FROM stg.fn_cross_validate_identities();"
# Then pipe those UPDATE statements to psql after review.
```

---

## Python Enrichment Worker — ID Resolution Priority

```python
import statsapi
import pybaseball

def resolve_player_ids(mlbam_id: int, player_name: str) -> dict:
    """
    Returns cross-source IDs and a confidence score.
    Priority: MLB StatsAPI xref -> pybaseball -> flag for manual review.
    Insert result into stg.player_identity_candidate, then call
    stg.fn_reconcile_candidates() to auto-promote or flag for human review.
    """
    # Priority 1: MLB StatsAPI xrefId
    try:
        people = statsapi.lookup_player(mlbam_id)
        if people:
            p = people[0]
            xrefs = p.get('xrefIds', {})
            if xrefs.get('retrosheet') or xrefs.get('bbref'):
                return {
                    'key_mlbam':     mlbam_id,
                    'key_retro':     xrefs.get('retrosheet'),
                    'key_bbref':     xrefs.get('bbref'),
                    'key_lahman':    xrefs.get('lahman'),
                    'key_fangraphs': xrefs.get('fangraphs'),
                    'confidence':    0.92,
                    'source':        'mlb_statsapi:xref'
                }
    except Exception:
        pass

    # Priority 2: pybaseball name lookup
    try:
        parts = player_name.strip().split()
        last, first = parts[-1], parts[0] if len(parts) > 1 else ''
        result = pybaseball.playerid_lookup(last, first)
        if not result.empty:
            row = result.iloc[0]
            return {
                'key_mlbam':     int(row.get('key_mlbam', mlbam_id)),
                'key_retro':     row.get('key_retro'),
                'key_bbref':     row.get('key_bbref'),
                'key_lahman':    row.get('key_lahman'),
                'key_fangraphs': str(int(row['key_fangraphs'])) if row.get('key_fangraphs') else None,
                'confidence':    0.80,
                'source':        'pybaseball:name_lookup'
            }
    except Exception:
        pass

    # Priority 3: flag for manual review
    return {
        'key_mlbam':     mlbam_id,
        'key_retro':     None,
        'key_bbref':     None,
        'key_lahman':    None,
        'key_fangraphs': None,
        'confidence':    0.30,
        'source':        'unresolved:needs_manual_review'
    }
```

After building results, insert into `stg.player_identity_candidate`, then call:

```sql
SELECT * FROM stg.fn_reconcile_candidates();
```

This auto-promotes scores >= 0.85 and flags the rest for human review in
`stg.v_candidates_pending_human_review`.

---

## Confidence Score Scale

| Score range | Meaning | DB action |
|---|---|---|
| `0.00` | Auto-inserted placeholder, never enriched | Pending enrichment queue |
| `0.01–0.49` | Enrichment attempted, low confidence | Manual review queue |
| `0.50–0.59` | Partial match (name only or single-source) | Manual review queue |
| `0.60–0.79` | Good match (MLBAM confirmed, some xrefs) | Live missing historical IDs view |
| `0.80–0.94` | Strong match (MLBAM + 2+ xrefs confirmed) | Auto-promote eligible |
| `0.95–1.00` | Authoritative (Chadwick confirmed + StatsAPI) | Fully resolved |

Auto-promotion threshold in `stg.fn_reconcile_candidates()` defaults to `0.85`.
Override: `SELECT * FROM stg.fn_reconcile_candidates(0.90);`

---

## Live Player to Historical ID Gap (Normal Behavior)

When a new MLB player debuts:

1. Statcast assigns an MLBAM id immediately.
2. The DB trigger inserts a `confidence = 0` placeholder.
3. MLB StatsAPI `people/xrefId` may return partial xrefs within days.
4. **Retrosheet, BRef, and Lahman IDs will not exist until those registers publish their next release** — expected and normal.
5. The player appears in `stg.v_live_players_pending_historical_ids` until the next Chadwick weekly refresh fills them in.

Do not treat a NULL `retrosheet_player_id` for a current-season player as an error.

---

## Validation Quick Reference

| What to check | Query |
|---|---|
| Overall ID fill rates | `SELECT * FROM stg.fn_validate_identity_completeness();` |
| Trigger health (must always be 0 rows) | `SELECT * FROM stg.fn_detect_orphaned_pitches();` |
| Compare vs. Chadwick | `SELECT * FROM stg.fn_cross_validate_identities();` |
| Full ops dashboard | `SELECT * FROM stg.v_identity_validation_dashboard;` |
| Full JSON health report | `SELECT stg.fn_full_identity_health_report();` |
| Find player by game context | `SELECT * FROM stg.fn_pinpoint_player_by_context('2024-07-15', 'NYY', 3, 2);` |
| Validate a game lineup | `SELECT * FROM stg.fn_validate_game_lineup('2024-07-15', 532441) WHERE flag LIKE 'WARN%';` |
| Contextual fingerprint check | `SELECT * FROM stg.fn_contextual_fingerprint_check('2024-07-15', 532441);` |
| Human review queue | `SELECT * FROM stg.v_candidates_pending_human_review;` |
| Manually update a player | `CALL stg.update_player_identity(42, 'ruthba01', 'ruthba01', '1234', 'ruthba01', 0.95, 'manual:dba');` |
| Process enrichment candidates | `SELECT * FROM stg.fn_reconcile_candidates();` |
