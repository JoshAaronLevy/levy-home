BEGIN;

CREATE TABLE IF NOT EXISTS shopping_ai_readd_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID NOT NULL UNIQUE,
  actor TEXT NOT NULL,
  requested_text TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued',
  requested_phrase_count INTEGER NOT NULL DEFAULT 0,
  processed_phrase_count INTEGER NOT NULL DEFAULT 0,
  readded_count INTEGER NOT NULL DEFAULT 0,
  quantity_updated_count INTEGER NOT NULL DEFAULT 0,
  already_needed_count INTEGER NOT NULL DEFAULT 0,
  unmatched_count INTEGER NOT NULL DEFAULT 0,
  stale_skipped_count INTEGER NOT NULL DEFAULT 0,
  invalid_request_count INTEGER NOT NULL DEFAULT 0,
  unavailable_count INTEGER NOT NULL DEFAULT 0,
  undone_count INTEGER NOT NULL DEFAULT 0,
  public_summary JSONB NOT NULL DEFAULT '{"operations":[],"unmatched":[]}'::jsonb,
  undo_expires_at TIMESTAMPTZ,
  purge_after TIMESTAMPTZ,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT shopping_ai_readd_runs_actor_valid
    CHECK (actor IN ('Josh', 'Mallory')),
  CONSTRAINT shopping_ai_readd_runs_requested_text_bounded
    CHECK (length(requested_text) BETWEEN 1 AND 500),
  CONSTRAINT shopping_ai_readd_runs_status_valid
    CHECK (status IN ('queued', 'matching', 'applying', 'completed', 'completed_with_issues', 'failed', 'undone')),
  CONSTRAINT shopping_ai_readd_runs_counts_nonnegative
    CHECK (
      requested_phrase_count >= 0
      AND processed_phrase_count >= 0
      AND readded_count >= 0
      AND quantity_updated_count >= 0
      AND already_needed_count >= 0
      AND unmatched_count >= 0
      AND stale_skipped_count >= 0
      AND invalid_request_count >= 0
      AND unavailable_count >= 0
      AND undone_count >= 0
    ),
  CONSTRAINT shopping_ai_readd_runs_counts_consistent
    CHECK (
      processed_phrase_count = readded_count + quantity_updated_count + already_needed_count
        + unmatched_count + stale_skipped_count + invalid_request_count + unavailable_count + undone_count
      AND processed_phrase_count <= requested_phrase_count
    ),
  CONSTRAINT shopping_ai_readd_runs_public_summary_bounded
    CHECK (jsonb_typeof(public_summary) = 'object' AND octet_length(public_summary::text) <= 16384),
  CONSTRAINT shopping_ai_readd_runs_undo_window_valid
    CHECK (
      (status IN ('queued', 'matching', 'applying') AND undo_expires_at IS NULL AND purge_after IS NULL)
      OR
      (
        status IN ('completed', 'completed_with_issues', 'failed', 'undone')
        AND purge_after IS NOT NULL
        AND (undo_expires_at IS NULL OR purge_after > undo_expires_at)
      )
    ),
  CONSTRAINT shopping_ai_readd_runs_lifecycle_valid
    CHECK (
      (status = 'queued' AND started_at IS NULL AND finished_at IS NULL AND undo_expires_at IS NULL AND purge_after IS NULL)
      OR
      (status IN ('matching', 'applying') AND started_at IS NOT NULL AND finished_at IS NULL AND undo_expires_at IS NULL AND purge_after IS NULL)
      OR
      (status IN ('completed', 'completed_with_issues') AND started_at IS NOT NULL AND finished_at IS NOT NULL)
      OR
      (status = 'failed' AND started_at IS NOT NULL AND finished_at IS NOT NULL AND undo_expires_at IS NULL)
      OR
      (status = 'undone' AND started_at IS NOT NULL AND finished_at IS NOT NULL AND undo_expires_at IS NOT NULL AND purge_after IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS shopping_ai_readd_runs_status_submitted_at_idx
  ON shopping_ai_readd_runs (status, submitted_at DESC);

CREATE INDEX IF NOT EXISTS shopping_ai_readd_runs_purge_after_idx
  ON shopping_ai_readd_runs (purge_after)
  WHERE purge_after IS NOT NULL;

CREATE TABLE IF NOT EXISTS shopping_ai_readd_operations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id UUID NOT NULL REFERENCES shopping_ai_readd_runs(id) ON DELETE CASCADE,
  request_index INTEGER NOT NULL,
  requested_text TEXT NOT NULL,
  outcome TEXT NOT NULL,
  target_item_id INTEGER,
  snapshot_version INTEGER,
  prior_purchased BOOLEAN,
  prior_quantity INTEGER,
  applied_purchased BOOLEAN,
  applied_quantity INTEGER,
  match_kind TEXT,
  undo_status TEXT NOT NULL DEFAULT 'not_eligible',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT shopping_ai_readd_operations_request_index_nonnegative
    CHECK (request_index >= 0),
  CONSTRAINT shopping_ai_readd_operations_requested_text_bounded
    CHECK (length(requested_text) BETWEEN 1 AND 500),
  CONSTRAINT shopping_ai_readd_operations_outcome_valid
    CHECK (outcome IN ('re_added', 'quantity_updated', 'already_needed', 'unmatched', 'stale_skipped', 'invalid_request', 'unavailable', 'undone')),
  CONSTRAINT shopping_ai_readd_operations_match_kind_valid
    CHECK (match_kind IS NULL OR match_kind IN ('exact', 'normalized', 'semantic')),
  CONSTRAINT shopping_ai_readd_operations_snapshot_version_valid
    CHECK (snapshot_version IS NULL OR snapshot_version >= 1),
  CONSTRAINT shopping_ai_readd_operations_prior_quantity_valid
    CHECK (prior_quantity IS NULL OR prior_quantity BETWEEN 1 AND 99),
  CONSTRAINT shopping_ai_readd_operations_applied_quantity_valid
    CHECK (applied_quantity IS NULL OR applied_quantity BETWEEN 1 AND 99),
  CONSTRAINT shopping_ai_readd_operations_undo_status_valid
    CHECK (undo_status IN ('not_eligible', 'eligible', 'reverted', 'skipped_stale')),
  CONSTRAINT shopping_ai_readd_operations_undo_facts_valid
    CHECK (
      undo_status = 'not_eligible'
      OR (
        target_item_id IS NOT NULL
        AND snapshot_version IS NOT NULL
        AND prior_purchased IS NOT NULL
        AND prior_quantity IS NOT NULL
        AND applied_purchased IS NOT NULL
        AND applied_quantity IS NOT NULL
      )
    ),
  CONSTRAINT shopping_ai_readd_operations_one_phrase_per_run
    UNIQUE (run_id, request_index)
);

CREATE INDEX IF NOT EXISTS shopping_ai_readd_operations_run_undo_idx
  ON shopping_ai_readd_operations (run_id, undo_status, request_index);

CREATE OR REPLACE FUNCTION set_shopping_ai_readd_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS shopping_ai_readd_runs_set_updated_at ON shopping_ai_readd_runs;
CREATE TRIGGER shopping_ai_readd_runs_set_updated_at
BEFORE UPDATE ON shopping_ai_readd_runs
FOR EACH ROW
EXECUTE FUNCTION set_shopping_ai_readd_updated_at();

DROP TRIGGER IF EXISTS shopping_ai_readd_operations_set_updated_at ON shopping_ai_readd_operations;
CREATE TRIGGER shopping_ai_readd_operations_set_updated_at
BEFORE UPDATE ON shopping_ai_readd_operations
FOR EACH ROW
EXECUTE FUNCTION set_shopping_ai_readd_updated_at();

COMMIT;
