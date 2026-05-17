BEGIN;

CREATE INDEX IF NOT EXISTS idx_ops_job_dependency_parent
    ON ops.job_dependency (parent_scheduled_job_id, child_scheduled_job_id);

CREATE INDEX IF NOT EXISTS idx_ops_ingest_profile_source
    ON ops.ingest_profile (source_system_id, active_flag);

CREATE INDEX IF NOT EXISTS idx_ops_job_queue_due
    ON ops.job_queue (queue_name, job_status, run_at, priority, created_at);

CREATE INDEX IF NOT EXISTS idx_ops_job_queue_claimed
    ON ops.job_queue (queue_name, job_status, lease_expires_at)
    WHERE job_status = 'claimed';

CREATE INDEX IF NOT EXISTS idx_ops_job_queue_workspace
    ON ops.job_queue (workspace_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_job_queue_source
    ON ops.job_queue (source_system_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_job_queue_idempotency
    ON ops.job_queue (idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_ops_job_dead_letter_job
    ON ops.job_dead_letter (job_queue_id, moved_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_live_poll_rule_source
    ON ops.live_poll_rule (source_system_id, rule_code);

CREATE INDEX IF NOT EXISTS idx_ops_live_game_poller_claim
    ON ops.live_game_poller (poll_status, lease_expires_at, last_polled_at);

COMMIT;