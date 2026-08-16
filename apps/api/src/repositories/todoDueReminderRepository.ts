import type { DatabaseQuery, DatabaseTransactionRunner } from '../db/client.js';
import { getDatabaseClient, getDatabaseTransactionRunner } from '../db/client.js';
import { jsonb, optionalString, requiredInteger, requiredString } from '../db/rowReaders.js';
import { TODO_FAMILY_USER_IDS } from '../contracts.js';

export type ToDoDueReminderKind = 'morning' | 'evening';

export type ToDoDueReminderDelivery = {
  id: string;
  todoItemId: number;
  itemName: string;
  dueDate: string;
  reminderKind: ToDoDueReminderKind;
  recipientUserId: number;
  attemptCount: number;
};

export type ToDoDueReminderPendingDelivery = Pick<
  ToDoDueReminderDelivery,
  'dueDate' | 'reminderKind'
> & {
  nextAttemptAt: Date;
};

export type ToDoDueReminderStore = {
  enqueueDueReminders: (dueDate: string, reminderKind: ToDoDueReminderKind) => Promise<void>;
  discardExpiredAndIneligibleDeliveries: (currentDueDate: string) => Promise<void>;
  claimDueDeliveries: (
    dueDate: string,
    reminderKind: ToDoDueReminderKind,
    limit: number,
  ) => Promise<ToDoDueReminderDelivery[]>;
  markSent: (deliveryId: string) => Promise<void>;
  markSkipped: (deliveryId: string, reason: string) => Promise<void>;
  markPermanentFailure: (deliveryId: string, reason: string) => Promise<void>;
  markRetryableFailure: (deliveryId: string, reason: string, nextAttemptAt: Date) => Promise<void>;
  recoverStaleClaims: () => Promise<void>;
  findNextPendingDelivery: (currentDueDate: string) => Promise<ToDoDueReminderPendingDelivery | undefined>;
};

type DeliveryRow = Record<string, unknown> & {
  id: unknown;
  todoItemId: unknown;
  itemName: unknown;
  dueDate: unknown;
  reminderKind: unknown;
  recipientUserId: unknown;
  attemptCount: unknown;
};

type PendingDeliveryRow = Record<string, unknown> & {
  dueDate: unknown;
  reminderKind: unknown;
  nextAttemptAt: unknown;
};

export function createPostgresToDoDueReminderStore(options: {
  database?: DatabaseQuery;
  transactionRunner?: DatabaseTransactionRunner;
} = {}): ToDoDueReminderStore {
  if (Boolean(options.database) !== Boolean(options.transactionRunner)) {
    throw new Error('database and transactionRunner must be injected together.');
  }

  const query = () => options.database ?? getDatabaseClient();
  const transaction = () => options.transactionRunner ?? getDatabaseTransactionRunner();

  return {
    async enqueueDueReminders(dueDate, reminderKind) {
      await query()`
        INSERT INTO todo_due_reminder_deliveries (
          todo_item_id,
          due_date,
          reminder_kind,
          recipient_user_id
        )
        SELECT DISTINCT
          item.id,
          ${dueDate}::date,
          ${reminderKind},
          audience.user_id::integer
        FROM todo_list item
        CROSS JOIN LATERAL jsonb_array_elements_text(
          COALESCE(item.created_for, ${jsonb(TODO_FAMILY_USER_IDS)}::jsonb)
        ) AS audience(user_id)
        WHERE item.status = 'open'
          AND item.date IS NOT NULL
          AND (item.date AT TIME ZONE 'America/Denver')::date = ${dueDate}::date
        ON CONFLICT (todo_item_id, due_date, reminder_kind, recipient_user_id) DO NOTHING
      `;
    },
    async discardExpiredAndIneligibleDeliveries(currentDueDate) {
      await query()`
        UPDATE todo_due_reminder_deliveries delivery
        SET
          status = 'skipped',
          last_error_reason = 'To-do is no longer due, open, or visible to this recipient.',
          updated_at = now()
        FROM todo_list item
        WHERE delivery.todo_item_id = item.id
          AND delivery.status IN ('pending', 'ambiguous')
          AND (
            delivery.due_date < ${currentDueDate}::date
            OR item.status <> 'open'
            OR item.date IS NULL
            OR (item.date AT TIME ZONE 'America/Denver')::date <> delivery.due_date
            OR NOT COALESCE(item.created_for, ${jsonb(TODO_FAMILY_USER_IDS)}::jsonb)
              @> jsonb_build_array(delivery.recipient_user_id)
          )
      `;
    },
    async claimDueDeliveries(dueDate, reminderKind, limit) {
      return transaction()(async (database) => {
        const rows = await database<DeliveryRow>`
          WITH claimed AS (
            SELECT delivery.id
            FROM todo_due_reminder_deliveries delivery
            INNER JOIN todo_list item ON item.id = delivery.todo_item_id
            WHERE delivery.status IN ('pending', 'ambiguous')
              AND delivery.next_attempt_at <= now()
              AND delivery.due_date = ${dueDate}::date
              AND delivery.reminder_kind = ${reminderKind}
              AND item.status = 'open'
              AND item.date IS NOT NULL
              AND (item.date AT TIME ZONE 'America/Denver')::date = delivery.due_date
              AND COALESCE(item.created_for, ${jsonb(TODO_FAMILY_USER_IDS)}::jsonb)
                @> jsonb_build_array(delivery.recipient_user_id)
            ORDER BY delivery.next_attempt_at ASC, delivery.created_at ASC
            LIMIT ${Math.max(1, Math.min(limit, 50))}
            FOR UPDATE OF delivery SKIP LOCKED
          )
          UPDATE todo_due_reminder_deliveries delivery
          SET
            status = 'sending',
            attempt_count = attempt_count + 1,
            updated_at = now()
          FROM claimed, todo_list item
          WHERE delivery.id = claimed.id
            AND item.id = delivery.todo_item_id
          RETURNING
            delivery.id,
            delivery.todo_item_id AS "todoItemId",
            item.name AS "itemName",
            delivery.due_date AS "dueDate",
            delivery.reminder_kind AS "reminderKind",
            delivery.recipient_user_id AS "recipientUserId",
            delivery.attempt_count AS "attemptCount"
        `;

        return rows.map(toDoDueReminderDeliveryFromRow);
      });
    },
    async markSent(deliveryId) {
      await query()`
        UPDATE todo_due_reminder_deliveries
        SET status = 'sent', sent_at = now(), last_error_reason = NULL, updated_at = now()
        WHERE id = ${deliveryId}
      `;
    },
    async markSkipped(deliveryId, reason) {
      await terminal(query(), deliveryId, 'skipped', reason);
    },
    async markPermanentFailure(deliveryId, reason) {
      await terminal(query(), deliveryId, 'failed', reason);
    },
    async markRetryableFailure(deliveryId, reason, nextAttemptAt) {
      await query()`
        UPDATE todo_due_reminder_deliveries
        SET
          status = 'pending',
          last_error_reason = ${reason},
          next_attempt_at = ${nextAttemptAt.toISOString()},
          updated_at = now()
        WHERE id = ${deliveryId}
      `;
    },
    async recoverStaleClaims() {
      await query()`
        UPDATE todo_due_reminder_deliveries
        SET
          status = 'ambiguous',
          last_error_reason = 'Reminder worker restarted before APNs response was recorded.',
          next_attempt_at = now() + interval '30 seconds',
          updated_at = now()
        WHERE status = 'sending'
          AND updated_at < now() - interval '60 seconds'
      `;
    },
    async findNextPendingDelivery(currentDueDate) {
      const [row] = await query()<PendingDeliveryRow>`
        SELECT
          delivery.due_date AS "dueDate",
          delivery.reminder_kind AS "reminderKind",
          delivery.next_attempt_at AS "nextAttemptAt"
        FROM todo_due_reminder_deliveries delivery
        INNER JOIN todo_list item ON item.id = delivery.todo_item_id
        WHERE delivery.status IN ('pending', 'ambiguous')
          AND delivery.due_date >= ${currentDueDate}::date
          AND item.status = 'open'
          AND item.date IS NOT NULL
          AND (item.date AT TIME ZONE 'America/Denver')::date = delivery.due_date
          AND COALESCE(item.created_for, ${jsonb(TODO_FAMILY_USER_IDS)}::jsonb)
            @> jsonb_build_array(delivery.recipient_user_id)
        ORDER BY delivery.next_attempt_at ASC, delivery.created_at ASC
        LIMIT 1
      `;

      return row ? toDoDueReminderPendingDeliveryFromRow(row) : undefined;
    },
  };
}

async function terminal(
  database: DatabaseQuery,
  deliveryId: string,
  status: 'failed' | 'skipped',
  reason: string,
): Promise<void> {
  await database`
    UPDATE todo_due_reminder_deliveries
    SET status = ${status}, last_error_reason = ${reason}, updated_at = now()
    WHERE id = ${deliveryId}
  `;
}

function toDoDueReminderDeliveryFromRow(row: DeliveryRow): ToDoDueReminderDelivery {
  return {
    id: requiredString(row.id, 'todo_due_reminder_deliveries.id'),
    todoItemId: requiredInteger(row.todoItemId, 'todo_due_reminder_deliveries.todo_item_id'),
    itemName: requiredString(row.itemName, 'todo_list.name'),
    dueDate: requiredDueDate(row.dueDate),
    reminderKind: requiredReminderKind(row.reminderKind),
    recipientUserId: requiredInteger(row.recipientUserId, 'todo_due_reminder_deliveries.recipient_user_id'),
    attemptCount: requiredInteger(row.attemptCount, 'todo_due_reminder_deliveries.attempt_count'),
  };
}

function toDoDueReminderPendingDeliveryFromRow(row: PendingDeliveryRow): ToDoDueReminderPendingDelivery {
  const nextAttemptAt = row.nextAttemptAt instanceof Date
    ? row.nextAttemptAt
    : new Date(requiredString(row.nextAttemptAt, 'todo_due_reminder_deliveries.next_attempt_at'));

  if (!Number.isFinite(nextAttemptAt.getTime())) {
    throw new Error('Expected todo_due_reminder_deliveries.next_attempt_at to be a timestamp.');
  }

  return {
    dueDate: requiredDueDate(row.dueDate),
    reminderKind: requiredReminderKind(row.reminderKind),
    nextAttemptAt,
  };
}

function requiredDueDate(value: unknown): string {
  const dueDate = value instanceof Date
    ? value.toISOString().slice(0, 10)
    : optionalString(value);

  if (!dueDate || !/^\d{4}-\d{2}-\d{2}$/.test(dueDate)) {
    throw new Error('Expected todo_due_reminder_deliveries.due_date to be a YYYY-MM-DD date.');
  }

  return dueDate;
}

function requiredReminderKind(value: unknown): ToDoDueReminderKind {
  if (value === 'morning' || value === 'evening') {
    return value;
  }

  throw new Error('Expected todo_due_reminder_deliveries.reminder_kind to be known.');
}
