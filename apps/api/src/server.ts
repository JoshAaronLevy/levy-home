import 'dotenv/config';

import cors from 'cors';
import express, { type NextFunction, type Request, type Response } from 'express';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';

import type { AppConfig } from './config.js';
import { readConfig } from './config.js';
import {
  buildEventDedupeKey,
  GARAGE_NOTIFICATION_PREFERENCES,
  getEventDisplayMetadata,
  type DevicePreferenceLocator,
  type EventPushStatus,
  type HomeAssistantEventPayload,
  type LevyHomeEvent,
  type NotificationPreference,
  type NotificationPreferenceUpdate,
  type QuickActionId,
  type RegisteredDevice,
} from './contracts.js';
import { createHomeAssistantFacade } from './homeAssistantClient.js';
import { HomeService } from './homeService.js';
import { HTTPError } from './httpError.js';
import {
  validateHomeAssistantEventPayload,
  validateNotificationPreferencesBody,
  validateNotificationPreferencesQuery,
  validateQuickActionBody,
  validateRegisterDeviceBody,
} from './validation.js';

export type CreateAppOptions = {
  config?: AppConfig;
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
      lightGroups: config.homeAssistant.lightGroups.map(({ id, name }) => ({ id, name })),
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

  app.post('/api/ha/events', requireHaWebhookSecret(config), (req, res) => {
    const validation = validateHomeAssistantEventPayload(req.body);

    if (!validation.ok) {
      res.status(400).json({ error: validation.error, code: validation.code });
      return;
    }

    const event = createStoredEvent(validation.value);
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
  });

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

export function startServer(config = readConfig()): void {
  const app = createApp({ config });

  app.listen(config.port, () => {
    console.log(`Levy Home API listening on http://localhost:${config.port}`);
  });
}

function createStoredEvent(payload: HomeAssistantEventPayload): LevyHomeEvent {
  const display = getEventDisplayMetadata(payload.type);
  const push: EventPushStatus = {
    attempted: false,
    skipped: true,
    reason: 'Push delivery is not configured in this backend stage.',
  };

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
    push,
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
