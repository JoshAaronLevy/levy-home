import 'dotenv/config';

import cors from 'cors';
import express, { type NextFunction, type Request, type Response } from 'express';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';

import {
  normalizePhoneStateChangedEvent,
  shouldIncludePhoneStateChangedEvent,
} from './activityNormalizer.js';
import {
  clampRecentActivityLimit,
  createRecentActivityStore,
  type RecentActivityStore,
} from './activityStore.js';
import {
  backfillHomeAssistantActivity,
  fetchHomeAssistantActivityWindow,
} from './homeAssistantActivityBackfill.js';
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
import { DatabaseConfigurationError } from './dbClient.js';
import {
  createHomeAssistantActivityListener,
  type HomeAssistantStateChangedEvent,
} from './homeAssistantActivityClient.js';
import { createHomeAssistantFacade } from './homeAssistantClient.js';
import { HomeService } from './homeService.js';
import { HTTPError } from './httpError.js';
import { createPostgresShoppingListStore, type ShoppingListStore } from './shoppingListStore.js';
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
  activityStore?: RecentActivityStore;
  pushSender?: PushSender;
  shoppingListStore?: ShoppingListStore;
};

export function createApp(options: CreateAppOptions = {}): express.Express {
  const config = options.config ?? readConfig();
  const app = express();
  const activityStore = options.activityStore ?? createRecentActivityStore(500);
  const registeredDevicesById = new Map<string, RegisteredDevice>();
  const registeredDeviceIdsByLookupKey = new Map<string, string>();
  const preferencesByDeviceKey = new Map<string, NotificationPreference[]>();
  const homeAssistant = createHomeAssistantFacade(config);
  const homeService = new HomeService(config, homeAssistant, () => activityStore.list(100));
  const pushSender = options.pushSender ?? createAPNsPushSender(config);
  const shoppingListStore = options.shoppingListStore ?? createPostgresShoppingListStore();

  app.set('etag', false);
  app.use(cors());
  app.use((_req, res, next) => {
    res.set('Cache-Control', 'no-store');
    next();
  });
  app.use(express.json({ limit: '1mb' }));

  app.get('/health', (_req, res) => {
    res.json({
      ok: true,
      service: 'levy-home-api',
      homeAssistantMode: config.homeAssistant.mode,
      registeredDeviceCount: registeredDevicesById.size,
      recentEventCount: activityStore.count(),
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
    '/api/home/actions/open-garage',
    asyncHandler(async (_req, res) => {
      const result = await homeService.performAction('open_garage');

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

  app.get('/api/shopping-list', asyncHandler(async (_req, res) => {
    const shoppingList = await shoppingListStore.fetchShoppingList();

    res.json({
      ok: true,
      ...shoppingList,
      generatedAt: new Date().toISOString(),
    });
  }));

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
    activityStore.add(event);

    res.status(201).json({
      ok: true,
      event,
      dedupeKey: buildEventDedupeKey(event),
      storedEventCount: activityStore.count(),
    });
    }),
  );

  app.get('/api/events', asyncHandler(async (req, res) => {
    const limit = clampRecentActivityLimit(req.query.limit);
    const window = parseActivityWindow(req.query);
    const storedEvents = activityStore
      .list(500)
      .filter((event) => isEventInWindow(event, window))
      .slice(0, limit);
    const historyEvents = window?.startTime && window.endTime
      ? await fetchNormalizedHomeAssistantHistoryEvents(config, {
          startTime: window.startTime,
          endTime: window.endTime,
        })
      : [];
    const events = mergeActivityEvents([...storedEvents, ...historyEvents], limit);

    res.json({
      ok: true,
      events,
    });
  }));

  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (err instanceof DatabaseConfigurationError) {
      res.status(503).json({
        error: err.message,
        code: 'database_not_configured',
      });
      return;
    }

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

type ActivityWindow = {
  startTime?: Date;
  endTime?: Date;
};

function parseActivityWindow(query: Request['query']): ActivityWindow | undefined {
  const hasStartOrEnd = typeof query.start === 'string' || typeof query.end === 'string';

  if (hasStartOrEnd) {
    if (typeof query.start !== 'string' || typeof query.end !== 'string') {
      throw new HTTPError(400, '`start` and `end` query parameters must be provided together.', 'invalid_activity_window');
    }

    const startTime = parseTimestamp(query.start);
    const endTime = parseTimestamp(query.end);

    if (!startTime || !endTime || startTime >= endTime) {
      throw new HTTPError(400, '`start` and `end` must be valid ISO timestamps with start before end.', 'invalid_activity_window');
    }

    if (endTime.getTime() - startTime.getTime() > 7 * 24 * 60 * 60 * 1_000) {
      throw new HTTPError(400, 'Activity windows cannot be longer than 7 days.', 'activity_window_too_large');
    }

    return { startTime, endTime };
  }

  const sinceTime = typeof query.since === 'string' ? parseTimestamp(query.since) : undefined;

  return sinceTime ? { startTime: sinceTime } : undefined;
}

function parseTimestamp(value: string): Date | undefined {
  const timestamp = Date.parse(value);

  if (!Number.isFinite(timestamp)) {
    return undefined;
  }

  return new Date(timestamp);
}

function isEventInWindow(event: LevyHomeEvent, window: ActivityWindow | undefined): boolean {
  if (!window) {
    return true;
  }

  const timestamp = eventTimestamp(event);

  if (window.startTime && timestamp < window.startTime.getTime()) {
    return false;
  }

  if (window.endTime && timestamp >= window.endTime.getTime()) {
    return false;
  }

  return true;
}

async function fetchNormalizedHomeAssistantHistoryEvents(
  config: AppConfig,
  window: Required<ActivityWindow>,
): Promise<LevyHomeEvent[]> {
  try {
    return (await fetchHomeAssistantActivityWindow(config, window))
      .filter(shouldIncludePhoneStateChangedEvent)
      .map((event) => normalizePhoneStateChangedEvent(event));
  } catch (error) {
    console.warn(`Home Assistant activity history unavailable for /api/events: ${safeErrorMessage(error)}`);
    return [];
  }
}

function eventTimestamp(event: LevyHomeEvent): number {
  const timestamp = Date.parse(event.occurredAt ?? '');

  return Number.isFinite(timestamp) ? timestamp : Number.NEGATIVE_INFINITY;
}

function mergeActivityEvents(events: LevyHomeEvent[], limit: number): LevyHomeEvent[] {
  const eventsByKey = new Map<string, LevyHomeEvent>();

  for (const event of events) {
    const key = activityEventKey(event);
    const existing = eventsByKey.get(key);

    if (!existing || event.receivedAt < existing.receivedAt) {
      eventsByKey.set(key, event);
    }
  }

  return Array.from(eventsByKey.values())
    .sort((a, b) => eventTimestamp(b) - eventTimestamp(a))
    .slice(0, limit);
}

function activityEventKey(event: LevyHomeEvent): string {
  return [
    event.type,
    event.entityId,
    event.occurredAt,
    event.display.title,
    event.display.body,
  ].join('|');
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
  const activityStore = createRecentActivityStore(500);
  const app = createApp({ config, activityStore });
  const storeHomeAssistantPhoneActivity = (event: HomeAssistantStateChangedEvent) => {
    if (!shouldIncludePhoneStateChangedEvent(event)) {
      return;
    }

    const normalizedEvent = normalizePhoneStateChangedEvent(event);

    activityStore.add(normalizedEvent);

    if (event.ingestionSource !== 'history') {
      console.info(`Home Assistant phone activity stored ${normalizedEvent.entityId}.`);
    }
  };
  const activityListener = createHomeAssistantActivityListener(config, {
    onStateChanged: storeHomeAssistantPhoneActivity,
  });

  const server = app.listen(config.port, () => {
    console.log(`Levy Home API listening on http://localhost:${config.port}`);
    activityListener?.start();
    void backfillHomeAssistantActivity(config, {
      onStateChanged: storeHomeAssistantPhoneActivity,
    })
      .then((eventCount) => {
        if (eventCount > 0) {
          console.info(`Home Assistant activity backfill stored ${eventCount} event(s) from the last 24 hours.`);
        }
      })
      .catch((error) => {
        console.warn(`Home Assistant activity backfill failed: ${safeErrorMessage(error)}`);
      });
  });

  server.on('close', () => {
    activityListener?.stop();
  });

  let isShuttingDown = false;
  const shutdown = (signal: NodeJS.Signals) => {
    if (isShuttingDown) {
      return;
    }

    isShuttingDown = true;
    console.info(`Levy Home API received ${signal}; shutting down.`);

    const forceExit = setTimeout(() => {
      process.exit(1);
    }, 10_000);
    forceExit.unref();

    server.close((error) => {
      if (error) {
        console.error(`Levy Home API shutdown failed: ${safeErrorMessage(error)}`);
        process.exit(1);
      }

      clearTimeout(forceExit);
      process.exit(0);
    });
  };

  process.once('SIGTERM', shutdown);
  process.once('SIGINT', shutdown);
}

function safeErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : 'Unknown error.';
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
