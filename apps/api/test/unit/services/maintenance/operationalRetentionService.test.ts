import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { OperationalRetentionStore } from '../../../../src/repositories/operationalRetentionRepository.js';
import {
  createOperationalRetentionService,
  operationalRetentionPolicy,
} from '../../../../src/services/maintenance/operationalRetentionService.js';

test('operational retention drains bounded batches with the documented retention cutoffs', async () => {
  const now = new Date('2026-08-16T12:00:00.000Z');
  const calls: Array<{ name: string; cutoff?: Date; limit: number }> = [];
  const logger = recordedLogger();
  const retentionStore: OperationalRetentionStore = {
    cleanupTerminalLiveActivityDeliveries: queuedCleanup('liveActivityDeliveries', [100, 2], calls),
    cleanupTerminalTripSummaryDeliveries: queuedCleanup('tripSummaryDeliveries', [1], calls),
    cleanupTerminalToDoReminderDeliveries: queuedCleanup('toDoReminderDeliveries', [0], calls),
    cleanupTerminalStockPriceCheckRuns: queuedCleanup('stockPriceCheckRuns', [0], calls),
    cleanupInactivePushDevices: queuedCleanup('inactivePushDevices', [0], calls),
  };
  const readdCalls: number[] = [];
  const readdBatches = [100, 4];
  const service = createOperationalRetentionService({
    logger,
    now: () => now,
    operationalRetentionStore: retentionStore,
    shoppingListReaddStore: {
      async cleanupExpiredRuns(limit) {
        readdCalls.push(limit ?? -1);
        return readdBatches.shift() ?? 0;
      },
    },
  });

  const result = await service.runOnce();

  assert.deepEqual(result, {
    shoppingListReaddRuns: 104,
    liveActivityDeliveries: 102,
    tripSummaryDeliveries: 1,
    toDoReminderDeliveries: 0,
    stockPriceCheckRuns: 0,
    inactivePushDevices: 0,
  });
  assert.deepEqual(readdCalls, [operationalRetentionPolicy.batchSize, operationalRetentionPolicy.batchSize]);
  assert.deepEqual(
    calls.filter((call) => call.name === 'liveActivityDeliveries').map((call) => call.limit),
    [operationalRetentionPolicy.batchSize, operationalRetentionPolicy.batchSize],
  );
  assert.equal(
    calls.find((call) => call.name === 'liveActivityDeliveries')?.cutoff?.toISOString(),
    '2026-05-18T12:00:00.000Z',
  );
  assert.equal(
    calls.find((call) => call.name === 'stockPriceCheckRuns')?.cutoff?.toISOString(),
    '2026-07-17T12:00:00.000Z',
  );
  assert.equal(
    calls.find((call) => call.name === 'inactivePushDevices')?.cutoff?.toISOString(),
    '2026-02-17T12:00:00.000Z',
  );
  assert.deepEqual(logger.infoCalls, [{
    message: 'Operational retention cleanup completed.',
    details: result,
  }]);
  assert.deepEqual(logger.errorCalls, []);
});

test('a failed retention target is logged and does not prevent other cleanup work', async () => {
  const logger = recordedLogger();
  const calls: Array<{ name: string; cutoff?: Date; limit: number }> = [];
  const service = createOperationalRetentionService({
    logger,
    operationalRetentionStore: {
      cleanupTerminalLiveActivityDeliveries: queuedCleanup('liveActivityDeliveries', [0], calls),
      cleanupTerminalTripSummaryDeliveries: queuedCleanup('tripSummaryDeliveries', [0], calls),
      cleanupTerminalToDoReminderDeliveries: queuedCleanup('toDoReminderDeliveries', [0], calls),
      async cleanupTerminalStockPriceCheckRuns() {
        throw new Error('database temporarily unavailable');
      },
      cleanupInactivePushDevices: queuedCleanup('inactivePushDevices', [3], calls),
    },
  });

  const result = await service.runOnce();

  assert.equal(result.stockPriceCheckRuns, 0);
  assert.equal(result.inactivePushDevices, 3);
  assert.equal(logger.errorCalls.length, 1);
  assert.equal(logger.errorCalls[0]?.details?.operation, 'stockPriceCheckRuns');
  assert.equal(logger.infoCalls.length, 1);
});

test('maintenance starts immediately, schedules one daily follow-up, and stops cleanly', async () => {
  const logger = recordedLogger();
  const timers: Array<{ callback: () => void; delayMs: number; cleared: boolean }> = [];
  const service = createOperationalRetentionService({
    logger,
    operationalRetentionStore: emptyRetentionStore(),
    setTimeout(callback, delayMs) {
      const timer = { callback, delayMs, cleared: false };
      timers.push(timer);
      return timer as unknown as ReturnType<typeof setTimeout>;
    },
    clearTimeout(timer) {
      (timer as unknown as { cleared: boolean }).cleared = true;
    },
  });

  service.start();
  await settle();
  service.start();

  assert.equal(logger.infoCalls.length, 1);
  assert.equal(timers.length, 1);
  assert.equal(timers[0]?.delayMs, operationalRetentionPolicy.intervalMs);
  service.stop();
  assert.equal(timers[0]?.cleared, true);
});

function queuedCleanup(
  name: string,
  batches: number[],
  calls: Array<{ name: string; cutoff?: Date; limit: number }>,
): (cutoff: Date, limit?: number) => Promise<number> {
  return async (cutoff, limit) => {
    calls.push({ name, cutoff, limit: limit ?? -1 });
    return batches.shift() ?? 0;
  };
}

function emptyRetentionStore(): OperationalRetentionStore {
  return {
    async cleanupTerminalLiveActivityDeliveries() { return 0; },
    async cleanupTerminalTripSummaryDeliveries() { return 0; },
    async cleanupTerminalToDoReminderDeliveries() { return 0; },
    async cleanupTerminalStockPriceCheckRuns() { return 0; },
    async cleanupInactivePushDevices() { return 0; },
  };
}

function recordedLogger(): {
  info: (message: string, details?: Record<string, unknown>) => void;
  error: (message: string, details?: Record<string, unknown>) => void;
  infoCalls: Array<{ message: string; details?: Record<string, unknown> }>;
  errorCalls: Array<{ message: string; details?: Record<string, unknown> }>;
} {
  const infoCalls: Array<{ message: string; details?: Record<string, unknown> }> = [];
  const errorCalls: Array<{ message: string; details?: Record<string, unknown> }> = [];

  return {
    info(message, details) {
      infoCalls.push({ message, details });
    },
    error(message, details) {
      errorCalls.push({ message, details });
    },
    infoCalls,
    errorCalls,
  };
}

async function settle(): Promise<void> {
  await new Promise<void>((resolve) => setImmediate(resolve));
}
