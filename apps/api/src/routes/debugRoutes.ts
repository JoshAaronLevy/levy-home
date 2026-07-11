import { Router } from 'express';

import type { AppConfig } from '../config.js';
import { buildEventDedupeKey, type EventPushStatus, type HomeAssistantEventPayload } from '../contracts.js';
import type { HomeAssistantFacade } from '../integrations/homeAssistant/facade.js';
import type { KrogerProductDiagnosticRunner } from '../integrations/kroger/productDiagnostics.js';
import { asyncHandler } from '../http/asyncHandler.js';
import { HTTPError } from '../http/errors.js';
import { requireHaWebhookSecret } from '../http/middleware/requireHaWebhookSecret.js';
import type { RecentActivityStore } from '../activityStore.js';
import type { ActivityEventService } from '../services/activity/activityEventService.js';
import type { NotificationService } from '../services/notifications/notificationService.js';
import type { ShoppingTripStore } from '../repositories/shoppingTripRepository.js';
import type { ShoppingLiveActivityDeliveryService } from '../services/shopping/shoppingLiveActivityDeliveryService.js';
import type { ShoppingLiveActivityStore } from '../repositories/shoppingLiveActivityRepository.js';
import { testPushMessage } from '../services/notifications/notificationService.js';
import { validateTestPushBody } from '../validation/notificationValidation.js';

export type DebugRouteDependencies = {
  activityEventService: ActivityEventService;
  activityStore: RecentActivityStore;
  config: AppConfig;
  homeAssistant: HomeAssistantFacade;
  krogerProductDiagnosticRunner: KrogerProductDiagnosticRunner;
  notificationService: NotificationService;
  shoppingLiveActivityDeliveryService?: ShoppingLiveActivityDeliveryService;
  shoppingLiveActivityStore?: Pick<ShoppingLiveActivityStore, 'getDiagnostics'>;
  shoppingTripStore?: Pick<ShoppingTripStore, 'fetchActiveTrip' | 'fetchTrip'>;
};

export function createDebugRoutes(deps: DebugRouteDependencies): Router {
  const router = Router();

  router.post(
    '/api/debug/send-test-push',
    asyncHandler(async (req, res) => {
      const payload = validateTestPushBody(req.body);
      const summary = await deps.notificationService.sendTestPush(payload);

      if (summary.configurationError) {
        throw new HTTPError(503, summary.configurationError, 'apns_credentials_not_configured');
      }

      res.json({
        ok: true,
        message: testPushMessage(summary),
        provider: 'apns',
        registeredDeviceCount: summary.registeredDeviceCount,
        eligibleDeviceCount: summary.eligibleDeviceCount,
        sentNotificationCount: summary.sentNotificationCount,
        sentTicketCount: summary.sentNotificationCount,
        failedNotificationCount: summary.failedNotificationCount,
        invalidTokenCount: summary.invalidTokenCount,
        skippedDeviceCount: summary.skippedDeviceCount,
        results: summary.results,
      });
    }),
  );

  router.post(
    '/api/debug/notification-pipeline-test',
    asyncHandler(async (_req, res) => {
      const event = await deps.activityEventService.createStoredEvent(notificationPipelineTestPayload());
      deps.activityStore.add(event);
      const push = event.push;

      res.status(201).json({
        ok: true,
        message: notificationPipelineTestMessage(push),
        provider: 'apns',
        event,
        dedupeKey: buildEventDedupeKey(event),
        storedEventCount: deps.activityStore.count(),
        sentNotificationCount: push?.sentNotificationCount ?? 0,
        failedNotificationCount: push?.failedNotificationCount ?? 0,
        invalidTokenCount: push?.invalidTokenCount ?? 0,
        skipped: push?.skipped ?? true,
        reason: push?.reason,
      });
    }),
  );

  router.get(
    '/api/debug/home-assistant/phone-entities',
    requireHaWebhookSecret(deps.config),
    asyncHandler(async (req, res) => {
      const candidates = await deps.homeAssistant.discoverPhoneEntities(
        readPhoneDiscoveryKeywords(req.query.keywords),
      );

      res.json({
        ok: true,
        candidates,
        candidateCount: candidates.length,
        generatedAt: new Date().toISOString(),
      });
    }),
  );

  router.get('/api/debug/kroger/products', asyncHandler(async (req, res) => {
    const term = typeof req.query.term === 'string' ? req.query.term : undefined;
    const response = await deps.krogerProductDiagnosticRunner(term);

    res.json(response);
  }));

  router.get('/api/debug/shopping-live-activity/diagnostics', asyncHandler(async (_req, res) => {
    const trip = await deps.shoppingTripStore?.fetchActiveTrip() ?? null;
    const diagnostics = deps.shoppingLiveActivityStore
      ? await deps.shoppingLiveActivityStore.getDiagnostics()
      : null;
    res.json({
      ok: true,
      activeTrip: trip,
      ...(diagnostics ?? {
        activePushToStartRegistrationCount: 0,
        activeUpdateRegistrationCount: 0,
        latestDelivery: null,
      }),
      generatedAt: new Date().toISOString(),
    });
  }));

  for (const event of ['start', 'update', 'end'] as const) {
    router.post(`/api/debug/shopping-live-activity/${event}`, asyncHandler(async (req, res) => {
      const trip = await debugTripForEvent(deps, event, req.body);
      const excludeResident = readOptionalDebugResident(req.body?.excludeResident);
      const deliveries = await requireShoppingDeliveryService(deps).enqueueEvent({
        event,
        trip,
        ...(excludeResident ? { excludeResident } : {}),
      });

      res.json({
        ok: true,
        trip,
        queuedDeliveryCount: deliveries.length,
        deliveryIds: deliveries.map((delivery) => delivery.id),
        generatedAt: new Date().toISOString(),
      });
    }));
  }

  return router;
}

async function debugTripForEvent(
  deps: DebugRouteDependencies,
  event: 'start' | 'update' | 'end',
  body: unknown,
) {
  const store = deps.shoppingTripStore;

  if (!store) {
    throw new HTTPError(503, 'Shopping trip persistence is not configured.', 'shopping_trip_not_configured');
  }

  const tripId = typeof body === 'object' && body !== null && typeof (body as { tripId?: unknown }).tripId === 'string'
    ? (body as { tripId: string }).tripId.trim()
    : undefined;
  const trip = tripId ? await store.fetchTrip(tripId) : await store.fetchActiveTrip();

  if (!trip) {
    throw new HTTPError(404, 'No matching shopping trip was found for the developer delivery.', 'shopping_trip_not_found');
  }

  if (event === 'end' && trip.status !== 'completed') {
    throw new HTTPError(409, 'End delivery requires a completed shopping trip.', 'shopping_trip_not_completed');
  }

  if (event !== 'end' && trip.status !== 'active') {
    throw new HTTPError(409, 'Start and update deliveries require an active shopping trip.', 'shopping_trip_not_active');
  }

  return trip;
}

function requireShoppingDeliveryService(
  deps: DebugRouteDependencies,
): ShoppingLiveActivityDeliveryService {
  if (!deps.shoppingLiveActivityDeliveryService) {
    throw new HTTPError(503, 'Shopping Live Activity delivery is not configured.', 'shopping_live_activity_not_configured');
  }

  return deps.shoppingLiveActivityDeliveryService;
}

function readOptionalDebugResident(value: unknown): 'Josh' | 'Mallory' | undefined {
  if (value === undefined || value === null || value === '') {
    return undefined;
  }

  if (value === 'Josh' || value === 'Mallory') {
    return value;
  }

  throw new HTTPError(400, 'excludeResident must be Josh or Mallory.', 'invalid_shopping_live_activity_debug_request');
}

function notificationPipelineTestPayload(): HomeAssistantEventPayload {
  return {
    type: 'garage_still_open_at_10pm',
    category: 'garage',
    severity: 'high',
    entityId: 'debug.notification_pipeline_test',
    source: 'home_assistant_debug_pipeline_test',
    occurredAt: new Date().toISOString(),
    title: 'Levy Home notification test',
    message: 'This push came through the Levy Home event pipeline.',
    metadata: {
      isDebugNotificationPipelineTest: true,
      trigger: 'preferences_developer_test_notification',
    },
  };
}

function notificationPipelineTestMessage(push: EventPushStatus | undefined): string {
  if (!push) {
    return 'Created a Home Assistant-style test event, but no push category was configured.';
  }

  if (push.skipped) {
    return `Created a Home Assistant-style test event. Push skipped: ${push.reason ?? 'No reason provided.'}`;
  }

  if ((push.sentNotificationCount ?? 0) > 0) {
    return `Created a Home Assistant-style test event and sent ${push.sentNotificationCount} APNs notification(s).`;
  }

  return 'Created a Home Assistant-style test event, but no APNs notification was sent.';
}

function readPhoneDiscoveryKeywords(value: unknown): string[] | undefined {
  if (typeof value !== 'string') {
    return undefined;
  }

  const keywords = value
    .split(',')
    .map((keyword) => keyword.trim())
    .filter(Boolean);

  return keywords.length > 0 ? keywords : undefined;
}
