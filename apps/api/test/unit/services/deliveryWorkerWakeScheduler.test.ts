import assert from 'node:assert/strict';
import { test } from 'node:test';

import { createDeliveryWorkerWakeScheduler } from '../../../src/services/shopping/deliveryWorkerWakeScheduler.js';

type FakeTimer = {
  callback: () => void;
  delayMs: number;
  cleared: boolean;
};

test('runs immediately, wakes for the earliest retry, then returns to a recovery sweep', async () => {
  let nowMs = Date.UTC(2026, 7, 16, 12, 0, 0);
  const timers: FakeTimer[] = [];
  let runCount = 0;
  const scheduler = createDeliveryWorkerWakeScheduler({
    now: () => new Date(nowMs),
    recoverySweepIntervalMs: 10 * 60 * 1_000,
    run: async () => {
      runCount += 1;
    },
    onError(error) {
      throw error;
    },
    setTimeout(callback, delayMs) {
      const timer: FakeTimer = { callback, delayMs, cleared: false };
      timers.push(timer);
      return timer as unknown as ReturnType<typeof setTimeout>;
    },
    clearTimeout(timeout) {
      (timeout as unknown as FakeTimer).cleared = true;
    },
  });

  scheduler.start();
  await settle();
  assert.equal(runCount, 1);
  assert.equal(activeTimer(timers).delayMs, 10 * 60 * 1_000);

  scheduler.scheduleRetryAt(new Date(nowMs + 30_000));
  assert.equal(timers[0].cleared, true);
  assert.equal(activeTimer(timers).delayMs, 30_000);

  scheduler.scheduleRetryAt(new Date(nowMs + 60_000));
  assert.equal(timers.length, 2, 'a later retry must not displace the earliest scheduled wake');

  nowMs += 30_000;
  activeTimer(timers).callback();
  await settle();

  assert.equal(runCount, 2);
  assert.equal(activeTimer(timers).delayMs, 10 * 60 * 1_000);
});

test('stop cancels the outstanding recovery wake', async () => {
  const timers: FakeTimer[] = [];
  const scheduler = createDeliveryWorkerWakeScheduler({
    run: async () => undefined,
    onError(error) {
      throw error;
    },
    setTimeout(callback, delayMs) {
      const timer: FakeTimer = { callback, delayMs, cleared: false };
      timers.push(timer);
      return timer as unknown as ReturnType<typeof setTimeout>;
    },
    clearTimeout(timeout) {
      (timeout as unknown as FakeTimer).cleared = true;
    },
  });

  scheduler.start();
  await settle();
  scheduler.stop();

  assert.equal(timers.length, 1);
  assert.equal(timers[0].cleared, true);
});

function activeTimer(timers: FakeTimer[]): FakeTimer {
  const timer = [...timers].reverse().find((candidate) => !candidate.cleared);
  assert.ok(timer, 'expected one active timer');
  return timer;
}

async function settle(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}
