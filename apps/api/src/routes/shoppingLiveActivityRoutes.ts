import { Router } from 'express';

import type { ShoppingLiveActivityRegistrationResponse } from '../contracts.js';
import { asyncHandler } from '../http/asyncHandler.js';
import { HTTPError } from '../http/errors.js';
import type { DeviceRegistry } from '../services/notifications/deviceRegistry.js';
import type { ShoppingLiveActivityDeliveryService } from '../services/shopping/shoppingLiveActivityDeliveryService.js';
import { validateShoppingLiveActivityRegistrationBody } from '../validation/shoppingLiveActivityValidation.js';

export type ShoppingLiveActivityRouteDependencies = {
  deviceRegistry: Pick<DeviceRegistry, 'getDevice'>;
  shoppingLiveActivityDeliveryService?: ShoppingLiveActivityDeliveryService;
};

export function createShoppingLiveActivityRoutes(deps: ShoppingLiveActivityRouteDependencies): Router {
  const router = Router();

  router.post('/api/shopping-list/live-activities/registrations', asyncHandler(async (req, res) => {
    const request = validateShoppingLiveActivityRegistrationBody(req.body);
    const pushDevice = await deps.deviceRegistry.getDevice(request.pushDeviceId);

    if (!pushDevice || pushDevice.provider !== 'apns') {
      throw new HTTPError(404, 'APNs device registration was not found.', 'shopping_live_activity_device_not_found');
    }

    if (pushDevice.environment !== request.environment) {
      throw new HTTPError(409, 'ActivityKit environment does not match the registered APNs device.', 'shopping_live_activity_environment_mismatch');
    }

    const deliveryService = requireDeliveryService(deps);
    const registration = await deliveryService.register(request);
    const response: ShoppingLiveActivityRegistrationResponse = {
      ok: true,
      registration,
      generatedAt: new Date().toISOString(),
    };

    res.status(201).json(response);
  }));

  return router;
}

function requireDeliveryService(
  deps: ShoppingLiveActivityRouteDependencies,
): ShoppingLiveActivityDeliveryService {
  if (!deps.shoppingLiveActivityDeliveryService) {
    throw new HTTPError(503, 'Shopping Live Activity delivery is not configured.', 'shopping_live_activity_not_configured');
  }

  return deps.shoppingLiveActivityDeliveryService;
}
