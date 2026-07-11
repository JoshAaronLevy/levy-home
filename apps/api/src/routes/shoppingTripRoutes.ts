import { Router } from 'express';

import type { ShoppingActiveTripResponse } from '../contracts.js';
import { DatabaseConfigurationError } from '../db/client.js';
import { asyncHandler } from '../http/asyncHandler.js';
import { mutationIdForRequest } from '../services/shopping/shoppingListMutationService.js';
import type { ShoppingTripService } from '../services/shopping/shoppingTripService.js';
import {
  validateCompleteShoppingTripBody,
  validateShoppingTripMutationId,
  validateStartShoppingTripBody,
} from '../validation/shoppingTripValidation.js';

export type ShoppingTripRouteDependencies = {
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
    const mutationId = validateShoppingTripMutationId(mutationIdForRequest(req, request.mutationId));
    const response = await requireShoppingTripService(deps).startTrip({
      ...request,
      mutationId,
    });

    res.status(201).json(response);
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

function requireShoppingTripService(deps: ShoppingTripRouteDependencies): ShoppingTripService {
  if (!deps.shoppingTripService) {
    throw new DatabaseConfigurationError();
  }

  return deps.shoppingTripService;
}
