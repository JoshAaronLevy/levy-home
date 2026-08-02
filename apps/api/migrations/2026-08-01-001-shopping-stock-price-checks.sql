BEGIN;

CREATE TABLE IF NOT EXISTS shopping_stock_price_check_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'queued',
  phase TEXT NOT NULL DEFAULT 'preparing',
  actor TEXT,
  requested_item_count INTEGER NOT NULL DEFAULT 0,
  processed_item_count INTEGER NOT NULL DEFAULT 0,
  updated_item_count INTEGER NOT NULL DEFAULT 0,
  unmatched_item_count INTEGER NOT NULL DEFAULT 0,
  failed_item_count INTEGER NOT NULL DEFAULT 0,
  skipped_stale_item_count INTEGER NOT NULL DEFAULT 0,
  failure_code TEXT,
  message TEXT,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT shopping_stock_price_check_runs_status_valid
    CHECK (status IN ('queued', 'running', 'completed', 'completed_with_issues', 'failed')),
  CONSTRAINT shopping_stock_price_check_runs_phase_valid
    CHECK (phase IN ('preparing', 'checking_stores', 'matching_products', 'applying_updates', 'finished')),
  CONSTRAINT shopping_stock_price_check_runs_counts_nonnegative
    CHECK (
      requested_item_count >= 0
      AND processed_item_count >= 0
      AND updated_item_count >= 0
      AND unmatched_item_count >= 0
      AND failed_item_count >= 0
      AND skipped_stale_item_count >= 0
    ),
  CONSTRAINT shopping_stock_price_check_runs_counts_consistent
    CHECK (
      processed_item_count = updated_item_count + unmatched_item_count + failed_item_count + skipped_stale_item_count
      AND processed_item_count <= requested_item_count
    ),
  CONSTRAINT shopping_stock_price_check_runs_lifecycle_valid
    CHECK (
      (status = 'queued' AND phase = 'preparing' AND started_at IS NULL AND finished_at IS NULL)
      OR
      (status = 'running' AND phase IN ('checking_stores', 'matching_products', 'applying_updates') AND started_at IS NOT NULL AND finished_at IS NULL)
      OR
      (status IN ('completed', 'completed_with_issues', 'failed') AND phase = 'finished' AND finished_at IS NOT NULL)
    ),
  CONSTRAINT shopping_stock_price_check_runs_failure_code_bounded
    CHECK (failure_code IS NULL OR length(failure_code) BETWEEN 1 AND 96),
  CONSTRAINT shopping_stock_price_check_runs_message_bounded
    CHECK (message IS NULL OR length(message) BETWEEN 1 AND 280)
);

CREATE UNIQUE INDEX IF NOT EXISTS shopping_stock_price_check_runs_one_active_idx
  ON shopping_stock_price_check_runs ((1))
  WHERE status IN ('queued', 'running');

CREATE INDEX IF NOT EXISTS shopping_stock_price_check_runs_status_submitted_at_idx
  ON shopping_stock_price_check_runs (status, submitted_at DESC);

CREATE TABLE IF NOT EXISTS shopping_stock_price_check_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id UUID NOT NULL REFERENCES shopping_stock_price_check_runs(id) ON DELETE CASCADE,
  shopping_item_id INTEGER NOT NULL,
  item_version INTEGER NOT NULL,
  snapshot_position INTEGER NOT NULL,
  item_snapshot JSONB NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  store_outcomes JSONB NOT NULL DEFAULT '[]'::jsonb,
  failure_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT shopping_stock_price_check_items_version_positive
    CHECK (item_version >= 1),
  CONSTRAINT shopping_stock_price_check_items_snapshot_position_nonnegative
    CHECK (snapshot_position >= 0),
  CONSTRAINT shopping_stock_price_check_items_snapshot_object
    CHECK (jsonb_typeof(item_snapshot) = 'object'),
  CONSTRAINT shopping_stock_price_check_items_store_outcomes_array
    CHECK (jsonb_typeof(store_outcomes) = 'array'),
  CONSTRAINT shopping_stock_price_check_items_status_valid
    CHECK (status IN ('pending', 'updated', 'unmatched', 'failed', 'skipped_stale')),
  CONSTRAINT shopping_stock_price_check_items_failure_code_bounded
    CHECK (failure_code IS NULL OR length(failure_code) BETWEEN 1 AND 96),
  CONSTRAINT shopping_stock_price_check_items_one_snapshot_per_item
    UNIQUE (run_id, shopping_item_id),
  CONSTRAINT shopping_stock_price_check_items_snapshot_position_unique
    UNIQUE (run_id, snapshot_position)
);

CREATE INDEX IF NOT EXISTS shopping_stock_price_check_items_run_status_idx
  ON shopping_stock_price_check_items (run_id, status, snapshot_position);

CREATE OR REPLACE FUNCTION set_shopping_stock_price_check_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS shopping_stock_price_check_runs_set_updated_at ON shopping_stock_price_check_runs;
CREATE TRIGGER shopping_stock_price_check_runs_set_updated_at
BEFORE UPDATE ON shopping_stock_price_check_runs
FOR EACH ROW
EXECUTE FUNCTION set_shopping_stock_price_check_updated_at();

DROP TRIGGER IF EXISTS shopping_stock_price_check_items_set_updated_at ON shopping_stock_price_check_items;
CREATE TRIGGER shopping_stock_price_check_items_set_updated_at
BEFORE UPDATE ON shopping_stock_price_check_items
FOR EACH ROW
EXECUTE FUNCTION set_shopping_stock_price_check_updated_at();

COMMIT;
