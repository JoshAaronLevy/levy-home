BEGIN;

CREATE TABLE IF NOT EXISTS push_devices (
  id TEXT PRIMARY KEY,
  lookup_key TEXT NOT NULL UNIQUE,
  token_hash TEXT NOT NULL,
  token TEXT NOT NULL,
  platform TEXT NOT NULL,
  provider TEXT NOT NULL,
  environment TEXT,
  app_version TEXT,
  device_name TEXT,
  registered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT push_devices_provider_check CHECK (provider IN ('apns', 'expo')),
  CONSTRAINT push_devices_platform_check CHECK (platform IN ('ios', 'android', 'unknown')),
  CONSTRAINT push_devices_environment_check CHECK (
    environment IS NULL OR environment IN ('sandbox', 'production')
  )
);

COMMENT ON COLUMN push_devices.token IS
  'Raw push tokens are stored deliberately because APNs delivery requires the device token. API responses and logs must keep tokens redacted.';

CREATE INDEX IF NOT EXISTS push_devices_token_hash_idx
  ON push_devices (token_hash);

CREATE INDEX IF NOT EXISTS push_devices_provider_environment_idx
  ON push_devices (provider, environment);

CREATE TABLE IF NOT EXISTS notification_preferences (
  device_key TEXT PRIMARY KEY,
  preferences JSONB NOT NULL DEFAULT '[]'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT notification_preferences_preferences_is_array
    CHECK (jsonb_typeof(preferences) = 'array')
);

COMMIT;
