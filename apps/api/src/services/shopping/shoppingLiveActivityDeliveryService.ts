import crypto from 'node:crypto';

import type {
  ShoppingLiveActivityDelivery,
  ShoppingLiveActivityDeliveryEvent,
  ShoppingLiveActivityPayload,
  ShoppingLiveActivityRegistration,
  ShoppingLiveActivityRegistrationRequest,
  ShoppingTripSnapshot,
} from '../../contracts.js';
import {
  APNsConfigurationError,
  type ShoppingLiveActivityPushSender,
} from '../../integrations/apple/apnsPushSender.js';
import type {
  ShoppingLiveActivityStore,
  StoredShoppingLiveActivityRegistration,
} from '../../repositories/shoppingLiveActivityRepository.js';
import type { ShoppingTripStore } from '../../repositories/shoppingTripRepository.js';
import type { Logger } from '../../observability/logger.js';
import { logger as defaultLogger, safeErrorMessage } from '../../observability/logger.js';

const permanentAPNsReasons = new Set(['Unregistered', 'BadDeviceToken', 'DeviceTokenNotForTopic']);
const deliveryPollIntervalMs = 5_000;

export type ShoppingLiveActivityDeliveryService = {
  start: () => void;
  stop: () => void;
  register: (request: ShoppingLiveActivityRegistrationRequest) => Promise<ShoppingLiveActivityRegistration>;
  enqueueEvent: (options: {
    event: ShoppingLiveActivityDeliveryEvent;
    trip: ShoppingTripSnapshot;
    excludeResident?: string;
  }) => Promise<ShoppingLiveActivityDelivery[]>;
  processPending: () => Promise<void>;
};

export function createShoppingLiveActivityDeliveryService(options: {
  logger?: Logger;
  now?: () => Date;
  pushSender: ShoppingLiveActivityPushSender;
  shoppingLiveActivityStore: ShoppingLiveActivityStore;
  shoppingTripStore: Pick<ShoppingTripStore, 'fetchTrip'>;
}): ShoppingLiveActivityDeliveryService {
  const auditLogger = options.logger ?? defaultLogger;
  const now = options.now ?? (() => new Date());
  let poller: NodeJS.Timeout | undefined;
  let processing: Promise<void> | undefined;

  const processPending = async (): Promise<void> => {
    if (processing) {
      return processing;
    }

    processing = processPendingDeliveries();

    try {
      await processing;
    } finally {
      processing = undefined;
    }
  };

  async function processPendingDeliveries(): Promise<void> {
    await options.shoppingLiveActivityStore.recoverStaleClaims();
    const deliveries = await options.shoppingLiveActivityStore.claimDueDeliveries(20);

    for (const delivery of deliveries) {
      try {
        const result = await options.pushSender.send({
          registrationId: delivery.registration.id,
          token: delivery.registration.token,
          environment: delivery.registration.environment,
          payload: delivery.payload,
          priority: delivery.eventType === 'update' ? 5 : 10,
          expiration: expirationFor(delivery.eventType, now()),
        });

        if (result.success) {
          await options.shoppingLiveActivityStore.markDeliverySent(delivery.id, result.apnsId);
          auditLogger.info('Shopping Live Activity delivery sent.', deliveryAuditDetails(delivery, result.reason));
          continue;
        }

        const reason = result.reason ?? `APNs status ${result.statusCode ?? 'unknown'}`;

        if (result.isInvalidToken || permanentAPNsReasons.has(reason)) {
          await options.shoppingLiveActivityStore.invalidateRegistration(delivery.registration.id);
          await options.shoppingLiveActivityStore.markDeliveryPermanentFailure(delivery.id, reason);
          auditLogger.warn('Shopping Live Activity registration invalidated after APNs rejection.', deliveryAuditDetails(delivery, reason));
          continue;
        }

        await options.shoppingLiveActivityStore.markDeliveryRetryableFailure(
          delivery.id,
          reason,
          nextRetryAt(delivery.attemptCount, now),
        );
        auditLogger.warn('Shopping Live Activity delivery will retry after APNs rejection.', deliveryAuditDetails(delivery, reason));
      } catch (error) {
        const reason = error instanceof APNsConfigurationError
          ? error.message
          : safeErrorMessage(error);
        await options.shoppingLiveActivityStore.markDeliveryAmbiguous(
          delivery.id,
          reason,
          nextRetryAt(delivery.attemptCount, now),
        );
        auditLogger.warn('Shopping Live Activity delivery response was ambiguous; retaining delivery for retry.', deliveryAuditDetails(delivery, reason));
      }
    }
  }

  return {
    start() {
      if (poller) {
        return;
      }

      void processPending().catch((error) => {
        auditLogger.warn('Initial Shopping Live Activity delivery recovery failed.', { error: safeErrorMessage(error) });
      });
      poller = setInterval(() => {
        void processPending().catch((error) => {
          auditLogger.warn('Shopping Live Activity delivery poll failed.', { error: safeErrorMessage(error) });
        });
      }, deliveryPollIntervalMs);
      poller.unref();
    },
    stop() {
      if (poller) {
        clearInterval(poller);
        poller = undefined;
      }
    },
    async register(request) {
      const registration = await options.shoppingLiveActivityStore.register(request);

      if (request.tokenType === 'activity_update' && request.tripId) {
        // This token can only arrive after an Activity exists on the device. It
        // is our positive reconciliation signal for a start whose APNs response
        // was lost, so do not ever resend that ambiguous start.
        await options.shoppingLiveActivityStore.reconcileAmbiguousStartDeliveries({
          tripId: request.tripId,
          pushDeviceId: request.pushDeviceId,
        });
        const trip = await options.shoppingTripStore.fetchTrip(request.tripId);

        if (trip) {
          await enqueueForRegistrations({
            event: trip.status === 'completed' ? 'end' : 'update',
            trip,
            registrations: [registration],
          });
          void processPending().catch((error) => {
            auditLogger.warn('Late Shopping Live Activity update token catch-up failed.', { error: safeErrorMessage(error) });
          });
        }
      }

      return registration;
    },
    async enqueueEvent({ event, trip, excludeResident }) {
      if (event === 'update') {
        await options.shoppingLiveActivityStore.supersedePendingUpdates(trip.id, trip.version);
      }
      const registrations = await options.shoppingLiveActivityStore.findActiveRegistrations({
        tokenType: event === 'start' ? 'push_to_start' : 'activity_update',
        ...(event === 'start' ? {} : { tripId: trip.id }),
        ...(excludeResident ? { excludeResident } : {}),
      });
      const deliveries = await enqueueForRegistrations({ event, trip, registrations });
      void processPending().catch((error) => {
        auditLogger.warn('Shopping Live Activity immediate delivery processing failed.', { error: safeErrorMessage(error) });
      });
      return deliveries;
    },
    processPending,
  };

  async function enqueueForRegistrations(optionsForQueue: {
    event: ShoppingLiveActivityDeliveryEvent;
    trip: ShoppingTripSnapshot;
    registrations: Array<ShoppingLiveActivityRegistration | StoredShoppingLiveActivityRegistration>;
  }): Promise<ShoppingLiveActivityDelivery[]> {
    const timestamp = optionsForQueue.event === 'update' && optionsForQueue.trip.activityUpdatedAtEpochSeconds > 0
      ? optionsForQueue.trip.activityUpdatedAtEpochSeconds
      : epochSeconds(now());
    const payload = buildShoppingLiveActivityPayload(optionsForQueue.event, optionsForQueue.trip, timestamp);

    return Promise.all(optionsForQueue.registrations.map((registration) => options.shoppingLiveActivityStore.enqueueDelivery({
      tripId: optionsForQueue.trip.id,
      registrationId: registration.id,
      eventType: optionsForQueue.event,
      stateVersion: optionsForQueue.trip.version,
      payload,
    })));
  }
}

export function buildShoppingLiveActivityPayload(
  event: ShoppingLiveActivityDeliveryEvent,
  trip: ShoppingTripSnapshot,
  timestamp: number,
): ShoppingLiveActivityPayload {
  const contentState = {
    status: trip.status,
    pickedUpCount: trip.pickedUpCount,
    remainingCount: trip.remainingCount,
    totalItemCount: trip.totalItemCount,
    estimatedTotalCents: trip.estimatedTotalCents,
    pricedPickedItemCount: trip.pricedPickedItemCount,
    unpricedPickedItemCount: trip.unpricedPickedItemCount,
    currencyCode: trip.currencyCode,
    stateVersion: trip.version,
    updatedAtEpochSeconds: timestamp,
  };

  if (event === 'start') {
    return {
      aps: {
        timestamp,
        event,
        'content-state': contentState,
        'attributes-type': 'ShoppingTripActivityAttributes',
        attributes: {
          tripID: trip.id,
          startedByName: trip.startedBy,
          startedAtEpochSeconds: epochSeconds(new Date(trip.startedAt)),
        },
        'input-push-token': 1,
        alert: {
          title: 'Shopping trip started',
          body: `${trip.startedBy} started a shopping trip.`,
        },
      },
    };
  }

  return {
    aps: {
      timestamp,
      event,
      'content-state': contentState,
      ...(event === 'end' ? { 'dismissal-date': timestamp + 15 * 60 } : {}),
    },
  };
}

function deliveryAuditDetails(
  delivery: { id: string; tripId: string; registrationId: string; eventType: string; stateVersion: number; attemptCount: number; registration?: { token: string; environment: string; resident: string } },
  reason?: string,
): Record<string, unknown> {
  return {
    deliveryId: delivery.id,
    tripId: delivery.tripId,
    registrationId: delivery.registrationId,
    event: delivery.eventType,
    stateVersion: delivery.stateVersion,
    attemptCount: delivery.attemptCount,
    ...(delivery.registration
      ? {
        registrationFingerprint: crypto
          .createHash('sha256')
          .update(delivery.registration.token)
          .digest('hex')
          .slice(0, 12),
        apnsEnvironment: delivery.registration.environment,
        resident: delivery.registration.resident,
      }
      : {}),
    ...(reason ? { reason } : {}),
  };
}

function epochSeconds(date: Date): number {
  return Math.floor(date.getTime() / 1000);
}

function expirationFor(event: ShoppingLiveActivityDeliveryEvent, date: Date): number {
  const nowSeconds = epochSeconds(date);
  return event === 'end' ? nowSeconds + 60 * 60 : nowSeconds + 8 * 60 * 60;
}

function nextRetryAt(attemptCount: number, now: () => Date): Date {
  const seconds = Math.min(5 * 60, 30 * Math.max(1, attemptCount));
  return new Date(now().getTime() + seconds * 1_000);
}
