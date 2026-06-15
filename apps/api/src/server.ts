import 'dotenv/config';

import cors from 'cors';
import express, { type NextFunction, type Request, type Response } from 'express';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';

import { normalizePhoneStateChangedEvent } from './activityNormalizer.js';
import { APNsConfigurationError, createAPNsPushSender, type PushSender } from './apnsService.js';
import type { AppConfig } from './config.js';
import { readConfig } from './config.js';
import {
  buildEventDedupeKey,
  GARAGE_NOTIFICATION_PREFERENCES,
  getEventDisplayMetadata,
  isNotificationPreferenceCategory,
  type APNsSendResult,
  type DevicePreferenceLocator,
  type EventPushStatus,
  type HomeAssistantEventPayload,
  type LevyHomeEvent,
  type NotificationPreference,
  type NotificationPreferenceCategory,
  type NotificationPreferenceUpdate,
  type PushSendSummary,
  type QuickActionId,
  type RegisteredDevice,
  type TestPushPayload,
} from './contracts.js';
import { createHomeAssistantActivityListener } from './homeAssistantActivityClient.js';
import { createHomeAssistantFacade } from './homeAssistantClient.js';
import { HomeService } from './homeService.js';
import { HTTPError } from './httpError.js';
import {
  validateHomeAssistantEventPayload,
  validateNotificationPreferencesBody,
  validateNotificationPreferencesQuery,
  validateQuickActionBody,
  validateRegisterDeviceBody,
  validateTestPushBody,
} from './validation.js';

export type CreateAppOptions = {
  config?: AppConfig;
  pushSender?: PushSender;
};

export function createApp(options: CreateAppOptions = {}): express.Express {
  const config = options.config ?? readConfig();
  const app = express();
  const recentEvents: LevyHomeEvent[] = [];
  const registeredDevicesById = new Map<string, RegisteredDevice>();
  const registeredDeviceIdsByLookupKey = new Map<string, string>();
  const preferencesByDeviceKey = new Map<string, NotificationPreference[]>();
  const homeAssistant = createHomeAssistantFacade(config);
  const homeService = new HomeService(config, homeAssistant, () => recentEvents);
  const pushSender = options.pushSender ?? createAPNsPushSender(config);

  app.use(cors());
  app.use(express.json({ limit: '1mb' }));

  app.get('/health', (_req, res) => {
    res.json({
      ok: true,
      service: 'levy-home-api',
      homeAssistantMode: config.homeAssistant.mode,
      registeredDeviceCount: registeredDevicesById.size,
      recentEventCount: recentEvents.length,
      uptimeSeconds: Math.round(process.uptime()),
    });
  });

  app.post('/api/devices/register', (req, res) => {
    const registration = validateRegisterDeviceBody(req.body);
    const lookupKey = createDeviceLookupKey(registration);
    const existingDeviceId = registeredDeviceIdsByLookupKey.get(lookupKey);
    const now = new Date().toISOString();
    const device: RegisteredDevice = {
      ...(existingDeviceId ? registeredDevicesById.get(existingDeviceId) : undefined),
      id: existingDeviceId ?? createDeviceId(registration),
      token: registration.token,
      platform: registration.platform,
      provider: registration.provider,
      ...(registration.environment ? { environment: registration.environment } : {}),
      ...(registration.appVersion ? { appVersion: registration.appVersion } : {}),
      ...(registration.deviceName ? { deviceName: registration.deviceName } : {}),
      registeredAt: existingDeviceId ? (registeredDevicesById.get(existingDeviceId)?.registeredAt ?? now) : now,
      lastSeenAt: now,
    };

    registeredDevicesById.set(device.id, device);
    registeredDeviceIdsByLookupKey.set(lookupKey, device.id);

    res.status(existingDeviceId ? 200 : 201).json({
      ok: true,
      registeredDeviceCount: registeredDevicesById.size,
      device: deviceResponse(device),
    });
  });

  app.get('/api/notification-preferences', (req, res) => {
    const locator = validateNotificationPreferencesQuery(req.query);
    const preferences = locator
      ? (preferencesByDeviceKey.get(preferenceKeyForLocator(locator, registeredDevicesById)) ?? GARAGE_NOTIFICATION_PREFERENCES)
      : GARAGE_NOTIFICATION_PREFERENCES;

    res.json({
      ok: true,
      preferences,
      syncedAt: new Date().toISOString(),
    });
  });

  app.put('/api/notification-preferences', (req, res) => {
    const update = validateNotificationPreferencesBody(req.body);
    const deviceKey = preferenceKeyForLocator(update.locator, registeredDevicesById);
    const preferences = applyPreferenceUpdates(GARAGE_NOTIFICATION_PREFERENCES, update.preferences);

    preferencesByDeviceKey.set(deviceKey, preferences);

    res.json({
      ok: true,
      preferences,
      syncedAt: new Date().toISOString(),
    });
  });

  app.post(
    '/api/debug/send-test-push',
    asyncHandler(async (req, res) => {
      const payload = validateTestPushBody(req.body);
      const summary = await sendPushToRegisteredDevices({
        devices: Array.from(registeredDevicesById.values()),
        preferencesByDeviceKey,
        pushSender,
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

  app.get(
    '/api/debug/home-assistant/phone-entities',
    requireHaWebhookSecret(config),
    asyncHandler(async (req, res) => {
      const candidates = await homeAssistant.discoverPhoneEntities(readPhoneDiscoveryKeywords(req.query.keywords));

      res.json({
        ok: true,
        candidates,
        candidateCount: candidates.length,
        generatedAt: new Date().toISOString(),
      });
    }),
  );

  app.get(
    '/api/home/overview',
    asyncHandler(async (_req, res) => {
      res.json({
        ok: true,
        overview: await homeService.getOverview(),
      });
    }),
  );

  app.get('/api/home/actions', (_req, res) => {
    res.json({
      ok: true,
      actions: homeService.listQuickActions(),
      lightGroups: lightActionTargets(config).map(({ id, name }) => ({ id, name })),
    });
  });

  app.post(
    '/api/home/actions',
    asyncHandler(async (req, res) => {
      const action = validateQuickActionBody(req.body);
      const result = await homeService.performAction(action.actionId, action.groupId);

      res.json({
        ok: true,
        result,
      });
    }),
  );

  app.post(
    '/api/home/actions/close-garage',
    asyncHandler(async (_req, res) => {
      const result = await homeService.performAction('close_garage');

      res.json({
        ok: true,
        result,
      });
    }),
  );

  app.post(
    '/api/home/actions/lights-off',
    asyncHandler(async (_req, res) => {
      const result = await homeService.performAction('turn_off_all_lights');

      res.json({
        ok: true,
        result,
      });
    }),
  );

  app.post(
    '/api/home/actions/light-groups/:groupId/off',
    asyncHandler(async (req, res) => {
      const groupId = typeof req.params.groupId === 'string' ? req.params.groupId : undefined;
      const result = await homeService.performAction('turn_off_light_group', groupId);

      res.json({
        ok: true,
        result,
      });
    }),
  );

  app.post(
    '/api/ha/events',
    requireHaWebhookSecret(config),
    asyncHandler(async (req, res) => {
    const validation = validateHomeAssistantEventPayload(req.body);

    if (!validation.ok) {
      res.status(400).json({ error: validation.error, code: validation.code });
      return;
    }

    const event = await createStoredEvent(validation.value, {
      devices: Array.from(registeredDevicesById.values()),
      preferencesByDeviceKey,
      pushSender,
    });
    recentEvents.unshift(event);

    if (recentEvents.length > 100) {
      recentEvents.length = 100;
    }

    res.status(201).json({
      ok: true,
      event,
      dedupeKey: buildEventDedupeKey(event),
      storedEventCount: recentEvents.length,
    });
    }),
  );

  app.get('/api/events', (req, res) => {
    const requestedLimit = Number(req.query.limit ?? 50);
    const limit = Number.isFinite(requestedLimit) ? Math.min(Math.max(requestedLimit, 1), 100) : 50;

    res.json({
      ok: true,
      events: recentEvents.slice(0, limit),
    });
  });

  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (err instanceof HTTPError) {
      res.status(err.statusCode).json({
        error: err.message,
        ...(err.code ? { code: err.code } : {}),
      });
      return;
    }

    console.error(err);
    res.status(500).json({ error: 'Unexpected server error.', code: 'unexpected_server_error' });
  });

  return app;
}

function lightActionTargets(config: AppConfig): Array<{ id: string; name: string }> {
  return config.homeAssistant.lightEntities.length > 0
    ? config.homeAssistant.lightEntities
    : config.homeAssistant.lightGroups;
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

function createDeviceLookupKey(registration: Pick<RegisteredDevice, 'token' | 'provider' | 'environment'>): string {
  const environment = registration.provider === 'apns' ? registration.environment : (registration.environment ?? 'none');

  return `${registration.provider}:${environment}:${hashToken(registration.token)}`;
}

function createDeviceId(registration: Pick<RegisteredDevice, 'token' | 'provider' | 'environment'>): string {
  const environment = registration.provider === 'apns' ? registration.environment : 'none';
  const prefix = registration.provider === 'apns' ? `apns-${environment}` : 'expo';

  return `${prefix}-${hashToken(registration.token).slice(0, 16)}`;
}

function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}

function deviceResponse(device: RegisteredDevice): Omit<RegisteredDevice, 'token'> {
  const { token: _token, ...response } = device;
  return response;
}

function preferenceKeyForLocator(
  locator: DevicePreferenceLocator,
  registeredDevicesById: Map<string, RegisteredDevice>,
): string {
  if ('deviceId' in locator) {
    const device = registeredDevicesById.get(locator.deviceId);

    if (device) {
      return `device-token:${createDeviceLookupKey(device)}`;
    }

    return `device-id:${locator.deviceId}`;
  }

  return `device-token:${createDeviceLookupKey(locator)}`;
}

function applyPreferenceUpdates(
  defaults: NotificationPreference[],
  updates: NotificationPreferenceUpdate[],
): NotificationPreference[] {
  const enabledByCategory = new Map(updates.map((update) => [update.category, update.isEnabled]));

  return defaults.map((preference) => ({
    ...preference,
    isEnabled: enabledByCategory.get(preference.category) ?? preference.isEnabled,
  }));
}

type PushSendOptions = {
  devices: RegisteredDevice[];
  preferencesByDeviceKey: Map<string, NotificationPreference[]>;
  pushSender: PushSender;
  payload: TestPushPayload;
  preferenceCategory?: NotificationPreferenceCategory;
};

async function sendPushToRegisteredDevices(options: PushSendOptions): Promise<PushSendSummary> {
  const apnsDevices = options.devices.filter((device) => device.provider === 'apns');
  const preferenceCategory = options.preferenceCategory;
  const enabledDevices = preferenceCategory
    ? apnsDevices.filter((device) =>
        isNotificationPreferenceEnabled(device, preferenceCategory, options.preferencesByDeviceKey),
      )
    : apnsDevices;
  const results: APNsSendResult[] = [];
  let configurationError: string | undefined;

  for (const device of enabledDevices) {
    try {
      results.push(
        await options.pushSender.send({
          device,
          title: options.payload.title,
          body: options.payload.body,
          data: options.preferenceCategory ? { category: options.preferenceCategory } : { debug: 'true' },
        }),
      );
    } catch (error) {
      if (error instanceof APNsConfigurationError) {
        configurationError = error.message;
        break;
      }

      results.push({
        provider: 'apns',
        deviceId: device.id,
        success: false,
        reason: error instanceof Error ? error.message : String(error),
        isInvalidToken: false,
      });
    }
  }

  const invalidTokenCount = results.filter((result) => result.isInvalidToken).length;

  return {
    provider: 'apns',
    registeredDeviceCount: options.devices.length,
    eligibleDeviceCount: enabledDevices.length,
    sentNotificationCount: results.filter((result) => result.success).length,
    failedNotificationCount: results.filter((result) => !result.success).length,
    invalidTokenCount,
    skippedDeviceCount: apnsDevices.length - enabledDevices.length,
    ...(configurationError ? { configurationError } : {}),
    results,
  };
}

function isNotificationPreferenceEnabled(
  device: RegisteredDevice,
  category: NotificationPreferenceCategory,
  preferencesByDeviceKey: Map<string, NotificationPreference[]>,
): boolean {
  const preferences =
    preferencesByDeviceKey.get(preferenceKeyForLocator({ token: device.token, provider: device.provider, environment: device.environment }, new Map())) ??
    GARAGE_NOTIFICATION_PREFERENCES;
  const preference = preferences.find((entry) => entry.category === category);

  return preference?.isEnabled ?? true;
}

function testPushMessage(summary: PushSendSummary): string {
  if (summary.registeredDeviceCount === 0) {
    return 'No registered devices are available for test push.';
  }

  if (summary.eligibleDeviceCount === 0) {
    return 'No registered APNs devices are available for test push.';
  }

  return `Sent ${summary.sentNotificationCount} APNs test notification(s).`;
}

function pushStatusFromSummary(summary: PushSendSummary, preferenceCategory?: NotificationPreferenceCategory): EventPushStatus {
  if (summary.configurationError) {
    return {
      attempted: false,
      skipped: true,
      reason: summary.configurationError,
    };
  }

  if (summary.registeredDeviceCount === 0 || summary.eligibleDeviceCount === 0) {
    return {
      attempted: false,
      skipped: true,
      reason:
        preferenceCategory && summary.skippedDeviceCount > 0
          ? 'All registered APNs devices have this notification disabled.'
          : 'No registered APNs devices are available for push delivery.',
    };
  }

  return {
    attempted: true,
    skipped: false,
    ticketCount: summary.sentNotificationCount,
    sentNotificationCount: summary.sentNotificationCount,
    failedNotificationCount: summary.failedNotificationCount,
    invalidTokenCount: summary.invalidTokenCount,
    ...(summary.failedNotificationCount > 0
      ? { reason: `${summary.failedNotificationCount} APNs notification(s) failed to send.` }
      : {}),
  };
}

function notificationCategoryForEvent(
  payload: HomeAssistantEventPayload,
): NotificationPreferenceCategory | undefined {
  const categoryByEventType: Partial<Record<HomeAssistantEventPayload['type'], NotificationPreferenceCategory>> = {
    garage_opened: 'garage_opened',
    garage_closed: 'garage_closed',
    garage_left_open_10_min: 'garage_left_open',
    garage_opened_after_hours: 'garage_after_hours',
    garage_still_open_at_10pm: 'garage_still_open_at_10pm',
  };
  const category = categoryByEventType[payload.type];

  return isNotificationPreferenceCategory(category) ? category : undefined;
}

export function startServer(config = readConfig()): void {
  const app = createApp({ config });
  const activityListener = createHomeAssistantActivityListener(config, {
    onStateChanged: (event) => {
      const normalizedEvent = normalizePhoneStateChangedEvent(event);
      console.info(`Home Assistant phone activity normalized ${normalizedEvent.entityId}.`);
    },
  });

  const server = app.listen(config.port, () => {
    console.log(`Levy Home API listening on http://localhost:${config.port}`);
    activityListener?.start();
  });

  server.on('close', () => {
    activityListener?.stop();
  });
}

async function createStoredEvent(
  payload: HomeAssistantEventPayload,
  pushOptions: Pick<PushSendOptions, 'devices' | 'preferencesByDeviceKey' | 'pushSender'>,
): Promise<LevyHomeEvent> {
  const display = getEventDisplayMetadata(payload.type);
  const preferenceCategory = notificationCategoryForEvent(payload);
  const push = preferenceCategory
    ? pushStatusFromSummary(
        await sendPushToRegisteredDevices({
          ...pushOptions,
          payload: {
            title: payload.title ?? display.title,
            body: payload.message ?? display.body,
          },
          preferenceCategory,
        }),
        preferenceCategory,
      )
    : {
        attempted: false,
        skipped: true,
        reason: 'No APNs notification preference category is configured for this event type.',
      };
  const isActivityOnlyPhoneEvent = payload.type === 'phone_state_changed' || payload.category === 'phone';

  return {
    id: crypto.randomUUID(),
    type: payload.type,
    entityId: payload.entityId,
    category: payload.category,
    severity: payload.severity,
    source: payload.source,
    occurredAt: payload.occurredAt ?? new Date().toISOString(),
    title: payload.title ?? display.title,
    message: payload.message ?? display.body,
    metadata: payload.metadata,
    receivedAt: new Date().toISOString(),
    display,
    ...(isActivityOnlyPhoneEvent ? {} : { push }),
  };
}

function requireHaWebhookSecret(config: AppConfig): (req: Request, res: Response, next: NextFunction) => void {
  return (req, res, next) => {
    if (!config.haWebhookSecret) {
      res.status(500).json({
        error: 'LEVY_HOME_HA_WEBHOOK_SECRET is not configured.',
        code: 'webhook_secret_not_configured',
      });
      return;
    }

    if (req.header('Authorization') !== `Bearer ${config.haWebhookSecret}`) {
      res.status(401).json({
        error: 'Unauthorized Home Assistant event webhook.',
        code: 'unauthorized_home_assistant_webhook',
      });
      return;
    }

    next();
  };
}

function asyncHandler(
  handler: (req: Request, res: Response, next: NextFunction) => Promise<void>,
): (req: Request, res: Response, next: NextFunction) => void {
  return (req, res, next) => {
    void handler(req, res, next).catch(next);
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  startServer();
}
