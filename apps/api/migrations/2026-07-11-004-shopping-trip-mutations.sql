BEGIN;

ALTER TABLE shopping_trips
  ADD COLUMN IF NOT EXISTS activity_updated_at_epoch_seconds BIGINT NOT NULL DEFAULT 0;

ALTER TABLE shopping_trips
  ADD CONSTRAINT shopping_trips_activity_timestamp_nonnegative
  CHECK (activity_updated_at_epoch_seconds >= 0);

COMMIT;
