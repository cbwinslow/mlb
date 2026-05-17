BEGIN;

CREATE OR REPLACE FUNCTION util.calculate_retry_run_at(
    p_attempts INT,
    p_base_delay_seconds INT,
    p_backoff_multiplier NUMERIC,
    p_jitter_seconds INT
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
AS $$
DECLARE
    v_delay_seconds NUMERIC;
    v_jitter INT;
BEGIN
    v_delay_seconds := p_base_delay_seconds * POWER(p_backoff_multiplier, GREATEST(p_attempts - 1, 0));
    v_jitter := FLOOR(random() * GREATEST(p_jitter_seconds, 0) + 1)::INT;
    RETURN NOW() + make_interval(secs => (v_delay_seconds::INT + v_jitter));
END;
$$;

CREATE OR REPLACE FUNCTION util.claim_next_job(
    p_queue_name TEXT,
    p_claimed_by TEXT,
    p_lease_seconds INT DEFAULT 300
)
RETURNS TABLE (
    job_queue_id UUID,
    scheduled_job_id BIGINT,
    job_type_id BIGINT,
    workspace_id UUID,
    source_system_id BIGINT,
    ingest_profile_id BIGINT,
    payload_json JSONB,
    attempts INT,
    max_attempts INT,
    claim_token UUID
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_claim_token UUID := gen_random_uuid();
BEGIN
    RETURN QUERY
    WITH candidate AS (
        SELECT jq.job_queue_id
        FROM ops.job_queue jq
        WHERE jq.queue_name = p_queue_name
          AND jq.job_status = 'pending'
          AND jq.run_at <= NOW()
          AND (jq.lease_expires_at IS NULL OR jq.lease_expires_at <= NOW())
          AND jq.attempts < jq.max_attempts
        ORDER BY jq.priority ASC, jq.run_at ASC, jq.created_at ASC
        FOR UPDATE SKIP LOCKED
        LIMIT 1
    )
    UPDATE ops.job_queue jq
    SET job_status = 'claimed',
        claimed_at = NOW(),
        updated_at = NOW(),
        claimed_by = p_claimed_by,
        claim_token = v_claim_token,
        lease_expires_at = NOW() + make_interval(secs => p_lease_seconds),
        attempts = jq.attempts + 1
    FROM candidate c
    WHERE jq.job_queue_id = c.job_queue_id
    RETURNING
        jq.job_queue_id,
        jq.scheduled_job_id,
        jq.job_type_id,
        jq.workspace_id,
        jq.source_system_id,
        jq.ingest_profile_id,
        jq.payload_json,
        jq.attempts,
        jq.max_attempts,
        jq.claim_token;
END;
$$;

CREATE OR REPLACE FUNCTION util.complete_job(
    p_job_queue_id UUID,
    p_claim_token UUID,
    p_result_json JSONB DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE ops.job_queue
    SET job_status = 'success',
        result_json = p_result_json,
        completed_at = NOW(),
        updated_at = NOW(),
        lease_expires_at = NULL
    WHERE job_queue_id = p_job_queue_id
      AND claim_token = p_claim_token;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job completion rejected for %, invalid claim token', p_job_queue_id;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION util.fail_job_for_retry(
    p_job_queue_id UUID,
    p_claim_token UUID,
    p_error TEXT,
    p_base_delay_seconds INT DEFAULT 60,
    p_backoff_multiplier NUMERIC DEFAULT 2.0,
    p_jitter_seconds INT DEFAULT 15
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_attempts INT;
    v_max_attempts INT;
    v_next_run_at TIMESTAMPTZ;
BEGIN
    SELECT attempts, max_attempts
    INTO v_attempts, v_max_attempts
    FROM ops.job_queue
    WHERE job_queue_id = p_job_queue_id
      AND claim_token = p_claim_token
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job retry rejected for %, invalid claim token', p_job_queue_id;
    END IF;

    IF v_attempts >= v_max_attempts THEN
        UPDATE ops.job_queue
        SET job_status = 'dead_letter',
            last_error = p_error,
            last_error_at = NOW(),
            updated_at = NOW(),
            lease_expires_at = NULL
        WHERE job_queue_id = p_job_queue_id
          AND claim_token = p_claim_token;

        INSERT INTO ops.job_dead_letter (job_queue_id, dead_letter_reason, error_snapshot_json)
        VALUES (p_job_queue_id, p_error, jsonb_build_object('attempts', v_attempts, 'failed_at', NOW()));
    ELSE
        v_next_run_at := util.calculate_retry_run_at(v_attempts, p_base_delay_seconds, p_backoff_multiplier, p_jitter_seconds);

        UPDATE ops.job_queue
        SET job_status = 'pending',
            run_at = v_next_run_at,
            last_error = p_error,
            last_error_at = NOW(),
            updated_at = NOW(),
            lease_expires_at = NULL
        WHERE job_queue_id = p_job_queue_id
          AND claim_token = p_claim_token;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION util.recover_stale_claimed_jobs(
    p_queue_name TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_count BIGINT;
BEGIN
    UPDATE ops.job_queue
    SET job_status = 'pending',
        claimed_at = NULL,
        claimed_by = NULL,
        claim_token = NULL,
        lease_expires_at = NULL,
        updated_at = NOW()
    WHERE job_status = 'claimed'
      AND lease_expires_at IS NOT NULL
      AND lease_expires_at < NOW()
      AND (p_queue_name IS NULL OR queue_name = p_queue_name);

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION util.live_poll_should_stop(
    p_source_system_id BIGINT,
    p_abstract_game_state TEXT,
    p_coded_game_state TEXT,
    p_detailed_state TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE((
        SELECT BOOL_OR(stop_polling_when_matched)
        FROM ops.live_poll_rule
        WHERE source_system_id = p_source_system_id
          AND (
              (abstract_game_state_in IS NOT NULL AND p_abstract_game_state = ANY(abstract_game_state_in))
              OR (coded_game_state_in IS NOT NULL AND p_coded_game_state = ANY(coded_game_state_in))
              OR (detailed_state_in IS NOT NULL AND p_detailed_state = ANY(detailed_state_in))
          )
    ), FALSE)
$$;

COMMIT;