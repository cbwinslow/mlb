\set ON_ERROR_STOP on

SELECT 'extensions' AS check_name,
       COUNT(*) AS found_count
FROM pg_extension
WHERE extname IN ('pgcrypto', 'citext', 'btree_gist');

DO $$
DECLARE
  missing_schemas text[];
BEGIN
  SELECT array_agg(s)
  INTO missing_schemas
  FROM (
    SELECT unnest(ARRAY[
      'meta','ref','rawretrosheet','rawchadwick','rawlahman','rawstatcast',
      'rawmlbapi','rawfangraphs','rawbref','rawespn','rawodds',
      'stg','core','mart','util','auth','api','ml','ops'
    ]) AS s
  ) expected
  WHERE NOT EXISTS (
    SELECT 1 FROM information_schema.schemata i WHERE i.schema_name = expected.s
  );

  IF missing_schemas IS NOT NULL THEN
    RAISE EXCEPTION 'Missing schemas: %', missing_schemas;
  END IF;
END $$;

DO $$
DECLARE
  missing_tables text[];
BEGIN
  SELECT array_agg(obj)
  INTO missing_tables
  FROM (
    SELECT unnest(ARRAY[
      'meta.sourcesystem',
      'meta.sourceendpoint',
      'meta.ingestrun',
      'meta.sourcefile',
      'meta.rawpayloadregistry',
      'meta.ingesterror',
      'rawretrosheet.eventfile',
      'rawretrosheet.game',
      'rawretrosheet.record',
      'stg.playeridentity',
      'stg.gameidentity',
      'core.player',
      'core.team',
      'core.game',
      'ml.problemdefinition',
      'ml.predictionoutput',
      'ops.jobqueue',
      'ops.scheduledjob',
      'auth.workspace',
      'api.requestlog'
    ]) AS obj
  ) expected
  WHERE to_regclass(expected.obj) IS NULL;

  IF missing_tables IS NOT NULL THEN
    RAISE EXCEPTION 'Missing tables: %', missing_tables;
  END IF;
END $$;

DO $$
DECLARE
  missing_roles text[];
BEGIN
  SELECT array_agg(r)
  INTO missing_roles
  FROM (
    SELECT unnest(ARRAY[
      'mlbplatformadmin','mlbappuser','mlbreadonly','mlbworker','mlbapi'
    ]) AS r
  ) expected
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_roles p WHERE p.rolname = expected.r
  );

  IF missing_roles IS NOT NULL THEN
    RAISE EXCEPTION 'Missing roles: %', missing_roles;
  END IF;
END $$;

DO $$
DECLARE
  missing_functions text[];
BEGIN
  SELECT array_agg(fn)
  INTO missing_functions
  FROM (
    SELECT unnest(ARRAY[
      'util.sha256text(text)',
      'util.registerpayloadhash(smallint,bigint,uuid,text,bytea)',
      'util.startingestrun(text,text,text,jsonb,text,date,date)',
      'util.normalizeretrosheetrecordtype(text)',
      'util.buildretrosheetgameid(text,date,smallint)',
      'util.shouldstoplivepolling(text,text,text)',
      'util.claimnextjob(text,text,integer)'
    ]) AS fn
  ) expected
  WHERE to_regprocedure(expected.fn) IS NULL;

  IF missing_functions IS NOT NULL THEN
    RAISE EXCEPTION 'Missing functions: %', missing_functions;
  END IF;
END $$;

DO $$
DECLARE
  source_count integer;
BEGIN
  SELECT COUNT(*) INTO source_count FROM meta.sourcesystem;
  IF source_count < 8 THEN
    RAISE EXCEPTION 'Expected seeded source systems, found only %', source_count;
  END IF;
END $$;

SELECT 'smoke tests passed' AS result;
