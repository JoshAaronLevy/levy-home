BEGIN;

CREATE TABLE IF NOT EXISTS shopping_trips (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  status TEXT NOT NULL DEFAULT 'active',
  started_by TEXT NOT NULL,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_by TEXT,
  ended_at TIMESTAMPTZ,
  version INTEGER NOT NULL DEFAULT 1,
  currency_code TEXT NOT NULL DEFAULT 'USD',
  start_mutation_id UUID NOT NULL,
  end_mutation_id UUID,
  summary_recipient TEXT,
  summary_enqueued_at TIMESTAMPTZ,
  CONSTRAINT shopping_trips_status_valid
    CHECK (status IN ('active', 'completed')),
  CONSTRAINT shopping_trips_started_by_valid
    CHECK (started_by IN ('Josh', 'Mallory')),
  CONSTRAINT shopping_trips_ended_by_valid
    CHECK (ended_by IS NULL OR ended_by IN ('Josh', 'Mallory')),
  CONSTRAINT shopping_trips_summary_recipient_valid
    CHECK (summary_recipient IS NULL OR summary_recipient IN ('Josh', 'Mallory')),
  CONSTRAINT shopping_trips_version_positive
    CHECK (version >= 1),
  CONSTRAINT shopping_trips_currency_code_valid
    CHECK (currency_code ~ '^[A-Z]{3}$'),
  CONSTRAINT shopping_trips_completion_shape_valid
    CHECK (
      (status = 'active' AND ended_by IS NULL AND ended_at IS NULL)
      OR
      (status = 'completed' AND ended_by IS NOT NULL AND ended_at IS NOT NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS shopping_trips_one_active_idx
  ON shopping_trips ((1))
  WHERE status = 'active';

CREATE UNIQUE INDEX IF NOT EXISTS shopping_trips_start_mutation_id_idx
  ON shopping_trips (start_mutation_id);

CREATE UNIQUE INDEX IF NOT EXISTS shopping_trips_end_mutation_id_idx
  ON shopping_trips (end_mutation_id)
  WHERE end_mutation_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS shopping_trips_status_started_at_idx
  ON shopping_trips (status, started_at DESC);

CREATE TABLE IF NOT EXISTS shopping_trip_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id UUID NOT NULL REFERENCES shopping_trips(id) ON DELETE CASCADE,
  shopping_item_id INTEGER REFERENCES shopping_list(id) ON DELETE SET NULL,
  snapshot_position INTEGER NOT NULL,
  name_snapshot TEXT NOT NULL,
  quantity_snapshot INTEGER NOT NULL DEFAULT 1,
  estimated_unit_price_cents BIGINT,
  price_source TEXT,
  store_id INTEGER,
  state TEXT NOT NULL DEFAULT 'remaining',
  picked_up_by TEXT,
  picked_up_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT shopping_trip_items_name_not_blank
    CHECK (length(btrim(name_snapshot)) > 0),
  CONSTRAINT shopping_trip_items_snapshot_position_nonnegative
    CHECK (snapshot_position >= 0),
  CONSTRAINT shopping_trip_items_quantity_positive
    CHECK (quantity_snapshot >= 1),
  CONSTRAINT shopping_trip_items_estimated_price_nonnegative
    CHECK (estimated_unit_price_cents IS NULL OR estimated_unit_price_cents >= 0),
  CONSTRAINT shopping_trip_items_state_valid
    CHECK (state IN ('remaining', 'picked_up', 'removed')),
  CONSTRAINT shopping_trip_items_picked_up_by_valid
    CHECK (picked_up_by IS NULL OR picked_up_by IN ('Josh', 'Mallory')),
  CONSTRAINT shopping_trip_items_pickup_shape_valid
    CHECK (
      (state = 'picked_up' AND picked_up_by IS NOT NULL AND picked_up_at IS NOT NULL)
      OR
      (state IN ('remaining', 'removed') AND picked_up_by IS NULL AND picked_up_at IS NULL)
    ),
  CONSTRAINT shopping_trip_items_one_snapshot_per_item
    UNIQUE (trip_id, shopping_item_id),
  CONSTRAINT shopping_trip_items_snapshot_position_unique
    UNIQUE (trip_id, snapshot_position)
);

CREATE INDEX IF NOT EXISTS shopping_trip_items_trip_state_idx
  ON shopping_trip_items (trip_id, state);

CREATE INDEX IF NOT EXISTS shopping_trip_items_shopping_item_idx
  ON shopping_trip_items (shopping_item_id)
  WHERE shopping_item_id IS NOT NULL;

CREATE OR REPLACE FUNCTION set_shopping_trip_item_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS shopping_trip_items_set_updated_at ON shopping_trip_items;

CREATE TRIGGER shopping_trip_items_set_updated_at
BEFORE UPDATE ON shopping_trip_items
FOR EACH ROW
EXECUTE FUNCTION set_shopping_trip_item_updated_at();

COMMIT;
