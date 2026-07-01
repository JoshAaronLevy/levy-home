import { Router } from 'express';

import type { RecentActivityStore } from '../activityStore.js';
import type { AppConfig } from '../config.js';
import type { DeviceRegistry } from '../services/notifications/deviceRegistry.js';

export type HealthRouteDependencies = {
  activityStore: RecentActivityStore;
  config: AppConfig;
  deviceRegistry: Pick<DeviceRegistry, 'count'>;
};

export function createHealthRoutes(deps: HealthRouteDependencies): Router {
  const router = Router();

  router.get('/health', (_req, res) => {
    res.json({
      ok: true,
      service: 'levy-home-api',
      homeAssistantMode: deps.config.homeAssistant.mode,
      registeredDeviceCount: deps.deviceRegistry.count(),
      recentEventCount: deps.activityStore.count(),
      uptimeSeconds: Math.round(process.uptime()),
    });
  });

  return router;
}
