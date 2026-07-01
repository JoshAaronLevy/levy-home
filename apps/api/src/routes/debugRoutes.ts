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
import { testPushMessage } from '../services/notifications/notificationService.js';
import { validateTestPushBody } from '../validation/notificationValidation.js';

export type DebugRouteDependencies = {
  activityEventService: ActivityEventService;
  activityStore: RecentActivityStore;
  config: AppConfig;
  homeAssistant: HomeAssistantFacade;
  krogerProductDiagnosticRunner: KrogerProductDiagnosticRunner;
  notificationService: NotificationService;
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

  return router;
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
