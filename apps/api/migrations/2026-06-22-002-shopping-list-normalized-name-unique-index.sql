BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS shopping_list_normalized_name_unique_idx
  ON shopping_list (lower(btrim(name)))
  WHERE name IS NOT NULL AND btrim(name) <> '';

COMMIT;
