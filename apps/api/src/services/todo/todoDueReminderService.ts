import type { EventPushStatus } from '../../contracts.js';
import { safeErrorMessage, type Logger } from '../../observability/logger.js';
import type {
  ToDoDueReminderDelivery,
  ToDoDueReminderKind,
  ToDoDueReminderStore,
} from '../../repositories/todoDueReminderRepository.js';
import type { NotificationService } from '../notifications/notificationService.js';

export const toDoDueReminderTimeZone = 'America/Denver';
const morningReminderMinute = 8 * 60;
const eveningReminderMinute = 18 * 60;
const pollIntervalMs = 30_000;

export type ToDoDueReminderService = {
  processDueReminders: () => Promise<void>;
  start: () => void;
  stop: () => void;
};

export type ToDoDueReminderSchedule = {
  dueDate: string;
  reminderKinds: ToDoDueReminderKind[];
};

export function createToDoDueReminderService(options: {
  logger: Logger;
  notificationService: Pick<NotificationService, 'sendToDoDueReminderPush'>;
  now?: () => Date;
  toDoDueReminderStore: ToDoDueReminderStore;
}): ToDoDueReminderService {
  const now = options.now ?? (() => new Date());
  let poller: NodeJS.Timeout | undefined;
  let processing: Promise<void> | undefined;

  const processDueReminders = async (): Promise<void> => {
    if (processing) {
      return processing;
    }

    processing = processCurrentDueReminders();

    try {
      await processing;
    } finally {
      processing = undefined;
    }
  };

  async function processCurrentDueReminders(): Promise<void> {
    const schedule = toDoDueReminderScheduleAt(now());

    try {
      await options.toDoDueReminderStore.recoverStaleClaims();
      await options.toDoDueReminderStore.discardExpiredAndIneligibleDeliveries(schedule.dueDate);

      for (const reminderKind of schedule.reminderKinds) {
        await options.toDoDueReminderStore.enqueueDueReminders(schedule.dueDate, reminderKind);
        const deliveries = await options.toDoDueReminderStore.claimDueDeliveries(
          schedule.dueDate,
          reminderKind,
          50,
        );

        for (const delivery of deliveries) {
          await sendDelivery(delivery);
        }
      }
    } catch (error) {
      options.logger.warn('To-do due reminder check failed.', { error: safeErrorMessage(error) });
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

    await options.toDoDueReminderStore.markRetryableFailure(
      delivery.id,
      reason,
      nextRetryAt(delivery.attemptCount, now),
    );
  }

  return {
    processDueReminders,
    start() {
      if (poller) {
        return;
      }

      options.logger.info('To-do due reminders enabled.', { timeZone: toDoDueReminderTimeZone });
      void processDueReminders();
      poller = setInterval(() => {
        void processDueReminders();
      }, pollIntervalMs);
      poller.unref();
    },
    stop() {
      if (poller) {
        clearInterval(poller);
      }
      poller = undefined;
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

function nextRetryAt(attemptCount: number, now: () => Date): Date {
  return new Date(now().getTime() + Math.min(5 * 60, 30 * Math.max(1, attemptCount)) * 1_000);
}

function mountainTimeParts(date: Date): { date: string; minutesSinceMidnight: number } {
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
    date: `${year}-${month}-${day}`,
    minutesSinceMidnight: hour * 60 + minute,
  };
}
