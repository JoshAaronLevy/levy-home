import { Router } from 'express';

import {
  deviceResponse,
  type DeviceRegistry,
} from '../services/notifications/deviceRegistry.js';
import { validateRegisterDeviceBody } from '../validation/deviceValidation.js';

export type DeviceRouteDependencies = {
  deviceRegistry: DeviceRegistry;
};

export function createDeviceRoutes(deps: DeviceRouteDependencies): Router {
  const router = Router();

  router.post('/api/devices/register', (req, res) => {
    const registration = validateRegisterDeviceBody(req.body);
    const result = deps.deviceRegistry.registerDevice(registration);

    res.status(result.statusCode).json({
      ok: true,
      registeredDeviceCount: result.registeredDeviceCount,
      device: deviceResponse(result.device),
    });
  });

  return router;
}
