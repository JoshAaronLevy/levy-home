import crypto from 'node:crypto';
import type { Request } from 'express';

import type {
  CreateShoppingListItemRequest,
  DeleteShoppingListItemResponse,
  ShoppingListItem,
  ShoppingListMutationResponse,
  UpdateShoppingListItemRequest,
} from '../../contracts.js';
import { HTTPError } from '../../http/errors.js';
import type { ShoppingListRealtimeBroadcaster } from '../../shoppingListRealtime.js';
import type { ShoppingListStore } from '../../shoppingListStore.js';

export type ShoppingListMutationService = {
  createItem: (request: CreateShoppingListItemRequest, mutationId: string) => Promise<ShoppingListMutationResponse>;
  deleteItem: (itemId: number, mutationId: string) => Promise<DeleteShoppingListItemResponse>;
  updateItem: (
    itemId: number,
    request: UpdateShoppingListItemRequest,
    mutationId: string,
  ) => Promise<ShoppingListMutationResponse>;
};

export function createShoppingListMutationService(options: {
  shoppingListRealtime?: ShoppingListRealtimeBroadcaster;
  shoppingListStore: ShoppingListStore;
}): ShoppingListMutationService {
  const { shoppingListRealtime, shoppingListStore } = options;

  return {
    async createItem(request, mutationId) {
      const duplicate = await shoppingListStore.findItemByName(request.name);

      if (duplicate) {
        throw duplicateShoppingItemError(duplicate);
      }

      try {
        const item = await shoppingListStore.createItem(request);
        const response = shoppingListMutationResponse(item, mutationId);

        shoppingListRealtime?.broadcastItemCreated(item, mutationId);

        return response;
      } catch (error) {
        if (isDatabaseUniqueViolation(error)) {
          throw duplicateShoppingItemError();
        }

        throw error;
      }
    },
    async deleteItem(itemId, mutationId) {
      const item = await shoppingListStore.deleteItem(itemId);

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

      shoppingListRealtime?.broadcastItemDeleted(itemId, mutationId);

      return response;
    },
    async updateItem(itemId, request, mutationId) {
      if (request.name !== undefined) {
        const currentItem = await shoppingListStore.fetchItem(itemId);

        if (!currentItem) {
          throw shoppingItemNotFoundError();
        }

        const duplicate = await shoppingListStore.findItemByName(request.name);

        if (duplicate && duplicate.id !== itemId) {
          throw duplicateShoppingItemError(duplicate);
        }
      }

      try {
        const item = await shoppingListStore.updateItem(itemId, request);

        if (!item) {
          throw shoppingItemNotFoundError();
        }

        const response = shoppingListMutationResponse(item, mutationId);

        shoppingListRealtime?.broadcastItemUpdated(item, mutationId);

        return response;
      } catch (error) {
        if (isDatabaseUniqueViolation(error)) {
          throw duplicateShoppingItemError();
        }

        throw error;
      }
    },
  };
}

export function readShoppingListItemId(value: unknown): number {
  const id = typeof value === 'string' && value.trim().length > 0 ? Number(value) : Number.NaN;

  if (!Number.isInteger(id) || id < 1) {
    throw new HTTPError(400, 'itemId must be a positive integer.', 'invalid_shopping_item');
  }

  return id;
}

export function mutationIdForRequest(req: Request, bodyMutationId?: string): string {
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
