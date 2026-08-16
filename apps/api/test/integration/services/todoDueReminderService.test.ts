import assert from 'node:assert/strict';
import { test } from 'node:test';

import { createPostgresToDoDueReminderStore } from '../../../src/repositories/todoDueReminderRepository.js';
import {
  createToDoDueReminderService,
  nextToDoDueReminderSlotAt,
  toDoDueReminderScheduleAt,
} from '../../../src/services/todo/todoDueReminderService.js';
import { createDisposableShoppingDatabase } from '../../support/pgliteDatabase.js';

test('To Do due reminder schedule uses the current America/Denver calendar day', () => {
  assert.deepEqual(
    toDoDueReminderScheduleAt(new Date('2026-01-15T14:59:00.000Z')),
    { dueDate: '2026-01-15', reminderKinds: [] },
  );
  assert.deepEqual(
    toDoDueReminderScheduleAt(new Date('2026-01-15T15:00:00.000Z')),
    { dueDate: '2026-01-15', reminderKinds: ['morning'] },
  );
  assert.deepEqual(
    toDoDueReminderScheduleAt(new Date('2026-01-16T01:00:00.000Z')),
    { dueDate: '2026-01-15', reminderKinds: ['evening'] },
  );
});

test('the next To Do reminder slot is an exact America/Denver 8 AM or 6 PM wake-up across daylight saving time', () => {
  assert.deepEqual(
    nextToDoDueReminderSlotAt(new Date('2026-01-15T14:59:00.000Z')),
    {
      dueDate: '2026-01-15',
      reminderKind: 'morning',
      scheduledAt: new Date('2026-01-15T15:00:00.000Z'),
    },
  );
  assert.deepEqual(
    nextToDoDueReminderSlotAt(new Date('2026-01-15T15:00:00.000Z')),
    {
      dueDate: '2026-01-15',
      reminderKind: 'evening',
      scheduledAt: new Date('2026-01-16T01:00:00.000Z'),
    },
  );
  assert.deepEqual(
    nextToDoDueReminderSlotAt(new Date('2026-03-08T13:59:00.000Z')),
    {
      dueDate: '2026-03-08',
      reminderKind: 'morning',
      scheduledAt: new Date('2026-03-08T14:00:00.000Z'),
    },
  );
  assert.deepEqual(
    nextToDoDueReminderSlotAt(new Date('2026-11-01T14:59:00.000Z')),
    {
      dueDate: '2026-11-01',
      reminderKind: 'morning',
      scheduledAt: new Date('2026-11-01T15:00:00.000Z'),
    },
  );
});

test('the reminder store exposes the earliest valid pending retry for one-shot scheduling', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  const reminderStore = createPostgresToDoDueReminderStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  await disposable.database`
    INSERT INTO todo_list (name, date, status, created_for)
    VALUES ('Return library books', '2026-01-15T22:00:00.000Z', 'open', '[1]'::jsonb)
  `;
  await reminderStore.enqueueDueReminders('2026-01-15', 'morning');

  const pending = await reminderStore.findNextPendingDelivery('2026-01-15');

  assert.ok(pending);
  assert.equal(pending.dueDate, '2026-01-15');
  assert.equal(pending.reminderKind, 'morning');
  assert.equal(Number.isFinite(pending.nextAttemptAt.getTime()), true);
});

test('To Do due reminders deliver once to the item audience and skip completed, undated, and overdue items', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  const reminderStore = createPostgresToDoDueReminderStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  await disposable.database`
    INSERT INTO todo_list (name, date, status, created_for)
    VALUES
      ('Family passport forms', '2026-01-15T22:00:00.000Z', 'open', '[1,2]'::jsonb),
      ('Undated chore', NULL, 'open', '[1]'::jsonb),
      ('Overdue chore', '2026-01-14T22:00:00.000Z', 'open', '[2]'::jsonb)
  `;
  let now = new Date('2026-01-15T14:59:00.000Z');
  const sent: Array<{ itemName: string; recipientUserId: number; reminderKind: string }> = [];
  const service = createToDoDueReminderService({
    logger: { debug() {}, error() {}, info() {}, warn() {} },
    now: () => now,
    notificationService: {
      async sendToDoDueReminderPush(payload) {
        sent.push({
          itemName: payload.itemName,
          recipientUserId: payload.recipientUserId,
          reminderKind: payload.reminderKind,
        });
        return { attempted: true, skipped: false, sentNotificationCount: 1 };
      },
    },
    toDoDueReminderStore: reminderStore,
  });

  await service.processDueReminders();
  assert.deepEqual(sent, []);

  now = new Date('2026-01-15T15:00:00.000Z');
  await service.processDueReminders();
  await service.processDueReminders();
  assert.deepEqual(sent, [
    { itemName: 'Family passport forms', recipientUserId: 1, reminderKind: 'morning' },
    { itemName: 'Family passport forms', recipientUserId: 2, reminderKind: 'morning' },
  ]);

  await disposable.database`UPDATE todo_list SET status = 'completed' WHERE name = 'Family passport forms'`;
  now = new Date('2026-01-16T01:00:00.000Z');
  await service.processDueReminders();
  assert.equal(sent.length, 2);

  await disposable.database`
    INSERT INTO todo_list (name, date, status, created_for)
    VALUES ('Personal prescription refill', '2026-01-15T22:00:00.000Z', 'open', '[1]'::jsonb)
  `;
  await service.processDueReminders();
  assert.deepEqual(sent, [
    { itemName: 'Family passport forms', recipientUserId: 1, reminderKind: 'morning' },
    { itemName: 'Family passport forms', recipientUserId: 2, reminderKind: 'morning' },
    { itemName: 'Personal prescription refill', recipientUserId: 1, reminderKind: 'evening' },
  ]);

  const deliveries = await disposable.database<{ itemName: unknown; status: unknown; recipientUserId: unknown }>`
    SELECT item.name AS "itemName", delivery.status, delivery.recipient_user_id AS "recipientUserId"
    FROM todo_due_reminder_deliveries delivery
    INNER JOIN todo_list item ON item.id = delivery.todo_item_id
    ORDER BY item.name, delivery.recipient_user_id
  `;
  assert.deepEqual(deliveries, [
    { itemName: 'Family passport forms', status: 'sent', recipientUserId: 1 },
    { itemName: 'Family passport forms', status: 'sent', recipientUserId: 2 },
    { itemName: 'Personal prescription refill', status: 'sent', recipientUserId: 1 },
  ]);
});
