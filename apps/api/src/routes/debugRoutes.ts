import { Router } from 'express';

import type { PushSender } from '../apnsService.js';
import type { AppConfig } from '../config.js';
import type { KrogerProductDiagnosticRunner } from '../krogerClient.js';
import type { HomeAssistantFacade } from '../homeAssistantClient.js';
import { asyncHandler } from '../http/asyncHandler.js';
import { HTTPError } from '../http/errors.js';
import { requireHaWebhookSecret } from '../http/middleware/requireHaWebhookSecret.js';
import { validateTestPushBody } from '../validation.js';
import {
  sendPushToRegisteredDevices,
  testPushMessage,
} from './pushDelivery.js';
import type {
  NotificationPreferenceState,
  RegisteredDeviceState,
} from './routeState.js';

export type DebugRouteDependencies = Pick<RegisteredDeviceState, 'registeredDevicesById'> &
  NotificationPreferenceState & {
    config: AppConfig;
    homeAssistant: HomeAssistantFacade;
    krogerProductDiagnosticRunner: KrogerProductDiagnosticRunner;
    pushSender: PushSender;
  };

export function createDebugRoutes(deps: DebugRouteDependencies): Router {
  const router = Router();

  router.post(
    '/api/debug/send-test-push',
    asyncHandler(async (req, res) => {
      const payload = validateTestPushBody(req.body);
      const summary = await sendPushToRegisteredDevices({
        devices: Array.from(deps.registeredDevicesById.values()),
        preferencesByDeviceKey: deps.preferencesByDeviceKey,
        pushSender: deps.pushSender,
        payload,
        preferenceCategory: undefined,
      });

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
