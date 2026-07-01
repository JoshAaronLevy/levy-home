import { Router } from 'express';

import type {
  ToDoLocationMutationResponse,
  ToDoLocationsResponse,
} from '../contracts.js';
import { asyncHandler } from '../http/asyncHandler.js';
import type { ToDoLocationStore } from '../repositories/todoLocationRepository.js';
import { validateCreateToDoLocationBody } from '../validation/todoValidation.js';

export type ToDoLocationRouteDependencies = {
  toDoLocationStore: ToDoLocationStore;
};

export function createToDoLocationRoutes(deps: ToDoLocationRouteDependencies): Router {
  const router = Router();

  router.get('/api/todo/locations', asyncHandler(async (_req, res) => {
    const response: ToDoLocationsResponse = {
      ok: true,
      locations: await deps.toDoLocationStore.fetchLocations(),
      generatedAt: new Date().toISOString(),
    };

    res.json(response);
  }));

  router.post('/api/todo/locations', asyncHandler(async (req, res) => {
    const request = validateCreateToDoLocationBody(req.body);
    const location = await deps.toDoLocationStore.createLocation(request);
    const response: ToDoLocationMutationResponse = {
      ok: true,
      location,
      generatedAt: new Date().toISOString(),
    };

    res.status(201).json(response);
  }));

  return router;
}
