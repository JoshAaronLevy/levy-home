import { Router, type Request } from 'express';
import crypto from 'node:crypto';

import type {
  DeleteShoppingListItemResponse,
  KrogerProductSearchResponse,
  ShoppingListItem,
  ShoppingListItemLookupResponse,
  ShoppingListMutationResponse,
} from '../contracts.js';
import { asyncHandler } from '../http/asyncHandler.js';
import { HTTPError } from '../http/errors.js';
import type { ShoppingListRealtimeBroadcaster } from '../shoppingListRealtime.js';
import type { ShoppingListStore } from '../shoppingListStore.js';
import {
  validateCreateShoppingListItemBody,
  validateShoppingListItemLookupQuery,
  validateShoppingProductSearchQuery,
  validateUpdateShoppingListItemBody,
} from '../validation.js';

export type ShoppingListRouteDependencies = {
  krogerProductSearchRunner: (query?: string) => Promise<KrogerProductSearchResponse>;
  shoppingListRealtime?: ShoppingListRealtimeBroadcaster;
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
    const duplicate = await deps.shoppingListStore.findItemByName(request.name);

    if (duplicate) {
      throw duplicateShoppingItemError(duplicate);
    }

    const mutationId = mutationIdForRequest(req, request.mutationId);

    try {
      const item = await deps.shoppingListStore.createItem(request);
      const response = shoppingListMutationResponse(item, mutationId);

      res.status(201).json(response);
      deps.shoppingListRealtime?.broadcastItemCreated(item, mutationId);
    } catch (error) {
      if (isDatabaseUniqueViolation(error)) {
        throw duplicateShoppingItemError();
      }

      throw error;
    }
  }));

  router.patch('/api/shopping-list/items/:itemId', asyncHandler(async (req, res) => {
    const itemId = readShoppingListItemId(req.params.itemId);
    const request = validateUpdateShoppingListItemBody(req.body);
    const mutationId = mutationIdForRequest(req, request.mutationId);

    if (request.name !== undefined) {
      const currentItem = await deps.shoppingListStore.fetchItem(itemId);

      if (!currentItem) {
        throw shoppingItemNotFoundError();
      }

      const duplicate = await deps.shoppingListStore.findItemByName(request.name);

      if (duplicate && duplicate.id !== itemId) {
        throw duplicateShoppingItemError(duplicate);
      }
    }

    try {
      const item = await deps.shoppingListStore.updateItem(itemId, request);

      if (!item) {
        throw shoppingItemNotFoundError();
      }

      const response = shoppingListMutationResponse(item, mutationId);

      res.json(response);
      deps.shoppingListRealtime?.broadcastItemUpdated(item, mutationId);
    } catch (error) {
      if (isDatabaseUniqueViolation(error)) {
        throw duplicateShoppingItemError();
      }

      throw error;
    }
  }));

  router.delete('/api/shopping-list/items/:itemId', asyncHandler(async (req, res) => {
    const itemId = readShoppingListItemId(req.params.itemId);
    const mutationId = mutationIdForRequest(req);
    const item = await deps.shoppingListStore.deleteItem(itemId);

    if (!item) {
      throw shoppingItemNotFoundError();
    }

    const response: DeleteShoppingListItemResponse = {
      ok: true,
      itemId,
      item,
      mutationId,
      generatedAt: new Date().toISOString(),
    };

    res.json(response);
    deps.shoppingListRealtime?.broadcastItemDeleted(itemId, mutationId);
  }));

  return router;
}

function readShoppingListItemId(value: unknown): number {
  const id = typeof value === 'string' && value.trim().length > 0 ? Number(value) : Number.NaN;

  if (!Number.isInteger(id) || id < 1) {
    throw new HTTPError(400, 'itemId must be a positive integer.', 'invalid_shopping_item');
  }

  return id;
}

function mutationIdForRequest(req: Request, bodyMutationId?: string): string {
  const headerMutationId = req.get('X-Levy-Home-Mutation-ID')?.trim();

  return bodyMutationId ?? (headerMutationId && headerMutationId.length > 0 ? headerMutationId : crypto.randomUUID());
}

function shoppingListMutationResponse(item: ShoppingListItem, mutationId: string): ShoppingListMutationResponse {
  return {
    ok: true,
    item,
    mutationId,
    generatedAt: new Date().toISOString(),
  };
}

function shoppingItemNotFoundError(): HTTPError {
  return new HTTPError(404, 'Shopping item was not found.', 'shopping_item_not_found');
}

function duplicateShoppingItemError(item?: ShoppingListItem): HTTPError {
  return new HTTPError(
    409,
    item ? `Shopping item already exists: ${item.name}.` : 'Shopping item already exists.',
    'duplicate_shopping_item',
  );
}

function isDatabaseUniqueViolation(error: unknown): boolean {
  return typeof error === 'object' && error !== null && (error as { code?: unknown }).code === '23505';
}
