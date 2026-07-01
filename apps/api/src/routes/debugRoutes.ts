import { Router } from 'express';

import type { AppConfig } from '../config.js';
import type { HomeAssistantFacade } from '../integrations/homeAssistant/facade.js';
import type { KrogerProductDiagnosticRunner } from '../integrations/kroger/productDiagnostics.js';
import { asyncHandler } from '../http/asyncHandler.js';
import { HTTPError } from '../http/errors.js';
import { requireHaWebhookSecret } from '../http/middleware/requireHaWebhookSecret.js';
import type { NotificationService } from '../services/notifications/notificationService.js';
import { testPushMessage } from '../services/notifications/notificationService.js';
import { validateTestPushBody } from '../validation.js';

export type DebugRouteDependencies = {
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
