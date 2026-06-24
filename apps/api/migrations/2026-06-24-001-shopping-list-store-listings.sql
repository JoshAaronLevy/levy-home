BEGIN;

ALTER TABLE shopping_list
  ADD COLUMN IF NOT EXISTS image TEXT,
  ADD COLUMN IF NOT EXISTS store_listings JSONB NOT NULL DEFAULT '[]'::jsonb;

UPDATE shopping_list
SET store_listings = COALESCE(store_listings, '[]'::jsonb);

ALTER TABLE shopping_list
  DROP CONSTRAINT IF EXISTS shopping_list_store_listings_is_array;

ALTER TABLE shopping_list
  ADD CONSTRAINT shopping_list_store_listings_is_array
  CHECK (jsonb_typeof(store_listings) = 'array');

COMMIT;
