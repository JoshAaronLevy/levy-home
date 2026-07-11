BEGIN;

CREATE TABLE IF NOT EXISTS shopping_trip_display_dispositions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id UUID NOT NULL REFERENCES shopping_trips(id) ON DELETE CASCADE,
  push_device_id TEXT NOT NULL REFERENCES push_devices(id) ON DELETE CASCADE,
  resident TEXT NOT NULL,
  kind TEXT NOT NULL,
  activity_registration_id UUID REFERENCES shopping_live_activity_registrations(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT shopping_trip_display_dispositions_resident_valid
    CHECK (resident IN ('Josh', 'Mallory')),
  CONSTRAINT shopping_trip_display_dispositions_kind_valid
    CHECK (kind IN ('start_locally', 'remote_start_pending')),
  CONSTRAINT shopping_trip_display_dispositions_unique_device
    UNIQUE (trip_id, push_device_id)
);

CREATE INDEX IF NOT EXISTS shopping_trip_display_dispositions_trip_idx
  ON shopping_trip_display_dispositions (trip_id, kind);

CREATE OR REPLACE FUNCTION set_shopping_trip_display_disposition_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS shopping_trip_display_dispositions_set_updated_at ON shopping_trip_display_dispositions;
CREATE TRIGGER shopping_trip_display_dispositions_set_updated_at
BEFORE UPDATE ON shopping_trip_display_dispositions
FOR EACH ROW
EXECUTE FUNCTION set_shopping_trip_display_disposition_updated_at();

COMMIT;
