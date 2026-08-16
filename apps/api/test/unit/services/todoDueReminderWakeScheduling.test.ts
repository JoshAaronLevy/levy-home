import assert from 'node:assert/strict';
import { test } from 'node:test';

import type {
  ToDoDueReminderDelivery,
  ToDoDueReminderPendingDelivery,
  ToDoDueReminderStore,
} from '../../../src/repositories/todoDueReminderRepository.js';
import { createToDoDueReminderService } from '../../../src/services/todo/todoDueReminderService.js';

type FakeTimer = {
  callback: () => void;
  delayMs: number;
  cleared: boolean;
};

test('startup catches up the current Denver reminder slot once and schedules the next exact slot', async () => {
  let now = new Date('2026-01-15T15:00:00.000Z');
  const timers: FakeTimer[] = [];
  const enqueued: Array<{ dueDate: string; reminderKind: string }> = [];
  const store = fakeStore({
    async enqueueDueReminders(dueDate, reminderKind) {
      enqueued.push({ dueDate, reminderKind });
    },
  });
  const service = createToDoDueReminderService({
    logger: silentLogger(),
    now: () => now,
    notificationService: { async sendToDoDueReminderPush() { return sentStatus; } },
    toDoDueReminderStore: store,
    setTimeoutFn: fakeSetTimeout(timers),
    clearTimeoutFn: fakeClearTimeout,
  });

  service.start();
  await settle();

  assert.deepEqual(enqueued, [{ dueDate: '2026-01-15', reminderKind: 'morning' }]);
  assert.deepEqual(
    activeTimers(timers).map((timer) => timer.delayMs).sort((left, right) => left - right),
    [90_000, 60 * 60 * 1_000, 10 * 60 * 60 * 1_000],
  );

  now = new Date('2026-01-15T16:00:00.000Z');
  service.stop();
  assert.equal(activeTimers(timers).length, 0);
});

test('a known retry wakes at its persisted time and claims its original reminder kind without another enqueue', async () => {
  let now = new Date('2026-01-15T14:00:00.000Z');
  const timers: FakeTimer[] = [];
  const claims: Array<{ dueDate: string; reminderKind: string }> = [];
  let pending: ToDoDueReminderPendingDelivery | undefined = {
    dueDate: '2026-01-15',
    reminderKind: 'morning',
    nextAttemptAt: new Date(now.getTime() + 30_000),
  };
  const store = fakeStore({
    async claimDueDeliveries(dueDate, reminderKind) {
      claims.push({ dueDate, reminderKind });
      return [];
    },
    async findNextPendingDelivery() {
      return pending;
    },
  });
  const service = createToDoDueReminderService({
    logger: silentLogger(),
    now: () => now,
    notificationService: { async sendToDoDueReminderPush() { return sentStatus; } },
    toDoDueReminderStore: store,
    setTimeoutFn: fakeSetTimeout(timers),
    clearTimeoutFn: fakeClearTimeout,
  });

  service.start();
  await settle();
  const retryTimer = activeTimers(timers).find((timer) => timer.delayMs === 30_000);
  assert.ok(retryTimer, 'expected the earliest retry to have a dedicated wake-up');

  now = new Date(now.getTime() + 30_000);
  pending = undefined;
  retryTimer.cleared = true;
  retryTimer.callback();
  await settle();

  assert.deepEqual(claims, [{ dueDate: '2026-01-15', reminderKind: 'morning' }]);
  service.stop();
});

test('a failed reminder delivery persists and schedules its retry without another all-day poll', async () => {
  const now = new Date('2026-01-15T15:00:00.000Z');
  const timers: FakeTimer[] = [];
  const delivery: ToDoDueReminderDelivery = {
    id: 'delivery-1',
    todoItemId: 42,
    itemName: 'Return library books',
    dueDate: '2026-01-15',
    reminderKind: 'morning',
    recipientUserId: 1,
    attemptCount: 1,
  };
  let pending: ToDoDueReminderPendingDelivery | undefined;
  let shouldClaim = true;
  const store = fakeStore({
    async claimDueDeliveries() {
      if (!shouldClaim) {
        return [];
      }

      shouldClaim = false;
      return [delivery];
    },
    async markRetryableFailure(_deliveryId, _reason, nextAttemptAt) {
      pending = {
        dueDate: delivery.dueDate,
        reminderKind: delivery.reminderKind,
        nextAttemptAt,
      };
    },
    async findNextPendingDelivery() {
      return pending;
    },
  });
  const service = createToDoDueReminderService({
    logger: silentLogger(),
    now: () => now,
    notificationService: {
      async sendToDoDueReminderPush() {
        return { attempted: true, skipped: false, sentNotificationCount: 0, reason: 'temporary APNs rejection' };
      },
    },
    toDoDueReminderStore: store,
    setTimeoutFn: fakeSetTimeout(timers),
    clearTimeoutFn: fakeClearTimeout,
  });

  service.start();
  await settle();

  assert.ok(pending);
  assert.equal(pending.nextAttemptAt.getTime(), now.getTime() + 30_000);
  assert.ok(activeTimers(timers).some((timer) => timer.delayMs === 30_000));
  service.stop();
});

const sentStatus = { attempted: true, skipped: false, sentNotificationCount: 1 };

function fakeStore(overrides: Partial<ToDoDueReminderStore> = {}): ToDoDueReminderStore {
  return {
    async enqueueDueReminders() {},
    async discardExpiredAndIneligibleDeliveries() {},
    async claimDueDeliveries(): Promise<ToDoDueReminderDelivery[]> { return []; },
    async markSent() {},
    async markSkipped() {},
    async markPermanentFailure() {},
    async markRetryableFailure() {},
    async recoverStaleClaims() {},
    async findNextPendingDelivery() { return undefined; },
    ...overrides,
  };
}

function fakeSetTimeout(timers: FakeTimer[]): (callback: () => void, delayMs: number) => ReturnType<typeof setTimeout> {
  return (callback, delayMs) => {
    const timer: FakeTimer = { callback, delayMs, cleared: false };
    timers.push(timer);
    return timer as unknown as ReturnType<typeof setTimeout>;
  };
}

function fakeClearTimeout(timeout: ReturnType<typeof setTimeout>): void {
  (timeout as unknown as FakeTimer).cleared = true;
}

function activeTimers(timers: FakeTimer[]): FakeTimer[] {
  return timers.filter((timer) => !timer.cleared);
}

function silentLogger() {
  return { debug() {}, error() {}, info() {}, warn() {} };
}

async function settle(): Promise<void> {
  for (let turn = 0; turn < 8; turn += 1) {
    await Promise.resolve();
  }
}
