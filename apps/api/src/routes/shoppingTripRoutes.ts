import { Router } from 'express';

import type { ShoppingActiveTripResponse } from '../contracts.js';
import { DatabaseConfigurationError } from '../db/client.js';
import { HTTPError } from '../http/errors.js';
import { asyncHandler } from '../http/asyncHandler.js';
import { mutationIdForRequest } from '../services/shopping/shoppingListMutationService.js';
import type { ShoppingTripService } from '../services/shopping/shoppingTripService.js';
import type { DeviceRegistry } from '../services/notifications/deviceRegistry.js';
import {
  validateCompleteShoppingTripBody,
  validateClaimShoppingTripDisplayBody,
  validateShoppingTripMutationId,
  validateStartShoppingTripBody,
} from '../validation/shoppingTripValidation.js';

export type ShoppingTripRouteDependencies = {
  deviceRegistry: Pick<DeviceRegistry, 'getDevice'>;
  shoppingTripService?: ShoppingTripService;
};

export function createShoppingTripRoutes(deps: ShoppingTripRouteDependencies): Router {
  const router = Router();

  router.get('/api/shopping-list/trip', asyncHandler(async (_req, res) => {
    const response: ShoppingActiveTripResponse = {
      ok: true,
      activeTrip: await requireShoppingTripService(deps).getActiveTrip(),
      generatedAt: new Date().toISOString(),
    };

    res.json(response);
  }));

  router.post('/api/shopping-list/trip/start', asyncHandler(async (req, res) => {
    const request = validateStartShoppingTripBody(req.body);
    if (request.originatingPushDeviceId) {
      await requireAPNsDevice(deps, request.originatingPushDeviceId);
    }
    const mutationId = validateShoppingTripMutationId(mutationIdForRequest(req, request.mutationId));
    const response = await requireShoppingTripService(deps).startTrip({
      ...request,
      mutationId,
    });

    res.status(201).json(response);
  }));

  router.post('/api/shopping-list/trip/:tripId/display/claim', asyncHandler(async (req, res) => {
    const tripId = Array.isArray(req.params.tripId) ? req.params.tripId[0] : req.params.tripId;
    const request = validateClaimShoppingTripDisplayBody(tripId ?? '', req.body);
    await requireAPNsDevice(deps, request.pushDeviceId);
    const displayDisposition = await requireShoppingTripService(deps).claimTripDisplay(request);

    if (!displayDisposition) {
      throw new HTTPError(409, 'Shopping trip display can only be claimed while the trip is active.', 'shopping_trip_not_active');
    }

    res.json({
      ok: true,
      displayDisposition,
      generatedAt: new Date().toISOString(),
    });
  }));

  router.post('/api/shopping-list/trip/end', asyncHandler(async (req, res) => {
    const request = validateCompleteShoppingTripBody(req.body);
    const mutationId = validateShoppingTripMutationId(mutationIdForRequest(req, request.mutationId));
    const response = await requireShoppingTripService(deps).endTrip({
      ...request,
      mutationId,
    });

    res.json(response);
  }));

  return router;
}

async function requireAPNsDevice(
  deps: ShoppingTripRouteDependencies,
  deviceId: string,
): Promise<void> {
  const device = await deps.deviceRegistry.getDevice(deviceId);

  if (!device || device.provider !== 'apns') {
    throw new HTTPError(
      409,
      'The originating iPhone must register for APNs before starting a shopping trip.',
      'shopping_trip_device_not_registered',
    );
  }
}

function requireShoppingTripService(deps: ShoppingTripRouteDependencies): ShoppingTripService {
  if (!deps.shoppingTripService) {
    throw new DatabaseConfigurationError();
  }

  return deps.shoppingTripService;
}
