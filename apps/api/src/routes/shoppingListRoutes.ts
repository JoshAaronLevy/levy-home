import { Router } from 'express';

import type {
  KrogerProductSearchResponse,
  ShoppingListItemLookupResponse,
} from '../contracts.js';
import { asyncHandler } from '../http/asyncHandler.js';
import type { ShoppingListMutationService } from '../services/shopping/shoppingListMutationService.js';
import {
  mutationIdForRequest,
  readShoppingListItemId,
} from '../services/shopping/shoppingListMutationService.js';
import type { ShoppingListStore } from '../repositories/shoppingListRepository.js';
import {
  validateCreateShoppingListItemBody,
  validateShoppingListItemLookupQuery,
  validateShoppingProductSearchQuery,
  validateUpdateShoppingListItemBody,
} from '../validation/shoppingValidation.js';

export type ShoppingListRouteDependencies = {
  krogerProductSearchRunner: (query?: string) => Promise<KrogerProductSearchResponse>;
  shoppingListMutationService: ShoppingListMutationService;
  shoppingListStore: ShoppingListStore;
};

export function createShoppingListRoutes(deps: ShoppingListRouteDependencies): Router {
  const router = Router();

  router.get('/api/shopping-list', asyncHandler(async (_req, res) => {
    const shoppingList = await deps.shoppingListStore.fetchShoppingList();

    res.json({
      ok: true,
      ...shoppingList,
      generatedAt: new Date().toISOString(),
    });
  }));

  router.get('/api/shopping-list/items/lookup', asyncHandler(async (req, res) => {
    const query = validateShoppingListItemLookupQuery(req.query);
    const match = await deps.shoppingListStore.findItemByName(query);
    const response: ShoppingListItemLookupResponse = {
      ok: true,
      query,
      match,
    };

    res.json(response);
  }));

  router.get('/api/shopping-list/products/search', asyncHandler(async (req, res) => {
    const term = validateShoppingProductSearchQuery(req.query);
    const response = await deps.krogerProductSearchRunner(term);

    res.json(response);
  }));

  router.post('/api/shopping-list/items', asyncHandler(async (req, res) => {
    const request = validateCreateShoppingListItemBody(req.body);
    const mutationId = mutationIdForRequest(req, request.mutationId);
    const response = await deps.shoppingListMutationService.createItem(request, mutationId);

    res.status(201).json(response);
  }));

  router.patch('/api/shopping-list/items/:itemId', asyncHandler(async (req, res) => {
    const itemId = readShoppingListItemId(req.params.itemId);
    const request = validateUpdateShoppingListItemBody(req.body);
    const mutationId = mutationIdForRequest(req, request.mutationId);
    const response = await deps.shoppingListMutationService.updateItem(itemId, request, mutationId);

    res.json(response);
  }));

  router.delete('/api/shopping-list/items/:itemId', asyncHandler(async (req, res) => {
    const itemId = readShoppingListItemId(req.params.itemId);
    const mutationId = mutationIdForRequest(req);
    const response = await deps.shoppingListMutationService.deleteItem(itemId, mutationId);

    res.json(response);
  }));

  return router;
}
