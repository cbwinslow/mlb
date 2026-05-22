# External Player Identity Tools & Sources

This document describes every external data source and library used in the
player identity resolution pipeline. It defines what each source provides,
how to access it, the priority order for resolution, and when to re-run
each source.

---

## Priority Resolution Order

| Priority | Source | Coverage | Why This Order |
|----------|--------|----------|-----------------|
| 1 | **Chadwick Bureau Register** | Historical + modern, all sources | Best free open cross-source authority file; covers MLBAM, Retrosheet, BRef, FanGraphs, Lahman in one CSV |
| 2 | **MLB Stats API (xrefId)** | Modern players (2000s–present) | Authoritative for MLBAM-centric sources; provides official xref to Retrosheet and Lahman where MLB has those mappings |
| 3 | **pybaseball `playerid_lookup`** | Modern players, name-based | Good fallback when a direct ID lookup fails; wraps the Smart Fantasy Player ID map |
| 4 | **Lahman `People` table** | Historical (1871–present) | Best biographical attributes (birthdate, debut, bats/throws) for historical players |
| 5 | **Retrosheet bio/master file** | Historical event-level detail | Deepest historical game context; use for lineup validation |
| 6 | **Smart Fantasy Player ID Map** | Broad cross-source map | Community-maintained; covers FanGraphs, Rotowire, ESPN, Yahoo, NFBC, CBS and others |

---

## Source Details

### 1. Chadwick Bureau Register

- **URL**: <https://github.com/chadwickbureau/register>
- **Format**: CSV (`people.csv`) in the `data/` folder of the repo
- **Columns relevant to us**: `key_mlbam`, `key_retro`, `key_bbref`,
  `key_fangraphs`, `key_lahman`, `name_first`, `name_last`, `name_given`,
  `birth_year`, `birth_month`, `birth_day`, `pro_played_first`, `pro_played_last`
- **Update cadence**: Approximately weekly (check commit history)
- **How to load**:
  ```sql
  TRUNCATE stg.chadwick_register_snapshot;
  COPY stg.chadwick_register_snapshot (
      key_mlbam, key_retro, key_bbref, key_fangraphs, key_lahman,
      name_first, name_last, name_given,
      birth_year, birth_month, birth_day,
      pro_played_first, pro_played_last
  )
  FROM '/path/to/people.csv'
  CSV HEADER;
  ```
- **After loading**: run `SELECT * FROM stg.fn_cross_validate_identities()`
  to surface divergences between your stored IDs and the new Chadwick data.
- **Limitations**: Chadwick lags on rookie call-ups by days to weeks.
  Use MLB Stats API as a supplement for very new players.

---

### 2. MLB Stats API — people/xrefId

- **Base URL**: `https://statsapi.mlb.com/api/v1/`
- **Relevant endpoints**:
  - `GET /people/{mlbam_id}` — full person record including position, debut date, bats/throws
  - `GET /people?personIds={id1},{id2}&hydrate=xrefIds` — batch lookup with cross-reference IDs
  - `GET /people/search?names={name}` — name search
- **Python library**: `python-mlb-statsapi` (`pip install python-mlb-statsapi`) or direct `requests`
- **What it returns**: MLBAM ID (canonical), plus `xrefIds` map that may include Retrosheet and Lahman
  IDs where MLB has those mappings
- **When to use**: primary enrichment source for any player who has appeared in
  an MLB game since roughly 2000; excellent for rookies who are not yet in Chadwick
- **Rate limits**: No published rate limit but be polite; batch requests with `personIds=` parameter
- **Example**:
  ```python
  import requests
  resp = requests.get(
      'https://statsapi.mlb.com/api/v1/people',
      params={'personIds': '660271', 'hydrate': 'xrefIds'}
  )
  person = resp.json()['people'][0]
  xrefs = {x['type']['id']: x['id'] for x in person.get('xrefIds', [])}
  ```

---

### 3. pybaseball `playerid_lookup`

- **Install**: `pip install pybaseball`
- **Function**: `pybaseball.playerid_lookup(last, first=None, fuzzy=False)`
- **Returns**: DataFrame with columns `name_last`, `name_first`, `key_mlbam`,
  `key_retro`, `key_bbref`, `key_fangraphs`, `key_lahman`, `mlb_played_first`,
  `mlb_played_last`
- **Source**: pulls from the Smart Fantasy Player ID Map (see source 6)
- **When to use**: fallback when direct MLBAM ID lookup fails or when you only
  have a player name from a raw data feed
- **Caveats**: name matching can produce false positives for common names;
  always verify `key_mlbam` matches your known ID before committing
- **Confidence to assign**: 0.80 for exact name+active-years match;
  0.60 for fuzzy/ambiguous match (route to manual review)
- **Example**:
  ```python
  import pybaseball
  results = pybaseball.playerid_lookup('judge', 'aaron')
  # Returns DataFrame; check key_mlbam == known MLBAM ID before accepting
  ```

---

### 4. Lahman Database — `People` table

- **URL**: <https://www.seanlahman.com/baseball-archive/statistics/> or
  via pybaseball: `pybaseball.lahman.download_lahman()`
- **Key columns**: `playerID` (Lahman key), `birthYear`, `birthMonth`, `birthDay`,
  `nameFirst`, `nameLast`, `nameGiven`, `bats`, `throws`, `debut`, `finalGame`
- **When to use**: best source for biographical attributes on historical players;
  use to enrich `stg.player_identity` with `birth_date`, `bats`, `throws`,
  `debut_date` once `lahman_player_id` is resolved
- **Update cadence**: Annual (usually January or February)
- **Notes**: The `playerID` format is `{lastname5}{first2}{sequence}` (e.g., `ruthba01`).
  This is a curated stable key — do not reconstruct it from names; always look it up.

---

### 5. Retrosheet bio/master file

- **URL**: <https://www.retrosheet.org/biofile.htm>
- **Format**: CSV — `BIOFILE.csv`
- **Key columns**: `PLAYERID` (Retrosheet ID), `LASTNAME`, `FIRSTNAME`, `DEBUT`, `LASTGAME`
- **When to use**: load into `stg.retrosheet_lineup_snapshot` to enable
  `stg.fn_validate_game_lineup()` — the contextual batting-order cross-validation
- **Update cadence**: Updated at end of each season; occasionally mid-season for new players
- **Notes**: Retrosheet IDs follow the format `{last5}{first1}{sequence}` (e.g., `ruthb101`).
  Chadwick's `key_retro` column maps MLBAM IDs to these Retrosheet IDs.

---

### 6. Smart Fantasy Player ID Map

- **URL**: <https://www.smartfantasybaseball.com/tools/>
- **Direct CSV**: `https://www.smartfantasybaseball.com/PLAYERIDMAPCSV`
- **Columns include**: `MLBID`, `RETROID`, `BREFID`, `FANGRAPHSID`, `ESPNID`,
  `YAHOOID`, `NFBCID`, `CBSID`, `ROTOWIREID`, and more
- **When to use**: useful when you need IDs for fantasy or DFS platforms (Yahoo, ESPN,
  DraftKings) in addition to the core analytical sources; pybaseball wraps this
- **Update cadence**: Community-maintained; roughly weekly during season
- **Notes**: Treated as a supplementary source. Prefer Chadwick for analytical IDs
  (MLBAM, Retrosheet, BRef); use Smart Fantasy for the broader platform ID set.

---

## Enrichment Worker Priority Logic

```python
# Pseudocode — see scripts/enrich_player_identity.py for full implementation

def resolve_player(mlbam_id: int, player_name: str) -> dict:
    """Returns dict of resolved IDs and confidence score."""

    # Step 1: Check Chadwick snapshot already in DB (fastest)
    row = db.query("""
        SELECT key_retro, key_bbref, key_fangraphs, key_lahman
        FROM stg.chadwick_register_snapshot
        WHERE key_mlbam = %(mlbam_id)s
    """, mlbam_id=mlbam_id).fetchone()

    if row and row['key_retro']:
        return {**row, 'confidence': 0.95, 'source': 'chadwick_seed'}

    # Step 2: MLB Stats API xrefId lookup
    xrefs = mlb_stats_api_xref(mlbam_id)
    if xrefs:
        return {**xrefs, 'confidence': 0.90, 'source': 'mlb_statsapi'}

    # Step 3: pybaseball name lookup
    last, first = player_name.split()[-1], player_name.split()[0]
    results = pybaseball.playerid_lookup(last, first)
    if len(results) == 1 and results.iloc[0]['key_mlbam'] == mlbam_id:
        return {**results.iloc[0].to_dict(), 'confidence': 0.80, 'source': 'pybaseball'}

    # Step 4: Fuzzy match — route to manual review
    return {'confidence': 0.40, 'source': 'unresolved:needs_manual_review'}
```

---

## Scheduled Job Cadence

| Job | Frequency | What It Does |
|-----|-----------|---------------|
| Chadwick seed load | Weekly | `TRUNCATE stg.chadwick_register_snapshot; COPY ...` then `fn_cross_validate_identities()` |
| Enrichment worker | Daily (or on-demand after new pitches arrive) | Reads `v_players_pending_enrichment`, calls MLB StatsAPI + pybaseball, writes via `update_player_identity()` |
| Orphan check | Daily | `SELECT * FROM stg.fn_detect_orphaned_pitches()` — alert if non-zero |
| Validation dashboard | Weekly (or on-demand) | `SELECT * FROM stg.v_identity_validation_dashboard` |
| Lineup cross-validation | Post-game-load | `SELECT * FROM stg.fn_validate_game_lineup(date, team)` for any game where IDs are suspect |
| Manual review queue | Human review, weekly | `SELECT * FROM stg.v_players_needing_manual_review` — fix via `update_player_identity()` |
