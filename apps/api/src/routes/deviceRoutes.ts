import { Router } from 'express';

import {
  createDeviceId,
  createDeviceLookupKey,
  deviceResponse,
  type RegisteredDeviceState,
} from './routeState.js';
import type { RegisteredDevice } from '../contracts.js';
import { validateRegisterDeviceBody } from '../validation.js';

export type DeviceRouteDependencies = RegisteredDeviceState;

export function createDeviceRoutes(deps: DeviceRouteDependencies): Router {
  const router = Router();

  router.post('/api/devices/register', (req, res) => {
    const registration = validateRegisterDeviceBody(req.body);
    const lookupKey = createDeviceLookupKey(registration);
    const existingDeviceId = deps.registeredDeviceIdsByLookupKey.get(lookupKey);
    const now = new Date().toISOString();
    const device: RegisteredDevice = {
      ...(existingDeviceId ? deps.registeredDevicesById.get(existingDeviceId) : undefined),
      id: existingDeviceId ?? createDeviceId(registration),
      token: registration.token,
      platform: registration.platform,
      provider: registration.provider,
      ...(registration.environment ? { environment: registration.environment } : {}),
      ...(registration.appVersion ? { appVersion: registration.appVersion } : {}),
      ...(registration.deviceName ? { deviceName: registration.deviceName } : {}),
      registeredAt: existingDeviceId
        ? (deps.registeredDevicesById.get(existingDeviceId)?.registeredAt ?? now)
        : now,
      lastSeenAt: now,
    };

    deps.registeredDevicesById.set(device.id, device);
    deps.registeredDeviceIdsByLookupKey.set(lookupKey, device.id);

    res.status(existingDeviceId ? 200 : 201).json({
      ok: true,
      registeredDeviceCount: deps.registeredDevicesById.size,
      device: deviceResponse(device),
    });
  });

  return router;
}
