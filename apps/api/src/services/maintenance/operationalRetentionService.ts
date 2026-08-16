import type { ShoppingListReaddStore } from '../../repositories/shoppingListReaddRepository.js';
import {
  operationalRetentionBatchSize,
  type OperationalRetentionStore,
} from '../../repositories/operationalRetentionRepository.js';
import { safeErrorMessage, type Logger } from '../../observability/logger.js';

const millisecondsPerDay = 24 * 60 * 60 * 1_000;

export const operationalRetentionPolicy = Object.freeze({
  intervalMs: millisecondsPerDay,
  batchSize: operationalRetentionBatchSize,
  shoppingListReaddDays: 30,
  terminalDeliveryDays: 90,
  stockPriceCheckDays: 30,
  inactivePushDeviceDays: 180,
});

export type OperationalRetentionRunResult = {
  shoppingListReaddRuns: number;
  liveActivityDeliveries: number;
  tripSummaryDeliveries: number;
  toDoReminderDeliveries: number;
  stockPriceCheckRuns: number;
  inactivePushDevices: number;
};

export type OperationalRetentionService = {
  start: () => void;
  stop: () => void;
  runOnce: () => Promise<OperationalRetentionRunResult>;
};

type TimeoutHandle = ReturnType<typeof setTimeout>;

/**
 * Low-frequency operational cleanup. It drains small indexed batches so the
 * database never receives an unbounded retention delete.
 */
export function createOperationalRetentionService(options: {
  logger: Pick<Logger, 'error' | 'info'>;
  operationalRetentionStore: OperationalRetentionStore;
  shoppingListReaddStore?: Pick<ShoppingListReaddStore, 'cleanupExpiredRuns'>;
  now?: () => Date;
  setTimeout?: (callback: () => void, delayMs: number) => TimeoutHandle;
  clearTimeout?: (timeout: TimeoutHandle) => void;
}): OperationalRetentionService {
  const now = options.now ?? (() => new Date());
  const setTimeoutForMaintenance = options.setTimeout ?? setTimeout;
  const clearTimeoutForMaintenance = options.clearTimeout ?? clearTimeout;
  let started = false;
  let activeRun: Promise<OperationalRetentionRunResult> | undefined;
  let timer: TimeoutHandle | undefined;

  const runOnce = (): Promise<OperationalRetentionRunResult> => {
    if (activeRun) {
      return activeRun;
    }

    activeRun = runRetention().finally(() => {
      activeRun = undefined;
    });
    return activeRun;
  };

  const scheduleNextRun = (): void => {
    if (!started) {
      return;
    }

    timer = setTimeoutForMaintenance(() => {
      timer = undefined;
      void runAndReschedule();
    }, operationalRetentionPolicy.intervalMs);
    timer.unref?.();
  };

  const runAndReschedule = async (): Promise<void> => {
    try {
      await runOnce();
    } catch (error) {
      options.logger.error('Operational retention cleanup failed.', {
        error: safeErrorMessage(error),
      });
    } finally {
      scheduleNextRun();
    }
  };

  const runRetention = async (): Promise<OperationalRetentionRunResult> => {
    const runStartedAt = now();
    const readdCutoff = daysBefore(runStartedAt, operationalRetentionPolicy.shoppingListReaddDays);
    const deliveryCutoff = daysBefore(runStartedAt, operationalRetentionPolicy.terminalDeliveryDays);
    const stockPriceCutoff = daysBefore(runStartedAt, operationalRetentionPolicy.stockPriceCheckDays);
    const inactiveDeviceCutoff = daysBefore(runStartedAt, operationalRetentionPolicy.inactivePushDeviceDays);
    const result: OperationalRetentionRunResult = {
      shoppingListReaddRuns: await cleanup('shoppingListReaddRuns', () => options.shoppingListReaddStore
        ? drainBatches((limit) => options.shoppingListReaddStore!.cleanupExpiredRuns(limit))
        : Promise.resolve(0)),
      liveActivityDeliveries: await cleanup('liveActivityDeliveries', () => drainBatches(
        (limit) => options.operationalRetentionStore.cleanupTerminalLiveActivityDeliveries(deliveryCutoff, limit),
      )),
      tripSummaryDeliveries: await cleanup('tripSummaryDeliveries', () => drainBatches(
        (limit) => options.operationalRetentionStore.cleanupTerminalTripSummaryDeliveries(deliveryCutoff, limit),
      )),
      toDoReminderDeliveries: await cleanup('toDoReminderDeliveries', () => drainBatches(
        (limit) => options.operationalRetentionStore.cleanupTerminalToDoReminderDeliveries(deliveryCutoff, limit),
      )),
      stockPriceCheckRuns: await cleanup('stockPriceCheckRuns', () => drainBatches(
        (limit) => options.operationalRetentionStore.cleanupTerminalStockPriceCheckRuns(stockPriceCutoff, limit),
      )),
      inactivePushDevices: await cleanup('inactivePushDevices', () => drainBatches(
        (limit) => options.operationalRetentionStore.cleanupInactivePushDevices(inactiveDeviceCutoff, limit),
      )),
    };

    options.logger.info('Operational retention cleanup completed.', result);
    return result;
  };

  const cleanup = async (
    operation: keyof OperationalRetentionRunResult,
    execute: () => Promise<number>,
  ): Promise<number> => {
    try {
      return await execute();
    } catch (error) {
      options.logger.error('Operational retention cleanup operation failed.', {
        operation,
        error: safeErrorMessage(error),
      });
      return 0;
    }
  };

  return {
    start() {
      if (started) {
        return;
      }

      started = true;
      void runAndReschedule();
    },
    stop() {
      started = false;
      if (timer) {
        clearTimeoutForMaintenance(timer);
        timer = undefined;
      }
    },
    runOnce,
  };
}

async function drainBatches(cleanup: (limit: number) => Promise<number>): Promise<number> {
  let deleted = 0;

  while (true) {
    const batchDeleted = await cleanup(operationalRetentionPolicy.batchSize);
    deleted += batchDeleted;

    if (batchDeleted < operationalRetentionPolicy.batchSize) {
      return deleted;
    }
  }
}

function daysBefore(date: Date, days: number): Date {
  return new Date(date.getTime() - days * millisecondsPerDay);
}
