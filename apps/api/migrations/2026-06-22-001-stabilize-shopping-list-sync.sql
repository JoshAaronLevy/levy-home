BEGIN;

ALTER TABLE shopping_list
  ALTER COLUMN quantity SET DEFAULT 1,
  ALTER COLUMN purchased SET DEFAULT false,
  ALTER COLUMN created_at SET DEFAULT now(),
  ALTER COLUMN updated_at SET DEFAULT now();

UPDATE shopping_list
SET
  quantity = COALESCE(quantity, 1),
  purchased = COALESCE(purchased, false),
  created_at = COALESCE(created_at, now()),
  updated_at = COALESCE(updated_at, created_at, now());

ALTER TABLE shopping_list
  ALTER COLUMN quantity SET NOT NULL,
  ALTER COLUMN purchased SET NOT NULL,
  ALTER COLUMN created_at SET NOT NULL,
  ALTER COLUMN updated_at SET NOT NULL;

ALTER TABLE shopping_list
  ADD COLUMN IF NOT EXISTS version INTEGER;

UPDATE shopping_list
SET version = COALESCE(version, 1);

ALTER TABLE shopping_list
  ALTER COLUMN version SET DEFAULT 1,
  ALTER COLUMN version SET NOT NULL;

CREATE OR REPLACE FUNCTION set_shopping_list_sync_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_at = now();
    NEW.updated_at = NEW.created_at;
    NEW.version = 1;
  ELSE
    NEW.created_at = OLD.created_at;
    NEW.updated_at = now();
    NEW.version = COALESCE(OLD.version, 1) + 1;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS shopping_list_set_sync_fields ON shopping_list;

CREATE TRIGGER shopping_list_set_sync_fields
BEFORE INSERT OR UPDATE ON shopping_list
FOR EACH ROW
EXECUTE FUNCTION set_shopping_list_sync_fields();

ALTER TABLE shopping_locations
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

UPDATE shopping_locations
SET updated_at = COALESCE(updated_at, now());

ALTER TABLE shopping_locations
  ALTER COLUMN updated_at SET NOT NULL;

ALTER TABLE shopping_categories
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

UPDATE shopping_categories
SET updated_at = COALESCE(updated_at, now());

ALTER TABLE shopping_categories
  ALTER COLUMN updated_at SET NOT NULL;

CREATE OR REPLACE FUNCTION set_updated_at_to_now()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS stores_set_updated_at ON shopping_locations;
DROP TRIGGER IF EXISTS shopping_locations_set_updated_at ON shopping_locations;

CREATE TRIGGER shopping_locations_set_updated_at
BEFORE UPDATE ON shopping_locations
FOR EACH ROW
EXECUTE FUNCTION set_updated_at_to_now();

DROP TRIGGER IF EXISTS categories_set_updated_at ON shopping_categories;
DROP TRIGGER IF EXISTS shopping_categories_set_updated_at ON shopping_categories;

CREATE TRIGGER shopping_categories_set_updated_at
BEFORE UPDATE ON shopping_categories
FOR EACH ROW
EXECUTE FUNCTION set_updated_at_to_now();

COMMIT;
