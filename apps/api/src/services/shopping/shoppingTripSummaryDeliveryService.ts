import { APNsConfigurationError, type PushSender } from '../../integrations/apple/apnsPushSender.js';
import type { ShoppingTripSummaryStore } from '../../repositories/shoppingTripSummaryRepository.js';
import type { Logger } from '../../observability/logger.js';
import { logger as defaultLogger, safeErrorMessage } from '../../observability/logger.js';
import type { DeviceRegistry } from '../notifications/deviceRegistry.js';
import type { NotificationPreferenceStore } from '../notifications/notificationPreferenceStore.js';

const pollIntervalMs = 5_000;
const permanentAPNsReasons = new Set(['Unregistered', 'BadDeviceToken', 'DeviceTokenNotForTopic']);

export type ShoppingTripSummaryDeliveryService = {
  start: () => void;
  stop: () => void;
  processPending: () => Promise<void>;
};

export function createShoppingTripSummaryDeliveryService(options: {
  logger?: Logger;
  now?: () => Date;
  pushSender: PushSender;
  deviceRegistry: Pick<DeviceRegistry, 'getDevice'> & Partial<Pick<DeviceRegistry, 'invalidateDevice'>>;
  notificationPreferenceStore: Pick<NotificationPreferenceStore, 'isNotificationEnabled'>;
  shoppingTripSummaryStore: ShoppingTripSummaryStore;
}): ShoppingTripSummaryDeliveryService {
  const auditLogger = options.logger ?? defaultLogger;
  const now = options.now ?? (() => new Date());
  let poller: NodeJS.Timeout | undefined;
  let processing: Promise<void> | undefined;

  const processPending = async (): Promise<void> => {
    if (processing) return processing;
    processing = processDeliveries();
    try {
      await processing;
    } finally {
      processing = undefined;
    }
  };

  async function processDeliveries(): Promise<void> {
    await options.shoppingTripSummaryStore.recoverStaleClaims();
    const deliveries = await options.shoppingTripSummaryStore.claimDueDeliveries(20);

    for (const delivery of deliveries) {
      const device = await options.deviceRegistry.getDevice(delivery.pushDeviceId);
      if (!device || device.provider !== 'apns') {
        await options.shoppingTripSummaryStore.markSkipped(delivery.id, 'recipient device is no longer an APNs registration');
        continue;
      }

      if (!await options.notificationPreferenceStore.isNotificationEnabled(device, 'shopping_list')) {
        await options.shoppingTripSummaryStore.markSkipped(delivery.id, 'shopping_list notifications are disabled for this recipient device');
        continue;
      }

      try {
        const result = await options.pushSender.send({
          device,
          title: delivery.title,
          body: delivery.body,
          collapseId: `shopping-trip-${delivery.tripId}-${delivery.recipient.toLowerCase()}`,
          expiration: Math.floor(now().getTime() / 1_000) + 60 * 60,
          data: {
            category: 'shopping_list',
            listType: 'shopping',
            action: 'trip_ended',
            tripId: delivery.tripId,
            recipient: delivery.recipient,
          },
        });

        if (result.success) {
          await options.shoppingTripSummaryStore.markSent(delivery.id, result.apnsId);
          auditLogger.info('Shopping trip summary delivery sent.', summaryAuditDetails(delivery));
          continue;
        }

        const reason = result.reason ?? `APNs status ${result.statusCode ?? 'unknown'}`;
        if (result.isInvalidToken || permanentAPNsReasons.has(reason)) {
          await options.deviceRegistry.invalidateDevice?.(device.id);
          await options.shoppingTripSummaryStore.markPermanentFailure(delivery.id, reason);
        } else if (delivery.attemptCount >= 5) {
          await options.shoppingTripSummaryStore.markPermanentFailure(delivery.id, `retry limit reached: ${reason}`);
        } else {
          await options.shoppingTripSummaryStore.markRetryableFailure(delivery.id, reason, nextRetryAt(delivery.attemptCount, now));
        }
      } catch (error) {
        const reason = error instanceof APNsConfigurationError ? error.message : safeErrorMessage(error);
        if (delivery.attemptCount >= 5) {
          await options.shoppingTripSummaryStore.markPermanentFailure(delivery.id, `retry limit reached: ${reason}`);
        } else {
          await options.shoppingTripSummaryStore.markRetryableFailure(
            delivery.id,
            reason,
            nextRetryAt(delivery.attemptCount, now),
            true,
          );
        }
      }
    }
  }

  return {
    start() {
      if (poller) return;
      void processPending().catch((error) => auditLogger.warn('Initial shopping trip summary recovery failed.', { error: safeErrorMessage(error) }));
      poller = setInterval(() => {
        void processPending().catch((error) => auditLogger.warn('Shopping trip summary poll failed.', { error: safeErrorMessage(error) }));
      }, pollIntervalMs);
      poller.unref();
    },
    stop() {
      if (poller) clearInterval(poller);
      poller = undefined;
    },
    processPending,
  };
}

function nextRetryAt(attemptCount: number, now: () => Date): Date {
  return new Date(now().getTime() + Math.min(5 * 60, 30 * Math.max(1, attemptCount)) * 1_000);
}

function summaryAuditDetails(delivery: { id: string; tripId: string; pushDeviceId: string; recipient: string; attemptCount: number }): Record<string, unknown> {
  return {
    deliveryId: delivery.id,
    tripId: delivery.tripId,
    deviceId: delivery.pushDeviceId,
    recipient: delivery.recipient,
    attemptCount: delivery.attemptCount,
  };
}
