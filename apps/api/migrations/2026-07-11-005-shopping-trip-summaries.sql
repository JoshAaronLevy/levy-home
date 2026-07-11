BEGIN;

CREATE TABLE IF NOT EXISTS shopping_trip_summary_deliveries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id UUID NOT NULL REFERENCES shopping_trips(id) ON DELETE CASCADE,
  recipient TEXT NOT NULL,
  push_device_id TEXT NOT NULL REFERENCES push_devices(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  attempt_count INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  apns_id TEXT,
  last_error_reason TEXT,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT shopping_trip_summary_deliveries_recipient_valid
    CHECK (recipient IN ('Josh', 'Mallory')),
  CONSTRAINT shopping_trip_summary_deliveries_status_valid
    CHECK (status IN ('pending', 'sending', 'sent', 'failed', 'skipped', 'ambiguous')),
  CONSTRAINT shopping_trip_summary_deliveries_attempt_count_nonnegative
    CHECK (attempt_count >= 0),
  CONSTRAINT shopping_trip_summary_deliveries_unique_device
    UNIQUE (trip_id, push_device_id)
);

CREATE INDEX IF NOT EXISTS shopping_trip_summary_deliveries_due_idx
  ON shopping_trip_summary_deliveries (status, next_attempt_at, created_at)
  WHERE status IN ('pending', 'ambiguous');

CREATE OR REPLACE FUNCTION set_shopping_trip_summary_delivery_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS shopping_trip_summary_deliveries_set_updated_at ON shopping_trip_summary_deliveries;
CREATE TRIGGER shopping_trip_summary_deliveries_set_updated_at
BEFORE UPDATE ON shopping_trip_summary_deliveries
FOR EACH ROW
EXECUTE FUNCTION set_shopping_trip_summary_delivery_updated_at();

COMMIT;
