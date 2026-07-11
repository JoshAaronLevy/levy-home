import crypto from 'node:crypto';
import type { Request } from 'express';

import type {
  CreateShoppingListItemRequest,
  DeleteShoppingListItemRequest,
  DeleteShoppingListItemResponse,
  EventPushStatus,
  ShoppingListItem,
  ShoppingListMutationResponse,
  ShoppingTripSnapshot,
  UpdateShoppingListItemRequest,
} from '../../contracts.js';
import { HTTPError } from '../../http/errors.js';
import { logger as defaultLogger, safeErrorMessage, type Logger } from '../../observability/logger.js';
import type { ShoppingListStore } from '../../repositories/shoppingListRepository.js';
import type { ListMutationPushAction, NotificationService } from '../notifications/notificationService.js';
import type { ShoppingListRealtimeBroadcaster } from '../../shoppingListRealtime.js';
import type { ShoppingTripService } from './shoppingTripService.js';

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
};

export function createShoppingListMutationService(options: {
  logger?: Logger;
  notificationService?: Pick<NotificationService, 'sendListMutationPush'>;
  shoppingListRealtime?: ShoppingListRealtimeBroadcaster;
  shoppingListStore: ShoppingListStore;
  shoppingTripService?: Pick<ShoppingTripService, 'getActiveTrip'>;
}): ShoppingListMutationService {
  const auditLogger = options.logger ?? defaultLogger;
  const { notificationService, shoppingListRealtime, shoppingListStore, shoppingTripService } = options;

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
        const item = await shoppingListStore.createItem(request);
        const response = shoppingListMutationResponse(
          item,
          mutationId,
          await currentActiveTrip(shoppingTripService),
        );

        auditLogger.info('Shopping list create committed.', itemAuditDetails(item, mutationId, request.actor));
        shoppingListRealtime?.broadcastItemCreated(item, mutationId);
        response.push = await sendShoppingListMutationPush(notificationService, item, 'created', request.actor);
        auditLogger.info('Shopping list create completed.', {
          ...itemAuditDetails(item, mutationId, request.actor),
          ...pushAuditDetails(response.push),
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
      const item = await shoppingListStore.deleteItem(itemId);

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
        activeTrip: await currentActiveTrip(shoppingTripService),
        mutationId,
        generatedAt: new Date().toISOString(),
      };

      auditLogger.info('Shopping list delete committed.', itemAuditDetails(item, mutationId, request.actor));
      shoppingListRealtime?.broadcastItemDeleted(itemId, mutationId);
      response.push = await sendShoppingListMutationPush(notificationService, item, 'deleted', request.actor);
      auditLogger.info('Shopping list delete completed.', {
        ...itemAuditDetails(item, mutationId, request.actor),
        ...pushAuditDetails(response.push),
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
        const item = await shoppingListStore.updateItem(itemId, request);

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
          await currentActiveTrip(shoppingTripService),
        );

        auditLogger.info('Shopping list update committed.', itemAuditDetails(item, mutationId, request.actor));
        shoppingListRealtime?.broadcastItemUpdated(item, mutationId);
        response.push = await sendShoppingListMutationPush(
          notificationService,
          item,
          request.purchased === true ? 'completed' : 'updated',
          request.actor,
        );
        auditLogger.info('Shopping list update completed.', {
          ...itemAuditDetails(item, mutationId, request.actor),
          ...pushAuditDetails(response.push),
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

async function sendShoppingListMutationPush(
  notificationService: Pick<NotificationService, 'sendListMutationPush'> | undefined,
  item: ShoppingListItem,
  action: ListMutationPushAction,
  actor?: string,
): Promise<EventPushStatus | undefined> {
  if (!notificationService) {
    return undefined;
  }

  try {
    return await notificationService.sendListMutationPush({
      listType: 'shopping',
      action,
      itemName: item.name,
      actor,
    });
  } catch (error) {
    return {
      attempted: false,
      skipped: true,
      reason: error instanceof Error ? error.message : String(error),
    };
  }
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

function pushAuditDetails(push: EventPushStatus | undefined): Record<string, unknown> {
  if (!push) {
    return {
      pushStatus: 'not_configured',
    };
  }

  return {
    pushAttempted: push.attempted,
    pushSkipped: push.skipped,
    pushTicketCount: push.ticketCount ?? push.sentNotificationCount,
    pushFailedCount: push.failedNotificationCount,
    ...(push.reason ? { pushReason: push.reason } : {}),
  };
}
