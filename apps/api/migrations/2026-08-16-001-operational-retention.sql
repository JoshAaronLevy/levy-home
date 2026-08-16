BEGIN;

-- These partial indexes make the daily, bounded retention deletes seek only
-- terminal operational rows. Pending, sending, and ambiguous deliveries are
-- deliberately excluded so recovery behavior is never affected by retention.
CREATE INDEX IF NOT EXISTS shopping_live_activity_deliveries_terminal_retention_idx
  ON shopping_live_activity_deliveries (updated_at ASC)
  WHERE status IN ('sent', 'failed');

CREATE INDEX IF NOT EXISTS shopping_trip_summary_deliveries_terminal_retention_idx
  ON shopping_trip_summary_deliveries (updated_at ASC)
  WHERE status IN ('sent', 'failed', 'skipped');

CREATE INDEX IF NOT EXISTS todo_due_reminder_deliveries_terminal_retention_idx
  ON todo_due_reminder_deliveries (updated_at ASC)
  WHERE status IN ('sent', 'failed', 'skipped');

CREATE INDEX IF NOT EXISTS shopping_stock_price_check_runs_terminal_retention_idx
  ON shopping_stock_price_check_runs (finished_at ASC)
  WHERE status IN ('completed', 'completed_with_issues', 'failed');

CREATE INDEX IF NOT EXISTS push_devices_inactive_retention_idx
  ON push_devices (invalidated_at ASC)
  WHERE NOT is_active AND invalidated_at IS NOT NULL;

COMMIT;
