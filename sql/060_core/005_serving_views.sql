BEGIN;

CREATE OR REPLACE VIEW mart.v_source_system_status
WITH (security_barrier = true)
AS
SELECT
    ss.source_system_id,
    ss.source_code,
    ss.source_name,
    COALESCE(dsc.enabled_for_ingest, TRUE) AS enabled_for_ingest,
    COALESCE(dsc.enabled_for_serving, TRUE) AS enabled_for_serving,
    COALESCE(dsc.legal_hold, FALSE) AS legal_hold,
    COALESCE(dsc.quality_hold, FALSE) AS quality_hold,
    dsc.kill_switch_reason,
    dsc.effective_from,
    dsc.effective_to,
    dsc.updated_at
FROM meta.source_system ss
LEFT JOIN auth.data_source_control dsc
    ON dsc.source_system_id = ss.source_system_id;

CREATE OR REPLACE VIEW mart.v_workspace_source_access
WITH (security_barrier = true)
AS
SELECT
    w.workspace_id,
    w.workspace_code,
    ss.source_system_id,
    ss.source_code,
    util.source_is_enabled_for_serving(ss.source_system_id) AS source_globally_enabled_for_serving,
    util.workspace_can_view_source(w.workspace_id, ss.source_system_id) AS workspace_can_view_source_data,
    util.workspace_can_use_source(w.workspace_id, ss.source_system_id) AS workspace_can_use_for_modeling,
    util.workspace_can_trigger_ingest(w.workspace_id, ss.source_system_id) AS workspace_can_trigger_ingest
FROM auth.workspace w
CROSS JOIN meta.source_system ss;



CREATE OR REPLACE VIEW core.v_unified_plate_appearances AS 
SELECT 
    pa.plate_appearance_id,
    pa.game_id,
    g.game_date,
    g.season,
    pa.batter_id,
    pa.pitcher_id,
    pa.inning,
    pa.half_inning,
    pa.event_result_code,
    pa.data_source_lineage,
    EXISTS (SELECT 1 FROM core.pitches p WHERE p.plate_appearance_id = pa.plate_appearance_id) AS has_pitch_telemetry
FROM core.plate_appearances pa
JOIN core.games g ON pa.game_id = g.game_id;

COMMIT;