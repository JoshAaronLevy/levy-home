import crypto from 'node:crypto';
import type { Request } from 'express';

import type {
  CreateShoppingListItemRequest,
  DeleteShoppingListItemRequest,
  DeleteShoppingListItemResponse,
  ShoppingListItem,
  ShoppingListMutationResponse,
  ShoppingTripSnapshot,
  UpdateShoppingListItemRequest,
} from '../../contracts.js';
import { HTTPError } from '../../http/errors.js';
import { logger as defaultLogger, safeErrorMessage, type Logger } from '../../observability/logger.js';
import {
  createShoppingListItem,
  deleteShoppingListItem,
  fetchShoppingListItemForUpdate,
  updateShoppingListItem,
  type ShoppingListStore,
} from '../../repositories/shoppingListRepository.js';
import { type DatabaseTransactionRunner } from '../../db/client.js';
import {
  applyShoppingTripItemMutation,
  lockActiveShoppingTrip,
  type ShoppingTripStore,
} from '../../repositories/shoppingTripRepository.js';
import type {
  ShoppingListRealtimeBroadcaster,
  ShoppingListRealtimeSessionRecorder,
} from '../../shoppingListRealtime.js';
import type { ShoppingTripService } from './shoppingTripService.js';
import type { ShoppingLiveActivityDeliveryService } from './shoppingLiveActivityDeliveryService.js';

export type ShoppingListMutationService = {
  createItem: (request: CreateShoppingListItemRequest, mutationId: string) => Promise<ShoppingListMutationResponse>;
  deleteItem: (
    itemId: number,
    mutationId: string,
    request?: DeleteShoppingListItemRequest,
  ) => Promise<DeleteShoppingListItemResponse>;
  updateItem: (
    itemId: number,
    request: UpdateShoppingListItemRequest,
    mutationId: string,
  ) => Promise<ShoppingListMutationResponse>;
  /**
   * Internal-only writer for a durable stock-and-price check.  It deliberately
   * cannot alter the shopper-owned fields on an item and never creates a
   * per-item session push notification.
   */
  applyStockPriceCheckListings: (
    itemId: number,
    request: { expectedVersion: number; storeListings: NonNullable<UpdateShoppingListItemRequest['storeListings']> },
    mutationId: string,
  ) => Promise<StockPriceCheckListingWriteResult>;
  /**
   * Internal-only optimistic writer for an AI Shopping re-add or its Undo.
   * It can alter only purchased and quantity after locking and comparing the
   * exact API-owned item state captured before matching.
   */
  applyShoppingListReaddUpdate: (
    itemId: number,
    request: ShoppingListReaddUpdateRequest,
    mutationId: string,
  ) => Promise<ShoppingListReaddWriteResult>;
};

export type StockPriceCheckListingWriteResult =
  | { status: 'updated'; response: ShoppingListMutationResponse }
  | { status: 'stale' };

export type ShoppingListReaddUpdateRequest = {
  expectedVersion: number;
  expectedPurchased: boolean;
  expectedQuantity: number;
  purchased: boolean;
  /** Omitted to preserve the current quantity. */
  quantity?: number;
  actor: 'Josh' | 'Mallory';
};

export type ShoppingListReaddWriteResult =
  | { status: 'updated'; response: ShoppingListMutationResponse }
  | { status: 'stale' };

export function createShoppingListMutationService(options: {
  logger?: Logger;
  shoppingListRealtime?: ShoppingListRealtimeBroadcaster & Partial<ShoppingListRealtimeSessionRecorder>;
  shoppingListStore: ShoppingListStore;
  shoppingTripService?: Pick<ShoppingTripService, 'getActiveTrip'>;
  shoppingTripStore?: ShoppingTripStore;
  transactionRunner?: DatabaseTransactionRunner;
  shoppingLiveActivityDeliveryService?: Pick<ShoppingLiveActivityDeliveryService, 'enqueueEvent'>;
}): ShoppingListMutationService {
  const auditLogger = options.logger ?? defaultLogger;
  const {
    shoppingListRealtime,
    shoppingListStore,
    shoppingTripService,
    shoppingTripStore,
    transactionRunner,
    shoppingLiveActivityDeliveryService,
  } = options;

  return {
    async createItem(request, mutationId) {
      const duplicate = await shoppingListStore.findItemByName(request.name);

      if (duplicate) {
        auditLogger.warn('Shopping list create rejected as duplicate.', {
          ...requestAuditDetails(request, mutationId),
          existingItemId: duplicate.id,
          existingPurchased: duplicate.purchased,
        });
        throw duplicateShoppingItemError(duplicate);
      }

      try {
        const committed = await commitShoppingMutation({ kind: 'created', request });
        const { item } = committed;
        const response = shoppingListMutationResponse(
          item,
          mutationId,
          committed.activeTrip,
        );

        auditLogger.info('Shopping list create committed.', itemAuditDetails(item, mutationId, request.actor));
        shoppingListRealtime?.broadcastItemCreated(item, mutationId);
        await publishTripUpdateIfNeeded(committed.activeTrip, committed.tripUpdated, mutationId);
        shoppingListRealtime?.recordItemMutation?.(item, mutationId, 'created', request.actor);
        auditLogger.info('Shopping list create completed.', {
          ...itemAuditDetails(item, mutationId, request.actor),
          notification: 'session_pending',
        });

        return response;
      } catch (error) {
        if (isDatabaseUniqueViolation(error)) {
          auditLogger.warn('Shopping list create rejected by database uniqueness.', {
            ...requestAuditDetails(request, mutationId),
            error: safeErrorMessage(error),
          });
          throw duplicateShoppingItemError();
        }

        auditLogger.error('Shopping list create failed.', {
          ...requestAuditDetails(request, mutationId),
          error: safeErrorMessage(error),
        });
        throw error;
      }
    },
    async deleteItem(itemId, mutationId, request = {}) {
      const committed = await commitShoppingMutation({ kind: 'deleted', itemId, request });
      const { item } = committed;

      if (!item) {
        auditLogger.warn('Shopping list delete rejected as missing.', {
          ...mutationAuditDetails(mutationId, request.actor),
          itemId,
        });
        throw shoppingItemNotFoundError();
      }

      const response: DeleteShoppingListItemResponse = {
        ok: true,
        itemId,
        item,
        activeTrip: committed.activeTrip,
        mutationId,
        generatedAt: new Date().toISOString(),
      };

      auditLogger.info('Shopping list delete committed.', itemAuditDetails(item, mutationId, request.actor));
      shoppingListRealtime?.broadcastItemDeleted(itemId, mutationId);
      await publishTripUpdateIfNeeded(committed.activeTrip, committed.tripUpdated, mutationId);
      shoppingListRealtime?.recordItemMutation?.(item, mutationId, 'deleted', request.actor);
      auditLogger.info('Shopping list delete completed.', {
        ...itemAuditDetails(item, mutationId, request.actor),
        notification: 'session_pending',
      });

      return response;
    },
    async updateItem(itemId, request, mutationId) {
      if (request.name !== undefined) {
        const currentItem = await shoppingListStore.fetchItem(itemId);

        if (!currentItem) {
          auditLogger.warn('Shopping list update rejected as missing before rename.', {
            ...requestAuditDetails(request, mutationId),
            itemId,
          });
          throw shoppingItemNotFoundError();
        }

        const duplicate = await shoppingListStore.findItemByName(request.name);

        if (duplicate && duplicate.id !== itemId) {
          auditLogger.warn('Shopping list update rejected as duplicate.', {
            ...requestAuditDetails(request, mutationId),
            itemId,
            existingItemId: duplicate.id,
            existingPurchased: duplicate.purchased,
          });
          throw duplicateShoppingItemError(duplicate);
        }
      }

      try {
        const committed = await commitShoppingMutation({ kind: 'updated', itemId, request });
        const { item } = committed;

        if (!item) {
          auditLogger.warn('Shopping list update rejected as missing.', {
            ...requestAuditDetails(request, mutationId),
            itemId,
          });
          throw shoppingItemNotFoundError();
        }

        const response = shoppingListMutationResponse(
          item,
          mutationId,
          committed.activeTrip,
        );

        auditLogger.info('Shopping list update committed.', itemAuditDetails(item, mutationId, request.actor));
        shoppingListRealtime?.broadcastItemUpdated(item, mutationId);
        await publishTripUpdateIfNeeded(committed.activeTrip, committed.tripUpdated, mutationId);
        shoppingListRealtime?.recordItemMutation?.(
          item,
          mutationId,
          request.purchased === true ? 'completed' : 'updated',
          request.actor,
        );
        auditLogger.info('Shopping list update completed.', {
          ...itemAuditDetails(item, mutationId, request.actor),
          notification: 'session_pending',
        });

        return response;
      } catch (error) {
        if (isDatabaseUniqueViolation(error)) {
          auditLogger.warn('Shopping list update rejected by database uniqueness.', {
            ...requestAuditDetails(request, mutationId),
            itemId,
            error: safeErrorMessage(error),
          });
          throw duplicateShoppingItemError();
        }

        auditLogger.error('Shopping list update failed.', {
          ...requestAuditDetails(request, mutationId),
          itemId,
          error: safeErrorMessage(error),
        });
        throw error;
      }
    },
    async applyStockPriceCheckListings(itemId, request, mutationId) {
      try {
        const committed = await commitShoppingMutation({
          kind: 'stock_price_check',
          itemId,
          expectedVersion: request.expectedVersion,
          request: {
            storeListings: request.storeListings,
            actor: 'AI stock check',
          },
        });
        const response = shoppingListMutationResponse(committed.item, mutationId, committed.activeTrip);

        auditLogger.info('Shopping stock and price listings committed.', {
          ...itemAuditDetails(response.item, mutationId, 'AI stock check'),
          notification: 'suppressed',
        });
        shoppingListRealtime?.broadcastItemUpdated(response.item, mutationId);
        await publishTripUpdateIfNeeded(committed.activeTrip, committed.tripUpdated, mutationId);

        return { status: 'updated', response };
      } catch (error) {
        if (error instanceof StockPriceCheckStaleItemError) {
          auditLogger.info('Shopping stock and price listings skipped as stale.', {
            mutationId,
            itemId,
            expectedVersion: request.expectedVersion,
          });
          return { status: 'stale' };
        }

        auditLogger.error('Shopping stock and price listings failed.', {
          mutationId,
          itemId,
          expectedVersion: request.expectedVersion,
          error: safeErrorMessage(error),
        });
        throw error;
      }
    },
    async applyShoppingListReaddUpdate(itemId, request, mutationId) {
      try {
        const committed = await commitShoppingMutation({
          kind: 'ai_readd',
          itemId,
          expectedVersion: request.expectedVersion,
          expectedPurchased: request.expectedPurchased,
          expectedQuantity: request.expectedQuantity,
          request: {
            purchased: request.purchased,
            ...(request.quantity === undefined ? {} : { quantity: request.quantity }),
            actor: request.actor,
          },
        });
        const response = shoppingListMutationResponse(committed.item, mutationId, committed.activeTrip);

        auditLogger.info('Shopping AI re-add item update committed.', {
          mutationId,
          itemId: response.item.id,
          actor: request.actor,
          expectedVersion: request.expectedVersion,
          appliedVersion: response.item.version,
        });
        shoppingListRealtime?.broadcastItemUpdated(response.item, mutationId);
        await publishTripUpdateIfNeeded(committed.activeTrip, committed.tripUpdated, mutationId);
        shoppingListRealtime?.recordItemMutation?.(response.item, mutationId, 'updated', request.actor);

        return { status: 'updated', response };
      } catch (error) {
        if (error instanceof ShoppingListReaddStaleItemError) {
          auditLogger.info('Shopping AI re-add item update skipped as stale.', {
            mutationId,
            itemId,
            expectedVersion: request.expectedVersion,
          });
          return { status: 'stale' };
        }

        auditLogger.error('Shopping AI re-add item update failed.', {
          mutationId,
          itemId,
          expectedVersion: request.expectedVersion,
          error: safeErrorMessage(error),
        });
        throw error;
      }
    },
  };

  async function commitShoppingMutation(input:
    | { kind: 'created'; request: CreateShoppingListItemRequest }
    | { kind: 'updated'; itemId: number; request: UpdateShoppingListItemRequest }
    | {
      kind: 'stock_price_check';
      itemId: number;
      expectedVersion: number;
      request: Pick<UpdateShoppingListItemRequest, 'storeListings' | 'actor'>;
    }
    | {
      kind: 'ai_readd';
      itemId: number;
      expectedVersion: number;
      expectedPurchased: boolean;
      expectedQuantity: number;
      request: Pick<UpdateShoppingListItemRequest, 'purchased' | 'quantity' | 'actor'>;
    }
    | { kind: 'deleted'; itemId: number; request: DeleteShoppingListItemRequest },
  ): Promise<{ item: ShoppingListItem; activeTrip: ShoppingTripSnapshot | null; tripUpdated: boolean }> {
    if (!transactionRunner || !shoppingTripStore) {
      if (input.kind === 'created') {
        const item = await shoppingListStore.createItem(input.request);
        return { item, activeTrip: await currentActiveTrip(shoppingTripService), tripUpdated: false };
      }
      if (input.kind === 'updated') {
        const item = await shoppingListStore.updateItem(input.itemId, input.request);
        if (!item) throw shoppingItemNotFoundError();
        return { item, activeTrip: await currentActiveTrip(shoppingTripService), tripUpdated: false };
      }
      if (input.kind === 'stock_price_check') {
        const previousItem = await shoppingListStore.fetchItem(input.itemId);
        if (!isCurrentNeededStockPriceCheckItem(previousItem, input.expectedVersion)) {
          throw new StockPriceCheckStaleItemError();
        }
        const item = await shoppingListStore.updateItem(input.itemId, input.request);
        if (!item) throw new StockPriceCheckStaleItemError();
        return { item, activeTrip: await currentActiveTrip(shoppingTripService), tripUpdated: false };
      }
      if (input.kind === 'ai_readd') {
        const previousItem = await shoppingListStore.fetchItem(input.itemId);
        if (!isCurrentShoppingListReaddItem(previousItem, input)) {
          throw new ShoppingListReaddStaleItemError();
        }
        const item = await shoppingListStore.updateItem(input.itemId, input.request);
        if (!item) throw new ShoppingListReaddStaleItemError();
        return { item, activeTrip: await currentActiveTrip(shoppingTripService), tripUpdated: false };
      }
      const item = await shoppingListStore.deleteItem(input.itemId);
      if (!item) throw shoppingItemNotFoundError();
      return { item, activeTrip: await currentActiveTrip(shoppingTripService), tripUpdated: false };
    }

    return transactionRunner(async (database) => {
      const activeTrip = await lockActiveShoppingTrip(database);

      if (input.kind === 'created') {
        if (activeTrip && input.request.purchased === true) {
          throw new HTTPError(409, 'Cannot add a pre-picked item while a shopping trip is active.', 'shopping_trip_create_purchased_not_supported');
        }
        const item = await createShoppingListItem(database, input.request);
        const updatedTrip = activeTrip
          ? await applyShoppingTripItemMutation(database, activeTrip, { kind: 'created', item, actor: input.request.actor })
          : null;
        return { item, activeTrip: updatedTrip, tripUpdated: Boolean(updatedTrip && updatedTrip.version !== activeTrip?.version) };
      }

      const previousItem = await fetchShoppingListItemForUpdate(database, input.itemId);
      if (input.kind === 'stock_price_check') {
        if (!isCurrentNeededStockPriceCheckItem(previousItem, input.expectedVersion)) {
          throw new StockPriceCheckStaleItemError();
        }
        const item = await updateShoppingListItem(database, input.itemId, input.request);
        if (!item) throw new StockPriceCheckStaleItemError();
        const updatedTrip = activeTrip
          ? await applyShoppingTripItemMutation(database, activeTrip, {
            kind: 'updated', previousItem, item, actor: input.request.actor,
          })
          : null;
        return { item, activeTrip: updatedTrip, tripUpdated: Boolean(updatedTrip && updatedTrip.version !== activeTrip?.version) };
      }
      if (input.kind === 'ai_readd') {
        if (!isCurrentShoppingListReaddItem(previousItem, input)) {
          throw new ShoppingListReaddStaleItemError();
        }
        if (activeTrip && input.request.purchased !== undefined) {
          requireShoppingTripActor(input.request.actor);
        }
        const item = await updateShoppingListItem(database, input.itemId, input.request);
        if (!item) throw new ShoppingListReaddStaleItemError();
        const updatedTrip = activeTrip
          ? await applyShoppingTripItemMutation(database, activeTrip, {
            kind: 'updated', previousItem, item, actor: input.request.actor,
          })
          : null;
        return { item, activeTrip: updatedTrip, tripUpdated: Boolean(updatedTrip && updatedTrip.version !== activeTrip?.version) };
      }
      if (!previousItem) throw shoppingItemNotFoundError();

      if (input.kind === 'updated') {
        if (activeTrip && input.request.purchased !== undefined) {
          requireShoppingTripActor(input.request.actor);
        }
        const item = await updateShoppingListItem(database, input.itemId, input.request);
        if (!item) throw shoppingItemNotFoundError();
        const updatedTrip = activeTrip
          ? await applyShoppingTripItemMutation(database, activeTrip, {
            kind: 'updated', previousItem, item, actor: input.request.actor,
          })
          : null;
        return { item, activeTrip: updatedTrip, tripUpdated: Boolean(updatedTrip && updatedTrip.version !== activeTrip?.version) };
      }

      const updatedTrip = activeTrip
        ? await applyShoppingTripItemMutation(database, activeTrip, {
          kind: 'deleted', item: previousItem, actor: input.request.actor,
        })
        : null;
      // The snapshot's shopping_item_id uses ON DELETE SET NULL. Apply the
      // trip transition first so a remaining row can be marked removed while
      // it still has its original shopping-list identity.
      const item = await deleteShoppingListItem(database, input.itemId);
      if (!item) throw shoppingItemNotFoundError();
      return { item, activeTrip: updatedTrip, tripUpdated: Boolean(updatedTrip && updatedTrip.version !== activeTrip?.version) };
    });
  }

  async function publishTripUpdateIfNeeded(
    trip: ShoppingTripSnapshot | null,
    tripUpdated: boolean,
    mutationId: string,
  ): Promise<void> {
    if (!trip || !tripUpdated) return;
    shoppingListRealtime?.broadcastTripUpdated(trip, mutationId);

    try {
      await shoppingLiveActivityDeliveryService?.enqueueEvent({ event: 'update', trip });
    } catch (error) {
      // The list and trip transaction is already committed. Delivery recovery
      // must not turn a successful edit into a false HTTP failure.
      auditLogger.warn('Shopping Live Activity update enqueue failed after list commit.', {
        mutationId,
        tripId: trip.id,
        tripVersion: trip.version,
        error: safeErrorMessage(error),
      });
    }
  }
}

class StockPriceCheckStaleItemError extends Error {
  constructor() {
    super('Shopping item changed, was picked up, or was removed during the stock check.');
    this.name = 'StockPriceCheckStaleItemError';
  }
}

class ShoppingListReaddStaleItemError extends Error {
  constructor() {
    super('Shopping item changed or was removed during AI re-add processing.');
    this.name = 'ShoppingListReaddStaleItemError';
  }
}

function isCurrentNeededStockPriceCheckItem(
  item: ShoppingListItem | null,
  expectedVersion: number,
): item is ShoppingListItem {
  return Boolean(item && item.purchased === false && item.version === expectedVersion);
}

function isCurrentShoppingListReaddItem(
  item: ShoppingListItem | null,
  expected: Pick<ShoppingListReaddUpdateRequest, 'expectedVersion' | 'expectedPurchased' | 'expectedQuantity'>,
): item is ShoppingListItem {
  return Boolean(
    item
    && item.version === expected.expectedVersion
    && item.purchased === expected.expectedPurchased
    && item.quantity === expected.expectedQuantity,
  );
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

function shoppingListMutationResponse(
  item: ShoppingListItem,
  mutationId: string,
  activeTrip: ShoppingTripSnapshot | null,
): ShoppingListMutationResponse {
  return {
    ok: true,
    item,
    activeTrip,
    mutationId,
    generatedAt: new Date().toISOString(),
  };
}

async function currentActiveTrip(
  shoppingTripService: Pick<ShoppingTripService, 'getActiveTrip'> | undefined,
): Promise<ShoppingTripSnapshot | null> {
  return shoppingTripService ? shoppingTripService.getActiveTrip() : null;
}

function shoppingItemNotFoundError(): HTTPError {
  return new HTTPError(404, 'Shopping item was not found.', 'shopping_item_not_found');
}

function requireShoppingTripActor(actor: string | undefined): asserts actor is 'Josh' | 'Mallory' {
  if (actor === 'Josh' || actor === 'Mallory') {
    return;
  }

  throw new HTTPError(
    409,
    'A shopping trip needs Josh or Mallory recorded for a pickup change.',
    'shopping_trip_actor_required',
  );
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

function mutationAuditDetails(
  mutationId: string,
  actor?: string,
): Record<string, unknown> {
  return {
    mutationId,
    ...(actor ? { actor } : {}),
  };
}

function requestAuditDetails(
  request: CreateShoppingListItemRequest | UpdateShoppingListItemRequest,
  mutationId: string,
): Record<string, unknown> {
  return {
    ...mutationAuditDetails(mutationId, request.actor),
    ...(request.name ? { itemName: request.name } : {}),
  };
}

function itemAuditDetails(
  item: ShoppingListItem,
  mutationId: string,
  actor?: string,
): Record<string, unknown> {
  return {
    ...mutationAuditDetails(mutationId, actor),
    itemId: item.id,
    itemName: item.name,
    purchased: item.purchased,
    categoryId: item.categoryId,
    version: item.version,
  };
}
