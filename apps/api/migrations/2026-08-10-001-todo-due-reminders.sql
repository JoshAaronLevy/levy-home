BEGIN;

CREATE TABLE IF NOT EXISTS todo_due_reminder_deliveries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  todo_item_id INTEGER NOT NULL REFERENCES todo_list(id) ON DELETE CASCADE,
  due_date DATE NOT NULL,
  reminder_kind TEXT NOT NULL,
  recipient_user_id INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  attempt_count INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_error_reason TEXT,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT todo_due_reminder_deliveries_kind_valid
    CHECK (reminder_kind IN ('morning', 'evening')),
  CONSTRAINT todo_due_reminder_deliveries_status_valid
    CHECK (status IN ('pending', 'sending', 'sent', 'failed', 'skipped', 'ambiguous')),
  CONSTRAINT todo_due_reminder_deliveries_attempt_count_nonnegative
    CHECK (attempt_count >= 0),
  CONSTRAINT todo_due_reminder_deliveries_unique_recipient
    UNIQUE (todo_item_id, due_date, reminder_kind, recipient_user_id)
);

CREATE INDEX IF NOT EXISTS todo_due_reminder_deliveries_due_idx
  ON todo_due_reminder_deliveries (status, due_date, next_attempt_at)
  WHERE status IN ('pending', 'ambiguous');

COMMIT;
