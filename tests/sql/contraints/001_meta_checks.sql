\set ON_ERROR_STOP on

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ingestrunstatuschk'
  ) THEN
    RAISE EXCEPTION 'Constraint ingestrunstatuschk is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ingestrundatewindowchk'
  ) THEN
    RAISE EXCEPTION 'Constraint ingestrundatewindowchk is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ingestrunfinishedchk'
  ) THEN
    RAISE EXCEPTION 'Constraint ingestrunfinishedchk is missing';
  END IF;
END $$;

DO $$
DECLARE
  run_id uuid;
BEGIN
  run_id := util.startingestrun('mlbapi', 'schedule', 'test-harness', '{"mode":"smoke"}'::jsonb, 'https://statsapi.mlb.com/api/v1/schedule', DATE '2024-04-01', DATE '2024-04-03');

  IF run_id IS NULL THEN
    RAISE EXCEPTION 'util.startingestrun returned NULL';
  END IF;

  CALL util.finishingestrun(run_id, 'succeeded', 10, 8, 1, 1, 0, 0, NULL);

  IF NOT EXISTS (
    SELECT 1
    FROM meta.ingestrun
    WHERE ingestrunid = run_id
      AND runstatus = 'succeeded'
      AND recordsseen = 10
      AND recordsinserted = 8
      AND recordsupdated = 1
      AND recordsunchanged = 1
      AND recordsrejected = 0
      AND errorcount = 0
      AND finishedat IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'util.finishingestrun did not persist expected values';
  END IF;
END $$;

DO $$
BEGIN
  IF util.normalizeretrosheetrecordtype(' Play ') <> 'play' THEN
    RAISE EXCEPTION 'Retrosheet record normalization failed';
  END IF;

  IF util.buildretrosheetgameid('BOS', DATE '2024-04-10', 1) <> 'BOS202404101' THEN
    RAISE EXCEPTION 'Retrosheet game id builder returned unexpected value';
  END IF;

  IF util.shouldstoplivepolling('Live', 'L', 'In Progress') THEN
    RAISE EXCEPTION 'shouldstoplivepolling incorrectly stopped live game';
  END IF;

  IF NOT util.shouldstoplivepolling('Final', 'F', 'Game Over') THEN
    RAISE EXCEPTION 'shouldstoplivepolling failed to stop final game';
  END IF;
END $$;

SELECT 'meta and utility checks passed' AS result;
