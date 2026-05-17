BEGIN;

CREATE INDEX IF NOT EXISTS idx_ops_source_loader_spec_source
    ON ops.source_loader_spec (source_system_id, active_flag);

CREATE INDEX IF NOT EXISTS idx_ops_source_endpoint_profile_loader
    ON ops.source_endpoint_profile (source_loader_spec_id, active_flag);

CREATE INDEX IF NOT EXISTS idx_ops_source_chunking_policy_loader
    ON ops.source_chunking_policy (source_loader_spec_id, active_flag);

CREATE INDEX IF NOT EXISTS idx_ops_file_acquisition_manifest_status
    ON ops.file_acquisition_manifest (source_loader_spec_id, file_status, season);

CREATE INDEX IF NOT EXISTS idx_ops_loader_run_binding_ingest
    ON ops.loader_run_binding (ingest_run_id, source_loader_spec_id);

CREATE INDEX IF NOT EXISTS idx_ops_live_endpoint_strategy_loader
    ON ops.live_endpoint_strategy (source_loader_spec_id, active_flag);

COMMIT;