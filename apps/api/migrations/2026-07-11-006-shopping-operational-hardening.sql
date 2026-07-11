BEGIN;

ALTER TABLE shopping_live_activity_registrations
  ADD COLUMN IF NOT EXISTS last_accepted_state_version INTEGER,
  ADD COLUMN IF NOT EXISTS last_accepted_at TIMESTAMPTZ;

ALTER TABLE push_devices
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS invalidated_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS push_devices_active_idx
  ON push_devices (provider, environment, registered_at)
  WHERE is_active;

COMMIT;
