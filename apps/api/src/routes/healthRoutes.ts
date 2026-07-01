import { Router } from 'express';

import type { RecentActivityStore } from '../activityStore.js';
import type { AppConfig } from '../config.js';
import type { RegisteredDevice } from '../contracts.js';

export type HealthRouteDependencies = {
  activityStore: RecentActivityStore;
  config: AppConfig;
  registeredDevicesById: Map<string, RegisteredDevice>;
};

export function createHealthRoutes(deps: HealthRouteDependencies): Router {
  const router = Router();

  router.get('/health', (_req, res) => {
    res.json({
      ok: true,
      service: 'levy-home-api',
      homeAssistantMode: deps.config.homeAssistant.mode,
      registeredDeviceCount: deps.registeredDevicesById.size,
      recentEventCount: deps.activityStore.count(),
      uptimeSeconds: Math.round(process.uptime()),
    });
  });

  return router;
}
