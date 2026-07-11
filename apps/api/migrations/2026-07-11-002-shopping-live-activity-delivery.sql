BEGIN;

CREATE TABLE IF NOT EXISTS shopping_live_activity_registrations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  push_device_id TEXT NOT NULL REFERENCES push_devices(id) ON DELETE CASCADE,
  resident TEXT NOT NULL,
  environment TEXT NOT NULL,
  token_type TEXT NOT NULL,
  trip_id UUID REFERENCES shopping_trips(id) ON DELETE CASCADE,
  token TEXT NOT NULL,
  token_hash TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  invalidated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT shopping_live_activity_registrations_resident_valid
    CHECK (resident IN ('Josh', 'Mallory')),
  CONSTRAINT shopping_live_activity_registrations_environment_valid
    CHECK (environment IN ('sandbox', 'production')),
  CONSTRAINT shopping_live_activity_registrations_token_type_valid
    CHECK (token_type IN ('push_to_start', 'activity_update')),
  CONSTRAINT shopping_live_activity_registrations_scope_valid
    CHECK (
      (token_type = 'push_to_start' AND trip_id IS NULL)
      OR
      (token_type = 'activity_update' AND trip_id IS NOT NULL)
    ),
  CONSTRAINT shopping_live_activity_registrations_invalidation_shape
    CHECK (
      (is_active AND invalidated_at IS NULL)
      OR
      (NOT is_active AND invalidated_at IS NOT NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS shopping_live_activity_registrations_active_scope_idx
  ON shopping_live_activity_registrations (
    push_device_id,
    token_type,
    environment,
    COALESCE(trip_id, '00000000-0000-0000-0000-000000000000'::uuid)
  )
  WHERE is_active;

CREATE UNIQUE INDEX IF NOT EXISTS shopping_live_activity_registrations_active_token_hash_idx
  ON shopping_live_activity_registrations (token_hash)
  WHERE is_active;

CREATE INDEX IF NOT EXISTS shopping_live_activity_registrations_trip_active_idx
  ON shopping_live_activity_registrations (trip_id, environment)
  WHERE is_active AND token_type = 'activity_update';

CREATE TABLE IF NOT EXISTS shopping_live_activity_deliveries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id UUID NOT NULL REFERENCES shopping_trips(id) ON DELETE CASCADE,
  registration_id UUID NOT NULL REFERENCES shopping_live_activity_registrations(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  state_version INTEGER NOT NULL,
  payload JSONB NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  attempt_count INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  apns_id TEXT,
  last_error_reason TEXT,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT shopping_live_activity_deliveries_event_type_valid
    CHECK (event_type IN ('start', 'update', 'end')),
  CONSTRAINT shopping_live_activity_deliveries_status_valid
    CHECK (status IN ('pending', 'sending', 'sent', 'failed', 'ambiguous')),
  CONSTRAINT shopping_live_activity_deliveries_attempt_count_nonnegative
    CHECK (attempt_count >= 0),
  CONSTRAINT shopping_live_activity_deliveries_state_version_positive
    CHECK (state_version >= 1),
  CONSTRAINT shopping_live_activity_deliveries_unique_event
    UNIQUE (trip_id, registration_id, event_type, state_version)
);

CREATE INDEX IF NOT EXISTS shopping_live_activity_deliveries_due_idx
  ON shopping_live_activity_deliveries (status, next_attempt_at, created_at)
  WHERE status IN ('pending', 'ambiguous');

CREATE OR REPLACE FUNCTION set_shopping_live_activity_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS shopping_live_activity_registrations_set_updated_at ON shopping_live_activity_registrations;
CREATE TRIGGER shopping_live_activity_registrations_set_updated_at
BEFORE UPDATE ON shopping_live_activity_registrations
FOR EACH ROW
EXECUTE FUNCTION set_shopping_live_activity_updated_at();

DROP TRIGGER IF EXISTS shopping_live_activity_deliveries_set_updated_at ON shopping_live_activity_deliveries;
CREATE TRIGGER shopping_live_activity_deliveries_set_updated_at
BEFORE UPDATE ON shopping_live_activity_deliveries
FOR EACH ROW
EXECUTE FUNCTION set_shopping_live_activity_updated_at();

COMMIT;
