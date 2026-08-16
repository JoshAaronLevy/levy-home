import type { EventPushStatus } from '../../contracts.js';
import { safeErrorMessage, type Logger } from '../../observability/logger.js';
import type {
  ToDoDueReminderDelivery,
  ToDoDueReminderKind,
  ToDoDueReminderPendingDelivery,
  ToDoDueReminderStore,
} from '../../repositories/todoDueReminderRepository.js';
import type { NotificationService } from '../notifications/notificationService.js';

export const toDoDueReminderTimeZone = 'America/Denver';
const morningReminderMinute = 8 * 60;
const eveningReminderMinute = 18 * 60;
const reminderDeliveryBatchSize = 50;
const maintenanceSweepIntervalMs = 60 * 60 * 1_000;
const startupRecoveryDelayMs = 90 * 1_000;

type TimeoutHandle = ReturnType<typeof setTimeout>;

export type ToDoDueReminderService = {
  processDueReminders: () => Promise<void>;
  start: () => void;
  stop: () => void;
};

export type ToDoDueReminderSchedule = {
  dueDate: string;
  reminderKinds: ToDoDueReminderKind[];
};

export type ToDoDueReminderSlot = {
  dueDate: string;
  reminderKind: ToDoDueReminderKind;
  scheduledAt: Date;
};

export function createToDoDueReminderService(options: {
  logger: Logger;
  notificationService: Pick<NotificationService, 'sendToDoDueReminderPush'>;
  now?: () => Date;
  toDoDueReminderStore: ToDoDueReminderStore;
  maintenanceSweepIntervalMs?: number;
  setTimeoutFn?: (callback: () => void, delayMs: number) => TimeoutHandle;
  clearTimeoutFn?: (timeout: TimeoutHandle) => void;
}): ToDoDueReminderService {
  const now = options.now ?? (() => new Date());
  const maintenanceIntervalMs = options.maintenanceSweepIntervalMs ?? maintenanceSweepIntervalMs;
  const setTimeoutForWorker = options.setTimeoutFn ?? setTimeout;
  const clearTimeoutForWorker = options.clearTimeoutFn ?? clearTimeout;
  let started = false;
  let nextSlotTimer: TimeoutHandle | undefined;
  let maintenanceTimer: TimeoutHandle | undefined;
  let startupRecoveryTimer: TimeoutHandle | undefined;
  let retryTimer: TimeoutHandle | undefined;
  let retryWakeAtMs: number | undefined;
  let processing: Promise<void> | undefined;

  const processDueReminders = async (): Promise<void> => {
    return processSchedule(toDoDueReminderScheduleAt(now()), { enqueue: true });
  };

  const processSchedule = async (
    schedule: ToDoDueReminderSchedule,
    behavior: { enqueue: boolean },
  ): Promise<void> => {
    if (processing) {
      return processing;
    }

    processing = processReminderSchedule(schedule, behavior);
    try {
      await processing;
    } finally {
      processing = undefined;
    }
  };

  async function processReminderSchedule(
    schedule: ToDoDueReminderSchedule,
    behavior: { enqueue: boolean },
  ): Promise<void> {
    try {
      for (const reminderKind of schedule.reminderKinds) {
        if (behavior.enqueue) {
          await options.toDoDueReminderStore.enqueueDueReminders(schedule.dueDate, reminderKind);
        }

        while (true) {
          const deliveries = await options.toDoDueReminderStore.claimDueDeliveries(
            schedule.dueDate,
            reminderKind,
            reminderDeliveryBatchSize,
          );

          for (const delivery of deliveries) {
            await sendDelivery(delivery);
          }

          if (deliveries.length < reminderDeliveryBatchSize) {
            break;
          }
        }
      }
    } catch (error) {
      options.logger.warn('To-do due reminder check failed.', { error: safeErrorMessage(error) });
    } finally {
      if (started) {
        try {
          await refreshNextPendingRetry();
        } catch (error) {
          options.logger.warn('To-do due reminder retry scheduling failed.', { error: safeErrorMessage(error) });
        }
      }
    }
  }

  async function sendDelivery(delivery: ToDoDueReminderDelivery): Promise<void> {
    try {
      const status = await options.notificationService.sendToDoDueReminderPush({
        itemId: delivery.todoItemId,
        itemName: delivery.itemName,
        dueDate: delivery.dueDate,
        reminderKind: delivery.reminderKind,
        recipientUserId: delivery.recipientUserId,
      });

      await persistDeliveryStatus(delivery, status);
      options.logger.info('To-do due reminder processed.', {
        todoItemId: delivery.todoItemId,
        recipientUserId: delivery.recipientUserId,
        reminderKind: delivery.reminderKind,
        attempted: status.attempted,
        skipped: status.skipped,
        sentNotificationCount: status.sentNotificationCount,
        reason: status.reason,
      });
    } catch (error) {
      await retryOrFailDelivery(delivery, safeErrorMessage(error));
    }
  }

  async function persistDeliveryStatus(delivery: ToDoDueReminderDelivery, status: EventPushStatus): Promise<void> {
    if ((status.sentNotificationCount ?? 0) > 0) {
      await options.toDoDueReminderStore.markSent(delivery.id);
      return;
    }

    if (status.skipped || !status.attempted) {
      await options.toDoDueReminderStore.markSkipped(
        delivery.id,
        status.reason ?? 'No eligible recipient device accepted this to-do reminder.',
      );
      return;
    }

    await retryOrFailDelivery(
      delivery,
      status.reason ?? 'APNs did not accept this to-do reminder for any recipient device.',
    );
  }

  async function retryOrFailDelivery(delivery: ToDoDueReminderDelivery, reason: string): Promise<void> {
    if (delivery.attemptCount >= 5) {
      await options.toDoDueReminderStore.markPermanentFailure(delivery.id, `retry limit reached: ${reason}`);
      return;
    }

    const retryAt = nextRetryAt(delivery.attemptCount, now);
    await options.toDoDueReminderStore.markRetryableFailure(
      delivery.id,
      reason,
      retryAt,
    );
    scheduleRetry({
      dueDate: delivery.dueDate,
      reminderKind: delivery.reminderKind,
      nextAttemptAt: retryAt,
    });
  }

  async function runMaintenanceSweep(): Promise<void> {
    try {
      const schedule = toDoDueReminderScheduleAt(now());
      await options.toDoDueReminderStore.recoverStaleClaims();
      await options.toDoDueReminderStore.discardExpiredAndIneligibleDeliveries(schedule.dueDate);
      await refreshNextPendingRetry(schedule.dueDate);
    } catch (error) {
      options.logger.warn('To-do due reminder maintenance failed.', { error: safeErrorMessage(error) });
    }
  }

  async function refreshNextPendingRetry(currentDueDate = toDoDueReminderScheduleAt(now()).dueDate): Promise<void> {
    if (!started) {
      return;
    }

    const delivery = await options.toDoDueReminderStore.findNextPendingDelivery(currentDueDate);
    if (!delivery) {
      clearRetryTimer();
      return;
    }

    scheduleRetry(delivery);
  }

  function scheduleNextSlot(): void {
    if (!started) {
      return;
    }

    const slot = nextToDoDueReminderSlotAt(now());
    nextSlotTimer = setTimeoutForWorker(() => {
      nextSlotTimer = undefined;
      scheduleNextSlot();
      void processSchedule({
        dueDate: slot.dueDate,
        reminderKinds: [slot.reminderKind],
      }, { enqueue: true });
    }, Math.max(0, slot.scheduledAt.getTime() - now().getTime()));
    nextSlotTimer.unref?.();
  }

  function scheduleMaintenanceSweep(): void {
    if (!started) {
      return;
    }

    maintenanceTimer = setTimeoutForWorker(() => {
      maintenanceTimer = undefined;
      void runMaintenanceSweep().finally(() => {
        scheduleMaintenanceSweep();
      });
    }, maintenanceIntervalMs);
    maintenanceTimer.unref?.();
  }

  function scheduleStartupRecovery(): void {
    if (!started) {
      return;
    }

    startupRecoveryTimer = setTimeoutForWorker(() => {
      startupRecoveryTimer = undefined;
      void runMaintenanceSweep();
    }, startupRecoveryDelayMs);
    startupRecoveryTimer.unref?.();
  }

  function scheduleRetry(delivery: ToDoDueReminderPendingDelivery): void {
    if (!started || (retryWakeAtMs !== undefined && retryWakeAtMs <= delivery.nextAttemptAt.getTime())) {
      return;
    }

    clearRetryTimer();
    retryWakeAtMs = delivery.nextAttemptAt.getTime();
    retryTimer = setTimeoutForWorker(() => {
      retryTimer = undefined;
      retryWakeAtMs = undefined;
      void processSchedule({
        dueDate: delivery.dueDate,
        reminderKinds: [delivery.reminderKind],
      }, { enqueue: false });
    }, Math.max(0, delivery.nextAttemptAt.getTime() - now().getTime()));
    retryTimer.unref?.();
  }

  function clearRetryTimer(): void {
    retryWakeAtMs = undefined;
    if (retryTimer) {
      clearTimeoutForWorker(retryTimer);
      retryTimer = undefined;
    }
  }

  function clearTimer(timer: TimeoutHandle | undefined): void {
    if (timer) {
      clearTimeoutForWorker(timer);
    }
  }

  return {
    processDueReminders,
    start() {
      if (started) {
        return;
      }

      started = true;
      options.logger.info('To-do due reminders enabled.', { timeZone: toDoDueReminderTimeZone });
      scheduleNextSlot();
      scheduleMaintenanceSweep();
      scheduleStartupRecovery();
      void (async () => {
        await runMaintenanceSweep();
        await processDueReminders();
      })();
    },
    stop() {
      started = false;
      clearTimer(nextSlotTimer);
      nextSlotTimer = undefined;
      clearTimer(maintenanceTimer);
      maintenanceTimer = undefined;
      clearTimer(startupRecoveryTimer);
      startupRecoveryTimer = undefined;
      clearRetryTimer();
    },
  };
}

export function toDoDueReminderScheduleAt(date: Date): ToDoDueReminderSchedule {
  const local = mountainTimeParts(date);

  return {
    dueDate: local.date,
    reminderKinds: local.minutesSinceMidnight >= eveningReminderMinute
      ? ['evening']
      : local.minutesSinceMidnight >= morningReminderMinute
        ? ['morning']
        : [],
  };
}

export function nextToDoDueReminderSlotAt(date: Date): ToDoDueReminderSlot {
  const local = mountainTimeParts(date);
  const target = local.minutesSinceMidnight < morningReminderMinute
    ? { calendarDate: local, reminderKind: 'morning' as const, minute: morningReminderMinute }
    : local.minutesSinceMidnight < eveningReminderMinute
      ? { calendarDate: local, reminderKind: 'evening' as const, minute: eveningReminderMinute }
      : { calendarDate: nextCalendarDate(local), reminderKind: 'morning' as const, minute: morningReminderMinute };

  const hour = Math.floor(target.minute / 60);
  const minute = target.minute % 60;
  const scheduledAt = mountainTimeDate(target.calendarDate, hour, minute);

  return {
    dueDate: target.calendarDate.date,
    reminderKind: target.reminderKind,
    scheduledAt,
  };
}

function nextRetryAt(attemptCount: number, now: () => Date): Date {
  return new Date(now().getTime() + Math.min(5 * 60, 30 * Math.max(1, attemptCount)) * 1_000);
}

type MountainTimeParts = {
  year: number;
  month: number;
  day: number;
  date: string;
  minutesSinceMidnight: number;
};

function mountainTimeParts(date: Date): MountainTimeParts {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: toDoDueReminderTimeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(date);
  const value = (type: Intl.DateTimeFormatPartTypes): string | undefined => (
    parts.find((part) => part.type === type)?.value
  );
  const year = value('year');
  const month = value('month');
  const day = value('day');
  const hour = Number(value('hour'));
  const minute = Number(value('minute'));

  if (!year || !month || !day || !Number.isInteger(hour) || !Number.isInteger(minute)) {
    throw new Error('Unable to determine the current America/Denver calendar time.');
  }

  return {
    year: Number(year),
    month: Number(month),
    day: Number(day),
    date: `${year}-${month}-${day}`,
    minutesSinceMidnight: hour * 60 + minute,
  };
}

function nextCalendarDate(parts: MountainTimeParts): MountainTimeParts {
  const next = new Date(Date.UTC(parts.year, parts.month - 1, parts.day + 1));
  const year = next.getUTCFullYear();
  const month = next.getUTCMonth() + 1;
  const day = next.getUTCDate();

  return {
    year,
    month,
    day,
    date: `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`,
    minutesSinceMidnight: 0,
  };
}

function mountainTimeDate(parts: MountainTimeParts, hour: number, minute: number): Date {
  const desiredWallClockMs = Date.UTC(parts.year, parts.month - 1, parts.day, hour, minute);
  let timestamp = desiredWallClockMs;

  for (let attempt = 0; attempt < 3; attempt += 1) {
    const actual = mountainTimeParts(new Date(timestamp));
    const actualWallClockMs = Date.UTC(
      actual.year,
      actual.month - 1,
      actual.day,
      Math.floor(actual.minutesSinceMidnight / 60),
      actual.minutesSinceMidnight % 60,
    );
    const adjustment = desiredWallClockMs - actualWallClockMs;

    if (adjustment === 0) {
      return new Date(timestamp);
    }

    timestamp += adjustment;
  }

  throw new Error('Unable to determine the next America/Denver reminder slot.');
}
