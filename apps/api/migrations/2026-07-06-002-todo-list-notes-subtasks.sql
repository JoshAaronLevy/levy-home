BEGIN;

ALTER TABLE todo_list
  ADD COLUMN IF NOT EXISTS notes TEXT,
  ADD COLUMN IF NOT EXISTS subtasks JSONB;

UPDATE todo_list
SET subtasks = '[]'::jsonb
WHERE subtasks IS NULL;

ALTER TABLE todo_list
  ALTER COLUMN subtasks SET DEFAULT '[]'::jsonb,
  ALTER COLUMN subtasks SET NOT NULL;

COMMIT;
