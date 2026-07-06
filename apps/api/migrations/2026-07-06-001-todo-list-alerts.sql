BEGIN;

ALTER TABLE todo_list
  ADD COLUMN IF NOT EXISTS alerts JSONB;

UPDATE todo_list
SET alerts = '[]'::jsonb
WHERE alerts IS NULL;

ALTER TABLE todo_list
  ALTER COLUMN alerts SET DEFAULT '[]'::jsonb,
  ALTER COLUMN alerts SET NOT NULL;

COMMIT;
