# Pybaseball Data Source Mapping

## Overview
This document maps all available pybaseball functions to our PostgreSQL schema, identifying gaps and implementation priorities.

**Generated:** 2026-05-30
**Last verified against:** pybaseball v installed package

---

## Current Status Summary

| Category | Implemented | Partially Implemented | Not Implemented |
|----------|-------------|----------------------|-----------------|
| Statcast pitch-level | ✅ 100% | - | - |
| Statcast player aggregations | ❌ | - | 18 functions |
| FanGraphs stats | ✅ 70% | Splits/Boxscores | Team stats |
| BRef stats | ✅ 70% | Splits/Boxscores | - |
| Lahman historical | ✅ 100% | - | - |
| MLB API live/stats | ✅ 60% | Schedule/live data | Team/league stats |
| Retrosheet | ✅ 100% | - | - (using pychadwick) |

---

## Detailed Function Mapping

### Statcast Pitch-Level (✅ COMPLETE)
Located in `sql/040_raw/003_raw_statcast.sql` - 121 columns including:
- Release metrics: velocity, spin_rate, plate_x/z, arm_angle, extension
- Batted ball: launch_speed, launch_angle, hc_x/y, hit_location
- Bat tracking (2024+): bat_speed, swing_length, attack_angle/direction/tilt
- Context: game state, score differentials, win expectancy, age fields
- All fielder IDs (fielder_2 through fielder_9, umpire)

---

### Statcast Player-Level Aggregations (❌ NOT IMPLEMENTED)

#### Season Totals
| Function | Output Columns (Key) | Proposed Table | Status |
|----------|-------------------|----------------|--------|
| `statcast_batter(start_dt, end_dt, player_id)` | PA, AB, H, HR, BB, K, BA, OBP, SLG, ISO, wOBA, xBA, xSLG, xwOBA, barrels, exit_velocity | `raw_statcast.batter_season_stats` | TODO |
| `statcast_pitcher(start_dt, end_dt, player_id)` | IP, TBF, H, R, ER, BB, K, ERA, FIP, xBA, xSLG, xwOBA, barrels | `raw_statcast.pitcher_season_stats` | TODO |

#### Expected Statistics
| Function | Output Columns | Proposed Table | Status |
|----------|---------------|---------------|--------|
| `statcast_batter_expected_stats()` | xBA, xSLG, xwOBA, xISO, run_exp | `raw_statcast.batter_expected` | TODO |
| `statcast_pitcher_expected_stats()` | xBA, xSLG, xwOBA allowed | `raw_statcast.pitcher_expected` | TODO |
| `statcast_batter_percentile_ranks()` | percentile ranks for all stats | `raw_statcast.player_percentiles` | TODO |
| `statcast_pitcher_percentile_ranks()` | percentile ranks for all stats | `raw_statcast.player_percentiles` | TODO |

#### Exit Velocity / Barrel Analysis
| Function | Output Columns | Proposed Table | Status |
|----------|---------------|---------------|--------|
| `statcast_batter_exitvelo_barrels()` | barrels, exit_velocity_avg, ev95 | `raw_statcast.batter_barrels` | TODO |
| `statcast_pitcher_exitvelo_barrels()` | barrels allowed, avg ev against | `raw_statcast.pitcher_barrels` | TODO |

#### Pitch Arsenal
| Function | Output Columns | Proposed Table | Status |
|----------|---------------|---------------|--------|
| `statcast_pitcher_arsenal_stats()` | pitch_type, count, usage_pct, avg_ev, avg_spin | `raw_statcast.pitcher_arsenal` | TODO |
| `statcast_batter_pitch_arsenal()` | pitch_type, count, ba, slg vs pitch | `raw_statcast.batter_arsenal` | TODO |

#### Sprint Speed / Running
| Function | Output Columns | Proposed Table | Status |
|----------|---------------|---------------|--------|
| `statcast_sprint_speed(year, min_opp)` | player_id, sprint_speed, ovr_rank | `raw_statcast.sprint_speed` | TODO |
| `statcast_running_splits(year, min_opp)` | baserunning splits with sprint speed | `raw_statcast.running_splits` | TODO |

#### Fielding Metrics
| Function | Output Columns | Proposed Table | Status |
|----------|---------------|---------------|--------|
| `statcast_outs_above_average(year, pos)` | OAA, attempted, success, fielder_runs | `raw_statcast.outs_above_average` | TODO |
| `statcast_outfield_catch_prob(year, min_att)` | OOF, catch_prob, runs_saved | `raw_statcast.outfield_catch_prob` | TODO |
| `statcast_outfield_directional_oaa(year, min_att)` | Directional OAA by field region | `raw_statcast.directional_oaa` | TODO |
| `statcast_outfielder_jump(year, min_att)` | Jump, read_time, best_jump | `raw_statcast.outfielder_jump` | TODO |

#### Catcher Metrics
| Function | Output Columns | Proposed Table | Status |
|----------|---------------|---------------|--------|
| `statcast_catcher_framing(year, min_opp)` | framing_runs, strikes_above_avg | `raw_statcast.catcher_framing` | TODO |
| `statcast_catcher_poptime(year, min_opp)` | pop_time, throws_to_2b, runs | `raw_statcast.catcher_poptime` | TODO |

---

### FanGraphs / Baseball Reference Stats (✅ PARTIAL)

#### Implemented
- `raw_fangraphs.batter_splits` - Batter splits by situation
- `raw_fangraphs.pitcher_splits` - Pitcher splits by situation  
- `raw_fangraphs.baserunning` - BsR, UBR, wSB
- `raw_fangraphs.plate_discipline` - Swing rates, chase rate
- `raw_fangraphs.boxscore_batting/pitching` - Game-level stats
- Same for `raw_bref.*`

#### Missing
| Function | Proposed Table | Notes |
|----------|---------------|-------|
| `fg_team_batting_data(year)` | `raw_fangraphs.team_batting` | Team offensive stats |
| `fg_team_pitching_data(year)` | `raw_fangraphs.team_pitching` | Team pitching stats |
| `fg_team_fielding_data(year)` | `raw_fangraphs.team_fielding` | Team fielding runs |
| `get_splits()` | Multiple tables | Situational stats query |

---

### MLB API / Team Stats (❌ PARTIAL)

#### Implemented
- `raw_mlbapi.schedule_game` - Game schedule
- `raw_mlbapi.live_play/pitch` - Live game feed
- `raw_mlbapi.person/team` - Rosters

#### Missing
| Function | Proposed Table | Notes |
|----------|---------------|-------|
| `standings(season)` | `raw_mlbapi.standings` | Division standings |
| `team_results(team, season)` | `raw_mlbapi.team_results` | Team seasonal results |
| `team_batting(season)` | `raw_mlbapi.team_batting_stats` | Team batting aggregate |
| `team_pitching(season)` | `raw_mlbapi.team_pitching_stats` | Team pitching aggregate |
| `league_batting_stats(season)` | `raw_mlbapi.league_batting` | League totals |

---

### Historical/Awards Data (✅ LAHMAN)

All covered via Lahman tables:
- `raw_lahman.awards_players` - MVP, Cy Young, Gold Glove
- `raw_lahman.awards_managers` - Manager awards
- `raw_lahman.awards_share_players/managers` - Voting data
- `raw_lahman.hall_of_fame` - HOF ballots
- `raw_lahman.allstar_full` - All-Star selections
- `raw_lahman.amateur_draft` - TODO: Not yet in Lahman SQL

**Missing:** `amateur_draft()` and `amateur_draft_by_team()` - need `raw_mlbapi.draft` table

---

## Implementation Plan

### Phase 1: Statcast Advanced Metrics
Create `sql/040_raw/008_raw_statcast_advanced.sql`:
- `raw_statcast.batter_season_stats`
- `raw_statcast.pitcher_season_stats`  
- `raw_statcast.player_percentiles`
- `raw_statcast.pitcher_arsenal`
- `raw_statcast.batter_arsenal`
- `raw_statcast.sprint_speed`
- `raw_statcast.fielding_advanced` (consolidated fielding metrics)

### Phase 2: Team Stats
Create `sql/040_raw/009_raw_mlbapi_team_stats.sql`:
- `raw_mlbapi.standings`
- `raw_mlbapi.team_batting_stats`
- `raw_mlbapi.team_pitching_stats`
- `raw_mlbapi.league_stats`

### Phase 3: Historical Completeness
Add to existing files:
- Draft tables to `raw_mlbapi` (for `amateur_draft()`)
- Team stats to `raw_fangraphs`

---

## Notes on Data Overlap

1. **Statcast season stats vs core.plate_appearances**: Statcast player-level functions return season aggregates that can populate core tables after processing.

2. **FanGraphs vs BRef**: Both provide similar data; we ingest both for cross-validation opportunities.

3. **Lahman vs MLB API**: Lahman has historical completeness (1871+); MLB API has current season updates.

4. **Player percentiles**: These are derived/calculated from Statcast data but useful as features for ML models.