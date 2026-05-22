# External Player Identity Tools Reference

This document describes every external data source used in the player identity
resolution pipeline. All enrichment workers, AI agents, and DBA scripts should
consult this reference before calling external APIs.

---

## Resolution Priority Order

When resolving a player identity, attempt sources in this order:

| Priority | Source | Best for | Coverage |
|----------|--------|----------|----------|
| 1 | Chadwick Bureau Register | Historical crosswalk (seed) | 1800s – present, updated weekly |
| 2 | MLB Stats API `people/xref` | Modern players, real-time debuts | 2000 – present |
| 3 | pybaseball `playerid_lookup` | Name-based fallback | Historical + modern |
| 4 | Lahman People table | Historical bios and stats | 1871 – prior season |
| 5 | Retrosheet bio/master | Pre-Statcast historical IDs | 1900 – prior season |
| 6 | Contextual game fingerprint | Last-resort (date + team + slot) | Any era |

---

## Sources

### 1. Chadwick Bureau Register

- **URL:** <https://github.com/chadwickbureau/register>
- **File:** `data/people.csv` in the repo root
- **Python:** `pip install requests` then download the raw CSV directly
- **Key columns:** `key_mlbam`, `key_retro`, `key_bbref`, `key_fangraphs`,
  `key_lahman`, `name_first`, `name_last`, `birth_year`, `mlb_played_first`,
  `mlb_played_last`
- **Update cadence:** Weekly; re-seed `stg.chadwick_register_import` after each
  update and run `SELECT * FROM stg.fn_cross_validate_identities()`
- **Confidence score assigned:** 0.90 (seed), 0.95 (seed + confirmed by second source)
- **Limitations:** Occasional lag for players debuting mid-season; very rare
  mapping errors corrected in later releases

```python
import requests, io
import pandas as pd

CHADWICK_URL = (
    "https://raw.githubusercontent.com/chadwickbureau/register/master/data/people.csv"
)

def load_chadwick() -> pd.DataFrame:
    resp = requests.get(CHADWICK_URL, timeout=30)
    resp.raise_for_status()
    return pd.read_csv(io.StringIO(resp.text), low_memory=False)
```

---

### 2. MLB Stats API — `people/xref`

- **Base URL:** `https://statsapi.mlb.com/api/v1/`
- **Endpoint:** `people/{mlbam_id}?hydrate=xrefIds` — returns the person record
  including cross-reference IDs (Retrosheet, Lahman, etc.) where MLB has them
- **Python package:** `python-mlb-statsapi` (`pip install python-mlb-statsapi`)
  or call the REST endpoint directly
- **Key fields returned:** `id` (MLBAM), `fullName`, `birthDate`, `xrefIds`
- **Update cadence:** Real-time; call on demand for new MLBAM IDs
- **Confidence score assigned:** 0.90 when `xrefIds` contains retro/lahman;
  0.75 when MLBAM-only data returned
- **Limitations:** Only covers players MLB has cross-referenced; older
  pre-Statcast players may have no `xrefIds`

```python
import statsapi  # python-mlb-statsapi

def resolve_via_mlb_api(mlbam_id: int) -> dict:
    """Returns dict with resolved IDs or empty dict if not found."""
    try:
        people = statsapi.lookup_player(mlbam_id)
        if not people:
            return {}
        person = people[0]
        xref = person.get("xrefIds", {})
        return {
            "key_mlbam":     person["id"],
            "full_name":     person["fullName"],
            "birth_date":    person.get("birthDate"),
            "key_retro":     xref.get("retrosheet"),
            "key_lahman":    xref.get("lahman"),
            "key_bbref":     xref.get("bbref"),
            "key_fangraphs": xref.get("fangraphs"),
        }
    except Exception:
        return {}
```

---

### 3. pybaseball — `playerid_lookup`

- **Package:** `pip install pybaseball`
- **Function:** `pybaseball.playerid_lookup(last, first, fuzzy=True)`
- **Returns:** DataFrame with `key_mlbam`, `key_retro`, `key_bbref`,
  `key_fangraphs`, `key_lahman`, `mlb_played_first`, `mlb_played_last`
- **Data source:** Backed by the Smart Fantasy Baseball / Chadwick crosswalk;
  effectively a cached mirror
- **Update cadence:** Follows pybaseball release cycle; may lag Chadwick weekly
  updates by a few weeks
- **Confidence score assigned:** 0.85 (exact name match); 0.60 (fuzzy match)
- **Limitations:** Name normalization issues with accented characters and
  hyphens; Jr./Sr. disambiguation requires birth year cross-check

```python
from pybaseball import playerid_lookup

def resolve_via_pybaseball(last_name: str, first_name: str) -> dict:
    df = playerid_lookup(last_name, first_name, fuzzy=True)
    if df.empty:
        return {}
    row = df.iloc[0]
    return {
        "key_mlbam":     int(row["key_mlbam"]) if pd.notna(row["key_mlbam"]) else None,
        "key_retro":     row.get("key_retro"),
        "key_bbref":     row.get("key_bbref"),
        "key_fangraphs": str(int(row["key_fangraphs"])) if pd.notna(row.get("key_fangraphs")) else None,
        "key_lahman":    row.get("key_lahmanid"),
    }
```

---

### 4. Lahman Database — `People` table

- **URL:** <https://www.seanlahman.com/baseball-archive/statistics/>
  and <https://github.com/chadwickbureau/basebball-databank>
- **Key table:** `People` (columns: `playerID`, `nameFirst`, `nameLast`,
  `birthYear`, `birthMonth`, `birthDay`, `debut`, `finalGame`, `bbrefID`,
  `retroID`)
- **Warehouse table:** Load into `raw_lahman.people` via your existing
  Lahman ingest job
- **Update cadence:** Annual (post-season release)
- **Confidence score assigned:** 0.90 when cross-referenced with Chadwick
- **Limitations:** Annual cadence means rookies from the current season are
  absent until the next release

---

### 5. Retrosheet — bio/master files

- **URL:** <https://www.retrosheet.org/biofile.htm>
- **Key file:** `biofile.txt` — tab-delimited, one row per player with
  Retrosheet ID, full name, birth date, debut date
- **Update cadence:** Annual (post-season)
- **Confidence score assigned:** 0.85 when Retrosheet ID confirmed via Chadwick
- **Limitations:** Historical coverage only; very limited modern player data

---

### 6. Contextual Game Fingerprint (DB Functions)

For the truly hard cases, the database provides two fallback functions:

```sql
-- Find a player by game date + team + batting order slot
SELECT * FROM stg.fn_pinpoint_player_by_context(
    '2024-07-15'::DATE, 'NYY', 3, NULL
);

-- Validate batting slot consistency for a whole game
SELECT * FROM stg.fn_contextual_fingerprint_check('2024-07-15', 532441)
WHERE flag LIKE 'WARN%';
```

See `sql/080_functions/013_identity_validation_functions.sql` and
`sql/080_functions/014_identity_reconciliation_functions.sql` for full
function signatures and examples.

---

## Confidence Score Reference

| Score range | Meaning | Action |
|-------------|---------|--------|
| 0.00 | Auto-inserted placeholder, never enriched | Run enrichment worker |
| 0.50–0.59 | Name-only fuzzy match, high uncertainty | Flag for manual review |
| 0.60–0.74 | Single source match, plausible | Enrichment worker logs; human should confirm |
| 0.75–0.84 | MLB StatsAPI match, no cross-check | Accept; schedule Chadwick cross-validate |
| 0.85–0.94 | Pybaseball exact match OR Chadwick seed | Auto-promote via `fn_reconcile_candidates` |
| 0.95–1.00 | Chadwick + secondary source confirmed | Fully resolved; no action needed |

All updates — regardless of source — must go through
`CALL stg.update_player_identity(...)`. Never `UPDATE stg.player_identity`
directly.

---

## Weekly Maintenance Checklist

```bash
# 1. Refresh Chadwick register
python scripts/enrich_player_identity.py --mode=seed-chadwick

# 2. Run enrichment worker on pending queue
python scripts/enrich_player_identity.py --mode=enrich --limit=1000

# 3. Auto-promote high-confidence candidates
psql $DATABASE_URL -c "SELECT * FROM stg.fn_reconcile_candidates();"

# 4. Cross-validate against fresh Chadwick snapshot
psql $DATABASE_URL -c "SELECT * FROM stg.fn_cross_validate_identities() LIMIT 50;"

# 5. Check dashboard — orphaned_pitches_48h must be 0
psql $DATABASE_URL -c "SELECT * FROM stg.v_identity_validation_dashboard;"

# 6. Generate full health report (logs to resolution_log)
psql $DATABASE_URL -c "SELECT stg.fn_full_identity_health_report();"
```
