import { Router } from 'express';

import type { RecentActivityStore } from '../activityStore.js';
import type { AppConfig } from '../config.js';
import { asyncHandler } from '../http/asyncHandler.js';
import { safeErrorMessage } from '../observability/logger.js';
import type { DeviceRegistry } from '../services/notifications/deviceRegistry.js';
import type { ShoppingLiveActivityStore } from '../repositories/shoppingLiveActivityRepository.js';
import type { ShoppingStockPriceCheckReadiness } from '../services/shopping/stockPriceCheckReadiness.js';

export type NotificationPersistenceMode = 'memory' | 'postgres';

export type HealthRouteDependencies = {
  activityStore: RecentActivityStore;
  config: AppConfig;
  deviceRegistry: Pick<DeviceRegistry, 'count'>;
  notificationPersistenceMode: NotificationPersistenceMode;
  shoppingLiveActivityStore?: Pick<ShoppingLiveActivityStore, 'getDiagnostics'>;
  shoppingStockPriceCheckReadiness?: ShoppingStockPriceCheckReadiness;
};

export function createHealthRoutes(deps: HealthRouteDependencies): Router {
  const router = Router();

  router.get('/health', asyncHandler(async (_req, res) => {
    const registeredDeviceCount = await optionalRegisteredDeviceCount(deps.deviceRegistry);

    res.json({
      ok: true,
      service: 'levy-home-api',
      homeAssistantMode: deps.config.homeAssistant.mode,
      notificationPersistenceMode: deps.notificationPersistenceMode,
      registeredDeviceCount,
      recentEventCount: deps.activityStore.count(),
      uptimeSeconds: Math.round(process.uptime()),
    });
  }));

  router.get('/ready', asyncHandler(async (_req, res) => {
    const readiness = await readinessStatus(deps);

    res.status(readiness.ok ? 200 : 503).json(readiness);
  }));

  return router;
}

async function optionalRegisteredDeviceCount(
  deviceRegistry: Pick<DeviceRegistry, 'count'>,
): Promise<number | null> {
  try {
    return await deviceRegistry.count();
  } catch {
    return null;
  }
}

async function readinessStatus(deps: HealthRouteDependencies) {
  const notificationPersistence = await notificationPersistenceReadiness(deps);
  const homeAssistant = homeAssistantReadiness(deps.config);
  const apns = apnsReadiness(deps.config);
  const shoppingLiveActivities = await shoppingLiveActivityReadiness(deps);
  const shoppingStockPriceChecks = deps.shoppingStockPriceCheckReadiness
    ? await deps.shoppingStockPriceCheckReadiness.getReadiness()
    : { ok: true, enabled: false, mode: 'not_configured' };
  const checks = {
    process: { ok: true },
    activity: {
      ok: true,
      persistenceMode: 'memory',
      recentEventCount: deps.activityStore.count(),
    },
    notificationPersistence,
    homeAssistant,
    apns,
    shoppingLiveActivities,
    shoppingStockPriceChecks,
  };
  const ok = Object.values(checks).every((check) => check.ok);

  return {
    ok,
    service: 'levy-home-api',
    checks,
  };
}

async function shoppingLiveActivityReadiness(deps: HealthRouteDependencies) {
  if (!deps.shoppingLiveActivityStore) {
    return { ok: true, mode: 'not_configured' };
  }

  try {
    const diagnostics = await deps.shoppingLiveActivityStore.getDiagnostics();
    return {
      ok: true,
      mode: 'postgres',
      migrationState: 'available',
      activePushToStartRegistrationCount: diagnostics.activePushToStartRegistrationCount,
      activeUpdateRegistrationCount: diagnostics.activeUpdateRegistrationCount,
    };
  } catch (error) {
    return {
      ok: false,
      mode: 'postgres',
      code: 'shopping_live_activity_persistence_unavailable',
      error: safeErrorMessage(error),
    };
  }
}

async function notificationPersistenceReadiness(deps: HealthRouteDependencies) {
  try {
    return {
      ok: true,
      mode: deps.notificationPersistenceMode,
      registeredDeviceCount: await deps.deviceRegistry.count(),
    };
  } catch (error) {
    return {
      ok: false,
      mode: deps.notificationPersistenceMode,
      code: 'notification_persistence_unavailable',
      error: safeErrorMessage(error),
    };
  }
}

function homeAssistantReadiness(config: AppConfig) {
  if (config.homeAssistant.mode === 'mock') {
    return { ok: true, mode: 'mock' };
  }

  const hasCredentials = Boolean(config.homeAssistant.baseURL && config.homeAssistant.token);

  return {
    ok: hasCredentials,
    mode: 'live',
    ...(hasCredentials ? {} : { code: 'home_assistant_credentials_missing' }),
  };
}

function apnsReadiness(config: AppConfig) {
  const isConfigured = Boolean(
    config.apns.keyId &&
      config.apns.teamId &&
      config.apns.bundleId &&
      config.apns.privateKey,
  );

  return {
    ok: true,
    configured: isConfigured,
    required: false,
  };
}
