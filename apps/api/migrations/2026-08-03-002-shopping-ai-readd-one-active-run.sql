BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS shopping_ai_readd_one_active_run_idx
  ON shopping_ai_readd_runs ((1))
  WHERE status IN ('queued', 'matching', 'applying');

COMMIT;
