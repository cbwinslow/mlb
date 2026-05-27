\set ON_ERROR_STOP on

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ingest_run_status_chk'
  ) THEN
    RAISE EXCEPTION 'Constraint ingest_run_status_chk is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ingest_run_date_window_chk'
  ) THEN
    RAISE EXCEPTION 'Constraint ingest_run_date_window_chk is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ingest_run_finished_chk'
  ) THEN
    RAISE EXCEPTION 'Constraint ingest_run_finished_chk is missing';
  END IF;
END $$;

DO $$
DECLARE
  run_id uuid;
BEGIN
  run_id := util.start_ingest_run('mlbapi', 'schedule', 'test-harness', '{"mode":"smoke"}'::jsonb, 'https://statsapi.mlb.com/api/v1/schedule', DATE '2024-04-01', DATE '2024-04-03');

  IF run_id IS NULL THEN
    RAISE EXCEPTION 'util.start_ingest_run returned NULL';
  END IF;

  CALL util.finish_ingest_run(run_id, 'succeeded', 10, 8, 1, 1, 0, 0, NULL);

  IF NOT EXISTS (
    SELECT 1
    FROM meta.ingest_run
    WHERE ingest_run_id = run_id
      AND run_status = 'succeeded'
      AND records_seen = 10
      AND records_inserted = 8
      AND records_updated = 1
      AND records_unchanged = 1
      AND records_rejected = 0
      AND error_count = 0
      AND finished_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'util.finish_ingest_run did not persist expected values';
  END IF;
END $$;

DO $$
BEGIN
  IF util.normalize_retrosheet_record_type(' Play ') <> 'play' THEN
    RAISE EXCEPTION 'Retrosheet record normalization failed';
  END IF;

  IF util.build_retrosheet_game_id('BOS', DATE '2024-04-10', 1) <> 'BOS202404101' THEN
    RAISE EXCEPTION 'Retrosheet game id builder returned unexpected value';
  END IF;

  IF util.should_stop_live_polling('Live', 'L', 'In Progress') THEN
    RAISE EXCEPTION 'should_stop_live_polling incorrectly stopped live game';
  END IF;

  IF NOT util.should_stop_live_polling('Final', 'F', 'Game Over') THEN
    RAISE EXCEPTION 'should_stop_live_polling failed to stop final game';
  END IF;
END $$;

SELECT 'meta and utility checks passed' AS result;
