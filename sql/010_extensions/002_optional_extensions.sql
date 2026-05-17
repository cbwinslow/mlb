BEGIN;

-- Optional but useful extensions. Enable only if available/desired in the target environment.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Install only when extension packages are available in the deployment environment.
-- CREATE EXTENSION IF NOT EXISTS pgaudit;
-- CREATE EXTENSION IF NOT EXISTS pg_cron;
-- CREATE EXTENSION IF NOT EXISTS vector;

COMMIT;