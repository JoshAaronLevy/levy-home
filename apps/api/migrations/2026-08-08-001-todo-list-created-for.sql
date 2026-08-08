BEGIN;

ALTER TABLE todo_list
  ADD COLUMN IF NOT EXISTS created_for JSONB;

UPDATE todo_list
SET created_for = '[1,2]'::jsonb
WHERE created_for IS NULL;

ALTER TABLE todo_list
  ALTER COLUMN created_for SET DEFAULT '[1,2]'::jsonb,
  ALTER COLUMN created_for SET NOT NULL;

COMMIT;
