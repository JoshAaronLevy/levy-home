import { Router } from 'express';

import {
  deviceResponse,
  type DeviceRegistry,
} from '../services/notifications/deviceRegistry.js';
import { asyncHandler } from '../http/asyncHandler.js';
import { validateRegisterDeviceBody } from '../validation/deviceValidation.js';

export type DeviceRouteDependencies = {
  deviceRegistry: DeviceRegistry;
};

export function createDeviceRoutes(deps: DeviceRouteDependencies): Router {
  const router = Router();

  router.post('/api/devices/register', asyncHandler(async (req, res) => {
    const registration = validateRegisterDeviceBody(req.body);
    const result = await deps.deviceRegistry.registerDevice(registration);

    res.status(result.statusCode).json({
      ok: true,
      ...(result.registeredDeviceCount === undefined
        ? {}
        : { registeredDeviceCount: result.registeredDeviceCount }),
      device: deviceResponse(result.device),
    });
  }));

  return router;
}
