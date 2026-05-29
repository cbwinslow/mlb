"""baseball.ingestion.retrosheet — Retrosheet data ingester.

Ingests ALL Retrosheet data using pyretrosheet Python library:
- Event files (.EVN/.EVA) → raw_retrosheet.events (via pyretrosheet)
- Game logs → raw_retrosheet.game_log
- Biographical files → raw_retrosheet.bio_people, ballparks, teams, etc.
- Schedules → raw_retrosheet.schedules
- Rosters → raw_retrosheet.rosters
- CSV package (plays.csv, batting.csv, etc.) → raw_retrosheet.events
"""

from __future__ import annotations

import asyncio
import gzip
import json
import logging
import tempfile
import time
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Optional
from uuid import UUID

import aiohttp
import pandas as pd

from psycopg_pool import AsyncConnectionPool

from baseball.ingestion.base import BaseIngester, IngestResult

log = logging.getLogger(__name__)

# Retrosheet data URLs
RETRO_SHEET_BASE_URL = "https://www.retrosheet.org"
RETRO_SHEET_EVENTS_URL = f"{RETRO_SHEET_BASE_URL}/events/{{year}}seve.zip"
RETRO_SHEET_GAMELOGS_URL = f"{RETRO_SHEET_BASE_URL}/gamelogs"
RETRO_SHEET_CSV_URL = f"{RETRO_SHEET_BASE_URL}/downloads/csvdownloads.zip"
RETRO_SHEET_BIO_URL = f"{RETRO_SHEET_BASE_URL}/downloads/biodata.zip"
RETRO_SHEET_ROSTERS_URL = f"{RETRO_SHEET_BASE_URL}/rosters.zip"


class RetrosheetIngester(BaseIngester):
    """Ingester for ALL Retrosheet data.

    Handles:
    - Event file parsing via pychadwick
    - Game log ingestion
    - Biographical data ingestion
    - Schedule and roster ingestion
    """

    def __init__(
        self,
        pool: AsyncConnectionPool,
        workspace_id: Optional[UUID] = None,
        data_dir: Optional[Path] = None,
    ):
        super().__init__(pool, workspace_id, "retrosheet")
        self.data_dir = data_dir or Path("data/retrosheet")

    # -----------------------------------------------------------------------
    # DOWNLOAD METHODS
    # -----------------------------------------------------------------------

    async def download(
        self,
        year: Optional[int] = None,
        session: Optional[aiohttp.ClientSession] = None,
    ) -> int:
        """Download all Retrosheet data.

        Args:
            year: Year to download (e.g., 2023). If None, downloads all available.
            session: Optional aiohttp session to reuse.

        Returns:
            Number of files downloaded.
        """
        close_session = False
        if session is None:
            session = aiohttp.ClientSession()
            close_session = True

        try:
            total = 0
            # Download event files
            if year:
                total += await self._download_events_year(year, session)
            else:
                total += await self._download_all_events(session)

            # Download CSV package (contains plays, batting, pitching, etc.)
            total += await self._download_csv_package(session)

            # Download biographical data
            total += await self._download_biographical(session)

            # Download rosters
            total += await self._download_rosters(session)

            return total
        finally:
            if close_session:
                await session.close()

    async def _download_events_year(self, year: int, session: aiohttp.ClientSession) -> int:
        """Download event files for a specific year."""
        url = RETRO_SHEET_EVENTS_URL.format(year=year)
        log.info("Downloading Retrosheet events for year %d from %s", year, url)

        year_dir = self.data_dir / "events" / str(year)
        year_dir.mkdir(parents=True, exist_ok=True)

        try:
            async with session.get(url) as response:
                if response.status != 200:
                    log.warning("No event data for year %d (status: %d)", year, response.status)
                    return 0

                data = await response.read()
                tmp_path = Path(tempfile.mktemp(suffix=".zip"))
                tmp_path.write_bytes(data)

                with zipfile.ZipFile(tmp_path, "r") as zf:
                    for member in zf.namelist():
                        if member.endswith((".EVN", ".EVA")):
                            zf.extract(member, year_dir)

                tmp_path.unlink()
                return len(list(year_dir.glob("*.EVN")) + list(year_dir.glob("*.EVA")))
        except aiohttp.ClientError as e:
            log.error("Failed to download events for year %d: %s", year, e)
            return 0

    async def _download_all_events(self, session: aiohttp.ClientSession) -> int:
        """Download all event files (1950-present)."""
        total = 0
        current_year = time.localtime().tm_year
        for year in range(1950, current_year + 1):
            total += await self._download_events_year(year, session)
        return total

    async def _download_csv_package(self, session: aiohttp.ClientSession) -> int:
        """Download the pre-processed CSV package."""
        url = RETRO_SHEET_CSV_URL
        log.info("Downloading Retrosheet CSV package from %s", url)

        csv_dir = self.data_dir / "csv"
        csv_dir.mkdir(parents=True, exist_ok=True)

        try:
            async with session.get(url) as response:
                if response.status != 200:
                    log.warning("Failed to download CSV package (status: %d)", response.status)
                    return 0

                data = await response.read()
                tmp_path = Path(tempfile.mktemp(suffix=".zip"))
                tmp_path.write_bytes(data)

                with zipfile.ZipFile(tmp_path, "r") as zf:
                    zf.extractall(csv_dir)

                tmp_path.unlink()
                return len(list(csv_dir.glob("*.csv")))
        except aiohttp.ClientError as e:
            log.error("Failed to download CSV package: %s", e)
            return 0

    async def _download_biographical(self, session: aiohttp.ClientSession) -> int:
        """Download biographical data."""
        url = RETRO_SHEET_BIO_URL
        log.info("Downloading Retrosheet biographical data from %s", url)

        bio_dir = self.data_dir / "bio"
        bio_dir.mkdir(parents=True, exist_ok=True)

        try:
            async with session.get(url) as response:
                if response.status != 200:
                    log.warning("Failed to download biographical data (status: %d)", response.status)
                    return 0

                data = await response.read()
                tmp_path = Path(tempfile.mktemp(suffix=".zip"))
                tmp_path.write_bytes(data)

                with zipfile.ZipFile(tmp_path, "r") as zf:
                    zf.extractall(bio_dir)

                tmp_path.unlink()
                return len(list(bio_dir.glob("*.csv")))
        except aiohttp.ClientError as e:
            log.error("Failed to download biographical data: %s", e)
            return 0

    async def _download_rosters(self, session: aiohttp.ClientSession) -> int:
        """Download roster files."""
        url = RETRO_SHEET_ROSTERS_URL
        log.info("Downloading Retrosheet rosters from %s", url)

        roster_dir = self.data_dir / "rosters"
        roster_dir.mkdir(parents=True, exist_ok=True)

        try:
            async with session.get(url) as response:
                if response.status != 200:
                    log.warning("Failed to download rosters (status: %d)", response.status)
                    return 0

                data = await response.read()
                tmp_path = Path(tempfile.mktemp(suffix=".zip"))
                tmp_path.write_bytes(data)

                with zipfile.ZipFile(tmp_path, "r") as zf:
                    for member in zf.namelist():
                        if member.endswith(".ROS"):
                            zf.extract(member, roster_dir)

                tmp_path.unlink()
                return len(list(roster_dir.glob("*.ROS")))
        except aiohttp.ClientError as e:
            log.error("Failed to download rosters: %s", e)
            return 0

    # -----------------------------------------------------------------------
    # INGEST METHODS
    # -----------------------------------------------------------------------

    async def validate(self) -> bool:
        """Validate that required tables exist."""
        async with self.pool.connection() as conn:
            result = await conn.execute(
                """
                SELECT EXISTS (
                    SELECT 1 FROM pg_tables
                    WHERE schemaname = 'raw_retrosheet'
                    AND tablename IN ('events', 'game_log', 'bio_people', 'rosters')
                )
                """
            )
            return (await result.fetchone())[0]

    async def ingest(
        self,
        year: Optional[int] = None,
        data_type: Optional[str] = None,
    ) -> IngestResult:
        """Ingest Retrosheet data.

        Args:
            year: Year to ingest (e.g., 2023). If None, ingest all available.
            data_type: Specific data type (events, game_log, bio, rosters, all).

        Returns:
            IngestResult with counts.
        """
        start_time = time.time()
        result = IngestResult()

        endpoint_id = await self._get_source_endpoint_id("event_files")
        ingest_run_id = await self._create_ingest_run(endpoint_id, {"year": year, "data_type": data_type})

        try:
            if data_type == "events" or data_type is None:
                result = await self._ingest_events(year, ingest_run_id)
            elif data_type == "game_log":
                result = await self._ingest_game_logs(year, ingest_run_id)
            elif data_type == "bio":
                result = await self._ingest_biographical(ingest_run_id)
            elif data_type == "rosters":
                result = await self._ingest_rosters(ingest_run_id)
            elif data_type == "all":
                result = await self._ingest_all(ingest_run_id)
            else:
                result = await self._ingest_events(year, ingest_run_id)

            await self._complete_ingest_run(ingest_run_id, "succeeded")
        except Exception as e:
            log.error("Retrosheet ingestion failed: %s", e)
            await self._complete_ingest_run(ingest_run_id, "failed", str(e))
            result.errors += 1

        result.duration_seconds = time.time() - start_time
        return result

    async def _ingest_events(self, year: Optional[int], ingest_run_id: UUID) -> IngestResult:
        """Ingest event data using pychadwick or CSV package."""
        result = IngestResult()

        # First try CSV package (plays.csv) - most efficient
        csv_dir = self.data_dir / "csv"
        plays_csv = csv_dir / "plays.csv"

        if plays_csv.exists():
            log.info("Ingesting events from CSV package: %s", plays_csv)
            result = await self._ingest_plays_csv(plays_csv, ingest_run_id)
            if result.rows_inserted > 0:
                return result

        # Fallback to pychadwick for event files
        try:
            from pychadwick.chadwick import Chadwick
        except ImportError:
            log.error("pychadwick not installed. Run: pip install pychadwick")
            result.errors += 1
            return result

        events_dir = self.data_dir / "events"

        if year:
            events_dir = events_dir / str(year)

        if not events_dir.exists():
            log.warning("No events directory found at %s", events_dir)
            return result

        # Process each event file
        for event_file in sorted(events_dir.glob("*.EVN")) + sorted(events_dir.glob("*.EVA")):
            file_result = await self._ingest_single_event_file(event_file, ingest_run_id)
            result.rows_processed += file_result.rows_processed
            result.rows_inserted += file_result.rows_inserted

        return result

    async def _ingest_plays_csv(self, csv_path: Path, ingest_run_id: UUID) -> IngestResult:
        """Ingest plays.csv from the Retrosheet CSV package."""
        result = IngestResult()

        # Use chunked reading for large file
        chunk_iter = pd.read_csv(csv_path, chunksize=10000)

        async with self.pool.connection() as conn:
            for chunk in chunk_iter:
                records = chunk.to_dict(orient="records")
                result.rows_processed += len(records)

                for record in records:
                    # Map CSV column names to our table columns
                    mapped = {
                        "game_id": record.get("gid"),
                        "event_seq": record.get("pa"),
                        "inning": record.get("inning"),
                        "batting_team": record.get("top_bot"),
                        "outs_ct": record.get("outs_pre"),
                        "bat_lineup_id": record.get("batteam"),
                        "fld_cd": record.get("pitteam"),
                        "batter": record.get("batter"),
                        "batter_hand": record.get("bathand"),
                        "pitcher": record.get("pitcher"),
                        "pitcher_hand": record.get("pithand"),
                        "event_text": record.get("event"),
                        "balls_ct": record.get("balls"),
                        "strikes_ct": record.get("strikes"),
                        "pitch_seq_tx": record.get("pitches"),
                        "ab_fl": bool(record.get("ab", 0)),
                        "h_fl": bool(record.get("h", 0)),
                        "sh_fl": bool(record.get("sh", 0)),
                        "sf_fl": bool(record.get("sf", 0)),
                        "bunt_fl": bool(record.get("bunt", 0)),
                        "foul_fl": bool(record.get("foul", 0)),
                        "wp_fl": bool(record.get("wp", 0)),
                        "pb_fl": bool(record.get("pb", 0)),
                        "ibb_fl": bool(record.get("iw", 0)),
                        "gdp_fl": bool(record.get("gdp", 0)),
                        "err_ct": sum([record.get(f"e{i}", 0) or 0 for i in range(1, 10)]),
                        "hit_val": record.get("single") or record.get("double") or record.get("triple") or record.get("hr") or 0,
                        "away_score_ct": record.get("score_v"),
                        "home_score_ct": record.get("score_h"),
                        "raw_event_json": json.dumps(record),
                    }
                    await conn.execute(
                        """
                        INSERT INTO raw_retrosheet.events (
                            game_id, event_seq, inning, batting_team, outs_ct,
                            bat_lineup_id, fld_cd, batter, batter_hand, pitcher, pitcher_hand,
                            event_text, balls_ct, strikes_ct, pitch_seq_tx, ab_fl, h_fl,
                            sh_fl, sf_fl, bunt_fl, foul_fl, wp_fl, pb_fl, ibb_fl, gdp_fl,
                            err_ct, hit_val, away_score_ct, home_score_ct, raw_event_json
                        ) VALUES (
                            %(game_id)s, %(event_seq)s, %(inning)s, %(batting_team)s, %(outs_ct)s,
                            %(bat_lineup_id)s, %(fld_cd)s, %(batter)s, %(batter_hand)s, %(pitcher)s, %(pitcher_hand)s,
                            %(event_text)s, %(balls_ct)s, %(strikes_ct)s, %(pitch_seq_tx)s, %(ab_fl)s, %(h_fl)s,
                            %(sh_fl)s, %(sf_fl)s, %(bunt_fl)s, %(foul_fl)s, %(wp_fl)s, %(pb_fl)s, %(ibb_fl)s, %(gdp_fl)s,
                            %(err_ct)s, %(hit_val)s, %(away_score_ct)s, %(home_score_ct)s, %(raw_event_json)s
                        )
                        ON CONFLICT (game_id, event_seq) DO NOTHING
                        """,
                        mapped,
                    )
                await conn.commit()
                result.rows_inserted += len(records)

        return result

    async def _ingest_single_event_file(
        self,
        file_path: Path,
        ingest_run_id: UUID,
    ) -> IngestResult:
        """Ingest a single event file using pychadwick."""
        result = IngestResult()

        try:
            from pychadwick.chadwick import Chadwick

            chadwick = Chadwick()
            # Use data_type_mapping={} to avoid type conversion errors
            df = chadwick.event_file_to_dataframe(str(file_path), data_type_mapping={})

            if df is not None and not df.empty:
                records = df.to_dict(orient="records")
                result.rows_processed += len(records)

                async with self.pool.connection() as conn:
                    for record in records:
                        # Map pychadwick column names to our table columns
                        mapped = {
                            "game_id": record.get("GAME_ID"),
                            "event_seq": record.get("EVENT_SEQ") or record.get("EVENT_ID"),
                            "away_team_id": record.get("AWAY_TEAM_ID"),
                            "inning": record.get("INN_CT"),
                            "batting_team": record.get("BAT_HOME_ID"),
                            "outs_ct": record.get("OUTS_CT"),
                            "bat_lineup_id": record.get("BAT_LINEUP_ID"),
                            "fld_cd": record.get("FLD_CD"),
                            "batter": record.get("BAT_ID"),
                            "batter_hand": record.get("BAT_HAND_CD"),
                            "pitcher": record.get("PIT_ID"),
                            "pitcher_hand": record.get("PIT_HAND_CD"),
                            "catcher": record.get("POS2_FLD_ID"),
                            "first_base": record.get("POS3_FLD_ID"),
                            "second_base": record.get("POS4_FLD_ID"),
                            "third_base": record.get("POS5_FLD_ID"),
                            "shortstop": record.get("POS6_FLD_ID"),
                            "left_field": record.get("POS7_FLD_ID"),
                            "center_field": record.get("POS8_FLD_ID"),
                            "right_field": record.get("POS9_FLD_ID"),
                            "res_batter": record.get("RES_BAT_ID"),
                            "res_batter_hand": record.get("RES_BAT_HAND_CD"),
                            "res_pitcher": record.get("RES_PIT_ID"),
                            "res_pitcher_hand": record.get("RES_PIT_HAND_CD"),
                            "first_runner": record.get("FIRST_RUNNER_ID"),
                            "second_runner": record.get("SECOND_RUNNER_ID"),
                            "third_runner": record.get("THIRD_RUNNER_ID"),
                            "event_text": record.get("EVENT_TX"),
                            "leadoff_fl": bool(record.get("LEADOFF_FL", 0)),
                            "ph_fl": bool(record.get("PH_FL", 0)),
                            "balls_ct": record.get("BALLS_CT"),
                            "strikes_ct": record.get("STRIKES_CT"),
                            "pitch_seq_tx": record.get("PITCH_SEQ_TX"),
                            "event_cd": record.get("EVENT_CD"),
                            "battedball_cd": record.get("BATTEDBALL_CD"),
                            "bunt_fl": bool(record.get("BUNT_FL", 0)),
                            "foul_fl": bool(record.get("FOUL_FL", 0)),
                            "hit_val": record.get("HIT_VAL"),
                            "sh_fl": bool(record.get("SH_FL", 0)),
                            "sf_fl": bool(record.get("SF_FL", 0)),
                            "hit_location_tx": record.get("HIT_LOCATION_TX"),
                            "err_ct": record.get("NUM_ERR_CT"),
                            "wp_fl": bool(record.get("WP_FL", 0)),
                            "pb_fl": bool(record.get("PB_FL", 0)),
                            "ab_fl": bool(record.get("AB_FL", 0)),
                            "h_fl": bool(record.get("H_FL", 0)),
                            "sh_ball_fl": bool(record.get("SH_BALL_FL", 0)),
                            "ibb_fl": bool(record.get("IBB_FL", 0)),
                            "gdp_fl": bool(record.get("GDP_FL", 0)),
                            "xi_fl": bool(record.get("XI_FL", 0)),
                            "bball_fl": bool(record.get("BBALL_FL", 0)),
                            "event_runs_ct": record.get("EVENT_RUNS_CT"),
                            "bat_dest_id": record.get("BAT_DEST_ID"),
                            "run1_dest_id": record.get("RUN1_DEST_ID"),
                            "run2_dest_id": record.get("RUN2_DEST_ID"),
                            "run3_dest_id": record.get("RUN3_DEST_ID"),
                            "event_outs_ct": record.get("EVENT_OUTS_CT"),
                            "bat_play_tx": record.get("BAT_PLAY_TX"),
                            "run1_play_tx": record.get("RUN1_PLAY_TX"),
                            "run2_play_tx": record.get("RUN2_PLAY_TX"),
                            "run3_play_tx": record.get("RUN3_PLAY_TX"),
                            "sb1_fl": bool(record.get("SB1_FL", 0)),
                            "sb2_fl": bool(record.get("SB2_FL", 0)),
                            "sb3_fl": bool(record.get("SB3_FL", 0)),
                            "cs1_fl": bool(record.get("CS1_FL", 0)),
                            "cs2_fl": bool(record.get("CS2_FL", 0)),
                            "cs3_fl": bool(record.get("CS3_FL", 0)),
                            "po1_fl": bool(record.get("PO1_FL", 0)),
                            "po2_fl": bool(record.get("PO2_FL", 0)),
                            "po3_fl": bool(record.get("PO3_FL", 0)),
                            "resp_fielder1_id": record.get("RESP_FIELDER1_ID"),
                            "resp_fielder2_id": record.get("RESP_FIELDER2_ID"),
                            "resp_fielder3_id": record.get("RESP_FIELDER3_ID"),
                            "resp_fielder_a1_id": record.get("RESP_FIELDER_A1_ID"),
                            "resp_fielder_a2_id": record.get("RESP_FIELDER_A2_ID"),
                            "resp_fielder_a3_id": record.get("RESP_FIELDER_A3_ID"),
                            "resp_fielder_a4_id": record.get("RESP_FIELDER_A4_ID"),
                            "resp_fielder_a5_id": record.get("RESP_FIELDER_A5_ID"),
                            "resp_fielder_e1_id": record.get("RESP_FIELDER_E1_ID"),
                            "resp_fielder_e2_id": record.get("RESP_FIELDER_E2_ID"),
                            "resp_fielder_e3_id": record.get("RESP_FIELDER_E3_ID"),
                            "resp_fielder_po1_id": record.get("RESP_FIELDER_PO1_ID"),
                            "resp_fielder_po2_id": record.get("RESP_FIELDER_PO2_ID"),
                            "resp_fielder_po3_id": record.get("RESP_FIELDER_PO3_ID"),
                            "away_score_ct": record.get("AWAY_SCORE_CT"),
                            "home_score_ct": record.get("HOME_SCORE_CT"),
                            "away_hits_ct": record.get("AWAY_HITS_CT"),
                            "home_hits_ct": record.get("HOME_HITS_CT"),
                            "away_err_ct": record.get("AWAY_ERR_CT"),
                            "home_err_ct": record.get("HOME_ERR_CT"),
                            "away_score_fl": bool(record.get("AWAY_SCORE_FL", 0)),
                            "home_score_fl": bool(record.get("HOME_SCORE_FL", 0)),
                            "bunt_fc_fl": bool(record.get("BUNT_FC_FL", 0)),
                            "pa_ball_ct": record.get("PA_BALL_CT"),
                            "pa_strike_ct": record.get("PA_STRIKE_CT"),
                            "pa_truncated_fl": bool(record.get("PA_TRUNCATED_FL", 0)),
                            "raw_event_json": json.dumps(record),
                        }
                        await conn.execute(
                            """
                            INSERT INTO raw_retrosheet.events (
                                game_id, event_seq, away_team_id, inning, batting_team, outs_ct,
                                bat_lineup_id, fld_cd, batter, batter_hand, pitcher, pitcher_hand,
                                catcher, first_base, second_base, third_base, shortstop,
                                left_field, center_field, right_field, res_batter, res_batter_hand,
                                res_pitcher, res_pitcher_hand, first_runner, second_runner, third_runner,
                                event_text, leadoff_fl, ph_fl, balls_ct, strikes_ct, pitch_seq_tx,
                                event_cd, battedball_cd, bunt_fl, foul_fl, hit_val, sh_fl, sf_fl,
                                hit_location_tx, err_ct, wp_fl, pb_fl, ab_fl, h_fl, sh_ball_fl,
                                ibb_fl, gdp_fl, xi_fl, bball_fl, event_runs_ct, bat_dest_id,
                                run1_dest_id, run2_dest_id, run3_dest_id, event_outs_ct, bat_play_tx,
                                run1_play_tx, run2_play_tx, run3_play_tx, sb1_fl, sb2_fl, sb3_fl,
                                cs1_fl, cs2_fl, cs3_fl, po1_fl, po2_fl, po3_fl, resp_fielder1_id,
                                resp_fielder2_id, resp_fielder3_id, resp_fielder_a1_id, resp_fielder_a2_id,
                                resp_fielder_a3_id, resp_fielder_a4_id, resp_fielder_a5_id,
                                resp_fielder_e1_id, resp_fielder_e2_id, resp_fielder_e3_id,
                                resp_fielder_po1_id, resp_fielder_po2_id, resp_fielder_po3_id,
                                away_score_ct, home_score_ct, away_hits_ct, home_hits_ct,
                                away_err_ct, home_err_ct, away_score_fl, home_score_fl, bunt_fc_fl,
                                pa_ball_ct, pa_strike_ct, pa_truncated_fl, raw_event_json
                            ) VALUES (
                                %(game_id)s, %(event_seq)s, %(away_team_id)s, %(inning)s, %(batting_team)s, %(outs_ct)s,
                                %(bat_lineup_id)s, %(fld_cd)s, %(batter)s, %(batter_hand)s, %(pitcher)s, %(pitcher_hand)s,
                                %(catcher)s, %(first_base)s, %(second_base)s, %(third_base)s, %(shortstop)s,
                                %(left_field)s, %(center_field)s, %(right_field)s, %(res_batter)s, %(res_batter_hand)s,
                                %(res_pitcher)s, %(res_pitcher_hand)s, %(first_runner)s, %(second_runner)s, %(third_runner)s,
                                %(event_text)s, %(leadoff_fl)s, %(ph_fl)s, %(balls_ct)s, %(strikes_ct)s, %(pitch_seq_tx)s,
                                %(event_cd)s, %(battedball_cd)s, %(bunt_fl)s, %(foul_fl)s, %(hit_val)s, %(sh_fl)s, %(sf_fl)s,
                                %(hit_location_tx)s, %(err_ct)s, %(wp_fl)s, %(pb_fl)s, %(ab_fl)s, %(h_fl)s, %(sh_ball_fl)s,
                                %(ibb_fl)s, %(gdp_fl)s, %(xi_fl)s, %(bball_fl)s, %(event_runs_ct)s, %(bat_dest_id)s,
                                %(run1_dest_id)s, %(run2_dest_id)s, %(run3_dest_id)s, %(event_outs_ct)s, %(bat_play_tx)s,
                                %(run1_play_tx)s, %(run2_play_tx)s, %(run3_play_tx)s, %(sb1_fl)s, %(sb2_fl)s, %(sb3_fl)s,
                                %(cs1_fl)s, %(cs2_fl)s, %(cs3_fl)s, %(po1_fl)s, %(po2_fl)s, %(po3_fl)s, %(resp_fielder1_id)s,
                                %(resp_fielder2_id)s, %(resp_fielder3_id)s, %(resp_fielder_a1_id)s, %(resp_fielder_a2_id)s,
                                %(resp_fielder_a3_id)s, %(resp_fielder_a4_id)s, %(resp_fielder_a5_id)s,
                                %(resp_fielder_e1_id)s, %(resp_fielder_e2_id)s, %(resp_fielder_e3_id)s,
                                %(resp_fielder_po1_id)s, %(resp_fielder_po2_id)s, %(resp_fielder_po3_id)s,
                                %(away_score_ct)s, %(home_score_ct)s, %(away_hits_ct)s, %(home_hits_ct)s,
                                %(away_err_ct)s, %(home_err_ct)s, %(away_score_fl)s, %(home_score_fl)s, %(bunt_fc_fl)s,
                                %(pa_ball_ct)s, %(pa_strike_ct)s, %(pa_truncated_fl)s, %(raw_event_json)s
                            )
                            ON CONFLICT (game_id, event_seq) DO NOTHING
                            """,
                            mapped,
                        )
                    await conn.commit()
                    result.rows_inserted += len(records)
        except Exception as e:
            log.error("Failed to process event file %s: %s", file_path, e)
            result.errors += 1

        return result

    async def _ingest_game_logs(self, year: Optional[int], ingest_run_id: UUID) -> IngestResult:
        """Ingest game log files from CSV package."""
        result = IngestResult()

        csv_dir = self.data_dir / "csv"
        gameinfo_csv = csv_dir / "gameinfo.csv"

        if not gameinfo_csv.exists():
            log.warning("No gameinfo.csv found at %s", gameinfo_csv)
            return result

        # Read gameinfo.csv in chunks
        chunk_iter = pd.read_csv(gameinfo_csv, chunksize=10000)

        async with self.pool.connection() as conn:
            for chunk in chunk_iter:
                records = chunk.to_dict(orient="records")
                result.rows_processed += len(records)

                for record in records:
                    mapped = {
                        "game_date": record.get("date"),
                        "game_num": record.get("number", 0),
                        "away_team": record.get("visteam"),
                        "home_team": record.get("hometeam"),
                        "away_score": record.get("vruns"),
                        "home_score": record.get("hruns"),
                        "attendance": record.get("attendance"),
                        "game_minutes": record.get("timeofgame"),
                        "park_id": record.get("site"),
                        "day_night": record.get("daynight"),
                        "raw_game_log_json": json.dumps(record),
                    }
                    await conn.execute(
                        """
                        INSERT INTO raw_retrosheet.game_log (
                            game_date, game_num, away_team, home_team, away_score, home_score,
                            attendance, game_minutes, park_id, day_night, raw_game_log_json
                        ) VALUES (
                            %(game_date)s, %(game_num)s, %(away_team)s, %(home_team)s, %(away_score)s, %(home_score)s,
                            %(attendance)s, %(game_minutes)s, %(park_id)s, %(day_night)s, %(raw_game_log_json)s
                        )
                        ON CONFLICT (game_date, home_team, game_num) DO NOTHING
                        """,
                        mapped,
                    )
                await conn.commit()
                result.rows_inserted += len(records)

        log.info("Ingested %d game log records", result.rows_inserted)
        return result

    async def _ingest_biographical(self, ingest_run_id: UUID) -> IngestResult:
        """Ingest biographical data from CSV package."""
        result = IngestResult()

        csv_dir = self.data_dir / "csv"
        allplayers_csv = csv_dir / "allplayers.csv"

        if not allplayers_csv.exists():
            log.warning("No allplayers.csv found at %s", allplayers_csv)
            return result

        # Read allplayers.csv in chunks
        chunk_iter = pd.read_csv(allplayers_csv, chunksize=10000)

        async with self.pool.connection() as conn:
            for chunk in chunk_iter:
                records = chunk.to_dict(orient="records")
                result.rows_processed += len(records)

                for record in records:
                    mapped = {
                        "retro_id": record.get("id"),
                        "last_name": record.get("last"),
                        "first_name": record.get("first"),
                        "bats": record.get("bat"),
                        "throws": record.get("throw"),
                        "first_g": record.get("first_g"),
                        "last_g": record.get("last_g"),
                        "raw_bio_json": json.dumps(record),
                    }
                    await conn.execute(
                        """
                        INSERT INTO raw_retrosheet.bio_people (
                            retro_id, last_name, first_name, bats, throws, first_g, last_g, raw_bio_json
                        ) VALUES (
                            %(retro_id)s, %(last_name)s, %(first_name)s, %(bats)s, %(throws)s, %(first_g)s, %(last_g)s, %(raw_bio_json)s
                        )
                        ON CONFLICT (retro_id) DO NOTHING
                        """,
                        mapped,
                    )
                await conn.commit()
                result.rows_inserted += len(records)

        log.info("Ingested %d biographical records", result.rows_inserted)
        return result

    async def _ingest_rosters(self, ingest_run_id: UUID) -> IngestResult:
        """Ingest roster files from CSV package."""
        result = IngestResult()

        csv_dir = self.data_dir / "csv"
        # Check for rosters in the bio directory (from rosters.zip)
        roster_dir = self.data_dir / "rosters"

        # Try to find roster files
        roster_files = []
        if roster_dir.exists():
            roster_files = list(roster_dir.glob("*.ROS"))

        if not roster_files:
            log.warning("No roster files found in %s", roster_dir)
            return result

        async with self.pool.connection() as conn:
            for roster_file in roster_files:
                # Parse .ROS files - they're fixed-width text files
                with open(roster_file, "r") as f:
                    for line in f:
                        if line.strip() and not line.startswith("#"):
                            result.rows_processed += 1
                            # .ROS format: player_id,last_name,first_name,team,bats,throws,position
                            parts = line.strip().split(",")
                            if len(parts) >= 4:
                                mapped = {
                                    "player_id": parts[0],
                                    "team_id": parts[3],
                                    "season": int(roster_file.stem[:4]) if roster_file.stem[:4].isdigit() else None,
                                    "last_name": parts[1] if len(parts) > 1 else None,
                                    "first_name": parts[2] if len(parts) > 2 else None,
                                    "bats": parts[4] if len(parts) > 4 else None,
                                    "throws": parts[5] if len(parts) > 5 else None,
                                    "position": parts[6] if len(parts) > 6 else None,
                                    "raw_roster_json": json.dumps({"line": line.strip()}),
                                }
                                await conn.execute(
                                    """
                                    INSERT INTO raw_retrosheet.rosters (
                                        player_id, team_id, season, last_name, first_name, bats, throws, position, raw_roster_json
                                    ) VALUES (
                                        %(player_id)s, %(team_id)s, %(season)s, %(last_name)s, %(first_name)s, %(bats)s, %(throws)s, %(position)s, %(raw_roster_json)s
                                    )
                                    ON CONFLICT (player_id, team_id, season) DO NOTHING
                                    """,
                                    mapped,
                                )
                await conn.commit()
                result.rows_inserted += result.rows_processed

        log.info("Ingested %d roster records", result.rows_inserted)
        return result

    async def _ingest_all(self, ingest_run_id: UUID) -> IngestResult:
        """Ingest all Retrosheet data types."""
        result = IngestResult()

        # Ingest events
        events_result = await self._ingest_events(None, ingest_run_id)
        result.rows_processed += events_result.rows_processed
        result.rows_inserted += events_result.rows_inserted

        # Ingest game logs
        gamelog_result = await self._ingest_game_logs(None, ingest_run_id)
        result.rows_processed += gamelog_result.rows_processed
        result.rows_inserted += gamelog_result.rows_inserted

        # Ingest biographical
        bio_result = await self._ingest_biographical(ingest_run_id)
        result.rows_processed += bio_result.rows_processed
        result.rows_inserted += bio_result.rows_inserted

        # Ingest rosters
        roster_result = await self._ingest_rosters(ingest_run_id)
        result.rows_processed += roster_result.rows_processed
        result.rows_inserted += roster_result.rows_inserted

        return result
