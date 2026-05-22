# External Tools Reference — Player Identity Pipeline

This document describes every external data source and Python library used in
the player identity enrichment pipeline. It covers what each source provides,
how it fits into the seed → enrich → validate workflow, update cadence, and
how to access it.

For the database-side design, see:
- `sql/050_staging/004_identity_trigger_and_indexes.sql` — trigger, views, review queues
- `sql/080_functions/013_identity_validation_functions.sql` — validation & cross-validate functions
- `sql/080_functions/014_identity_reconciliation_functions.sql` — reconcile & health report
- `sql/080_functions/015_chadwick_seed_and_refresh.sql` — Chadwick raw table & seed functions

For the enrichment worker, see `scripts/enrich_player_identity.py`.

---

## ID Systems at a Glance

| Column in `stg.player_identity` | Source System | Type | Example |
|---|---|---|---|
| `mlbam_player_id` | MLB MLBAM / Statcast | `BIGINT` | `660271` |
| `retrosheet_player_id` | Retrosheet | `TEXT` | `trout001mi` |
| `bbref_player_id` | Baseball-Reference | `TEXT` | `troutmi01` |
| `fangraphs_player_id` | FanGraphs | `BIGINT` | `10155` |
| `lahman_player_id` | Lahman Database | `TEXT` | `troutmi01` |

---

## Source Reference

### 1. Chadwick Register (Primary Cross-Source Authority)

**What it is:** The Chadwick Bureau Register is the most comprehensive free
open authority file for baseball player identities. It maps a single
`key_person` internal key to MLBAM, Retrosheet, Baseball-Reference, FanGraphs,
Lahman, and other IDs for every known player in professional baseball history.

**URL:** https://github.com/chadwickbureau/register  
**File:** `data/people.csv` in the repository  
**License:** CC0 (public domain)  
**Update cadence:** Weekly (GitHub releases + direct CSV download)  

**What it provides:**
- `key_mlbam` — MLB Advanced Media / Statcast player ID
- `key_retro` — Retrosheet player ID
- `key_bbref` — Baseball-Reference player ID
- `key_fangraphs` — FanGraphs player ID
- `key_lahman` — Lahman Database playerID
- `name_first`, `name_last` — canonical player name
- `birth_year`, `birth_month`, `birth_day` — birth date
- `mlb_played_first`, `mlb_played_last` — MLB career span

**Where it fits in the pipeline:**
- **Seed step**: Bulk-load `people.csv` into `raw.chadwick_register`, then call
  `SELECT stg.fn_seed_from_chadwick()` to populate `stg.player_identity`.
  This resolves ~99% of historical players in a single operation.
- **Weekly refresh**: Re-run seed after each Chadwick weekly release to pick up
  new crosswalk entries for rookies and recent call-ups.
- **Validation**: `stg.fn_chadwick_divergence_report()` compares stored IDs
  against the latest Chadwick data and flags disagreements.

**Download the latest CSV:**
```bash
curl -L -o /tmp/chadwick_people.csv \
  https://raw.githubusercontent.com/chadwickbureau/register/master/data/people.csv
```

**Load and seed:**
```bash
psql $MLB_DB_DSN -c "TRUNCATE TABLE raw.chadwick_register"
psql $MLB_DB_DSN -c "\COPY raw.chadwick_register (...columns...) FROM '/tmp/chadwick_people.csv' CSV HEADER"
psql $MLB_DB_DSN -c "SELECT * FROM stg.fn_refresh_chadwick()"
```

Or use the Python enrichment worker:
```bash
python scripts/enrich_player_identity.py --chadwick-refresh /tmp/chadwick_people.csv
```

---

### 2. MLB Stats API (Modern Player Resolution)

**What it is:** The official MLB Stats API provides player metadata and
cross-reference IDs for all players in the MLB system. The `people/{personId}`
endpoint with `hydrate=xrefIds` returns third-party IDs that MLB has mapped,
including Retrosheet and Lahman where available.

**Base URL:** `https://statsapi.mlb.com`  
**Authentication:** None required (public API)  
**Rate limits:** Unofficial; ~1 request/second is safe  

**Key endpoints:**

```
# Get person metadata + xref IDs by MLBAM id
GET /api/v1/people/{personId}?hydrate=xrefIds

# Search by name
GET /api/v1/people/search?names={lastName},{firstName}

# Get all people with a specific xref ID (reverse lookup)
GET /api/v1/people?xrefId={id}&xrefType=retrosheet
```

**Example response (xrefIds):**
```json
{
  "people": [{
    "id": 660271,
    "fullName": "Juan Soto",
    "birthDate": "1998-10-25",
    "xrefIds": [
      {"xrefType": "retrosheet", "xrefId": "sotoj001"},
      {"xrefType": "bbref",      "xrefId": "sotoju01"},
      {"xrefType": "fangraphs",  "xrefId": "19755"}
    ]
  }]
}
```

**Where it fits in the pipeline:**
- **Priority 1 resolver** in `enrich_player_identity.py` for all players with
  a known MLBAM id. Confidence score: **0.90**.
- Best for players active since ~2016 (when MLBAM IDs became universal).
- Does not have Retrosheet IDs for pre-MLBAM historical players — use Chadwick
  for those.

**Python library (optional):**
```bash
pip install python-mlb-statsapi
```
```python
import statsapi
result = statsapi.lookup_player('trout')  # name search
person = statsapi.get('people', {'personIds': 545361, 'hydrate': 'xrefIds'})
```

---

### 3. pybaseball (Name-Based Lookup Fallback)

**What it is:** `pybaseball` is a Python library that wraps multiple baseball
data sources. Its `playerid_lookup()` function queries the Smart Fantasy Player
ID Map (sfbb.baseball-reference.com) which cross-references MLBAM, Retrosheet,
BBref, FanGraphs, and Lahman IDs by player name.

**GitHub:** https://github.com/jldbc/pybaseball  
**Install:** `pip install pybaseball`  
**Data source for ID lookup:** Smart Fantasy Baseball Player ID Map  

**Key function:**
```python
import pybaseball

# Exact match
result = pybaseball.playerid_lookup('trout', 'mike')

# Fuzzy match (handles name variations)
result = pybaseball.playerid_lookup('trot', 'mike', fuzzy=True)

# Returns a DataFrame with columns:
# name_last, name_first, key_mlbam, key_retro, key_bbref, key_fangraphs, key_bbref_minors
```

**Where it fits in the pipeline:**
- **Priority 3 resolver** in `enrich_player_identity.py`.
- Used when StatsAPI xref lookup returns no cross-source IDs (common for
  players with sparse xref data) and Chadwick DB lookup fails.
- Confidence score: **0.80** (MLBAM-confirmed match) or **0.60** (name-only).
- The returned MLBAM id is always cross-checked against the known MLBAM id
  before accepting the result.

**Caveats:**
- Queries a remote CSV on each call; cache the result for bulk operations.
- The underlying Smart Fantasy map updates weekly but is not always in sync
  with the very latest rookie additions.
- Fuzzy matching can produce false positives — always check MLBAM id.

---

### 4. Lahman Database (Historical Bio Enrichment)

**What it is:** The Lahman Baseball Database is the definitive free historical
statistics and biographical database for major league baseball. The `People`
table maps `playerID` (Lahman key) to biographical attributes: full name, birth
date, birth country/city, height, weight, bats, throws, debut date, and more.

**URL:** https://www.seanlahman.com/baseball-archive/statistics/  
**GitHub (community maintained):** https://github.com/chadwickbureau/baseballdatabank  
**License:** CC BY-SA 4.0  
**Update cadence:** Annual (post-season update each winter)  

**Key table: `People.csv`**

| Column | Description |
|---|---|
| `playerID` | Lahman stable key (e.g., `troutmi01`) |
| `nameFirst`, `nameLast` | Player name |
| `birthYear/Month/Day` | Birth date |
| `debut` | MLB debut date |
| `finalGame` | Last MLB game date |
| `bats`, `throws` | Handedness |
| `birthCity`, `birthCountry` | Birthplace |
| `retroID` | Retrosheet ID (in newer releases) |
| `bbrefID` | Baseball-Reference ID (in newer releases) |

**Where it fits in the pipeline:**
- **Historical bio enrichment**: After identity IDs are resolved, join
  `stg.player_identity` on `lahman_player_id` to pull biographical attributes
  into `core.player`.
- The `lahman_player_id` column in `stg.player_identity` is populated by the
  Chadwick seed (Chadwick carries `key_lahman`), so no separate Lahman ID
  resolution step is needed.
- Lahman's `retroID` and `bbrefID` columns (added in recent releases) can be
  used as a secondary cross-validation source.

---

### 5. Retrosheet (Historical Game Data & Bio)

**What it is:** Retrosheet provides event-level play-by-play data and player
bio/register files for major league baseball. The bio/master file includes
Retrosheet player IDs and biographical attributes for all players back to 1871.

**URL:** https://www.retrosheet.org  
**License:** Free for non-commercial use (see retrosheet.org/notice.txt)  
**Key file:** `biofile.txt` (biographical register)

**Where it fits in the pipeline:**
- Retrosheet `retroID` (column `retrosheet_player_id` in `stg.player_identity`)
  is the key used to join Statcast/MLBAM data with historical play-by-play data.
- The Chadwick Register carries `key_retro` for all players it knows about,
  so in most cases the Retrosheet ID is populated via the Chadwick seed.
- For pre-MLBAM historical players (before ~2000), Retrosheet is often the
  only source that has event-level data.
- The contextual fingerprint validator (`stg.fn_contextual_fingerprint_check`)
  flags when a Retrosheet ID appears in the wrong batting slot, which can
  indicate a wrong `retrosheet_player_id` mapping.

---

### 6. Smart Fantasy Baseball Player ID Map

**What it is:** A community-maintained CSV that maps player IDs across MLB,
FanGraphs, Baseball-Reference, and other fantasy platforms. This is the
underlying data source for `pybaseball.playerid_lookup()`.

**URL:** https://www.smartfantasybaseball.com/tools/playerid-map/  
**Update cadence:** Near-weekly during the season  

**Where it fits in the pipeline:**
- Accessed indirectly via `pybaseball.playerid_lookup()` — no direct download
  needed.
- Useful as a manual reference when automated lookup fails and you need to
  cross-check IDs in a browser.

---

## Confidence Score Reference

| Resolution Method | Confidence Score | Auto-Promoted? | Notes |
|---|---|---|---|
| Chadwick seed (direct MLBAM match) | 0.85 | Yes | Bulk seed, most historical players |
| MLB StatsAPI xrefId | 0.90 | Yes | Best for modern players |
| Chadwick DB lookup (MLBAM confirmed) | 0.85 | Yes | Post-seed single-player lookup |
| pybaseball (MLBAM confirmed) | 0.80 | No* | Written as candidate; reconciled |
| Chadwick name match | 0.65 | No | No MLBAM in Chadwick; name only |
| pybaseball (name only, unconfirmed) | 0.60 | No | Manual review required |
| Auto-inserted placeholder | 0.00 | No | Pending enrichment |

*pybaseball at 0.80 is below the default auto-promote threshold of 0.85.
Candidates at this score go to `stg.v_candidates_pending_human_review`.
Adjust `--auto-threshold` in the enrichment worker to change this behaviour.

---

## Weekly Maintenance Checklist

Run this checklist after each Chadwick weekly release (typically Tuesday):

```bash
# 1. Download latest Chadwick people.csv
curl -L -o /tmp/chadwick_people.csv \
  https://raw.githubusercontent.com/chadwickbureau/register/master/data/people.csv

# 2. Run enrichment worker with Chadwick refresh + full batch
python scripts/enrich_player_identity.py \
  --chadwick-refresh /tmp/chadwick_people.csv \
  --batch-size 1000 \
  --auto-threshold 0.85

# 3. Check the health report
psql $MLB_DB_DSN -c "SELECT stg.fn_full_identity_health_report()"

# 4. Review Chadwick divergences (IDs that changed)
psql $MLB_DB_DSN -c \
  "SELECT * FROM stg.fn_chadwick_divergence_report() WHERE divergence_type != 'OK'"

# 5. Review human review queue (low-confidence candidates)
psql $MLB_DB_DSN -c \
  "SELECT player_identity_id, candidate_name, candidate_score, accept_sql \
   FROM stg.v_candidates_pending_human_review"

# 6. Check for unmatched Chadwick entries (net-new players not yet in stg)
psql $MLB_DB_DSN -c \
  "SELECT * FROM stg.v_chadwick_unmatched LIMIT 50"

# 7. Check orphaned pitches (should always be zero)
psql $MLB_DB_DSN -c \
  "SELECT COUNT(*) FROM stg.fn_detect_orphaned_pitches()"
```

---

## Live Player ID Lag: What to Expect

When a player makes their MLB debut, the ID propagation timeline is:

| Milestone | Timing |
|---|---|
| MLBAM id assigned | Before first MLB appearance |
| Statcast pitch trigger fires | Same inning as debut |
| MLB StatsAPI xrefId available | Usually within 24–48 hours of debut |
| FanGraphs page created | Within 1–3 days of debut |
| Baseball-Reference page created | Within 1–7 days of debut |
| Chadwick Register updated | Next weekly release (up to 7 days) |
| Retrosheet ID assigned | End of season (Retrosheet is post-season) |
| Lahman Database updated | Annual (following off-season) |

**Implication:** For a debut player, `stg.v_live_players_pending_historical_ids`
will show them as missing `retrosheet_player_id` and `lahman_player_id` for
weeks to months. This is expected and not an error. The `identity_confidence_score`
will be 0.85–0.90 (MLBAM + bbref + fangraphs confirmed) and the player is fully
usable for Statcast analysis. The missing historical IDs are filled in
automatically by the weekly Chadwick refresh once Chadwick publishes them.
