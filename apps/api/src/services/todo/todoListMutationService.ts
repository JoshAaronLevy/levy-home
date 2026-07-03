import crypto from 'node:crypto';
import type { Request } from 'express';

import type {
  CreateToDoItemRequest,
  DeleteToDoItemRequest,
  DeleteToDoItemResponse,
  EventPushStatus,
  ToDoItem,
  ToDoListMutationResponse,
  UpdateToDoItemRequest,
} from '../../contracts.js';
import { HTTPError } from '../../http/errors.js';
import type { ToDoListStore } from '../../repositories/todoListRepository.js';
import type { ListMutationPushAction, NotificationService } from '../notifications/notificationService.js';

export type ToDoListMutationService = {
  createItem: (request: CreateToDoItemRequest, mutationId: string) => Promise<ToDoListMutationResponse>;
  updateItem: (
    itemId: number,
    request: UpdateToDoItemRequest,
    mutationId: string,
  ) => Promise<ToDoListMutationResponse>;
  deleteItem: (
    itemId: number,
    mutationId: string,
    request?: DeleteToDoItemRequest,
  ) => Promise<DeleteToDoItemResponse>;
};

export function createToDoListMutationService(options: {
  notificationService?: Pick<NotificationService, 'sendListMutationPush'>;
  toDoListStore: ToDoListStore;
}): ToDoListMutationService {
  const { notificationService, toDoListStore } = options;

  return {
    async createItem(request, mutationId) {
      const item = await toDoListStore.createItem(request);
      const response = toDoListMutationResponse(item, mutationId);

      response.push = await sendToDoListMutationPush(notificationService, item, 'created', request.actor);

      return response;
    },
    async updateItem(itemId, request, mutationId) {
      const item = await toDoListStore.updateItem(itemId, request);

      if (!item) {
        throw toDoItemNotFoundError();
      }

      const response = toDoListMutationResponse(item, mutationId);

      response.push = await sendToDoListMutationPush(
        notificationService,
        item,
        request.status === 'completed' ? 'completed' : 'updated',
        request.actor,
      );

      return response;
    },
    async deleteItem(itemId, mutationId, request = {}) {
      const item = await toDoListStore.deleteItem(itemId);

      if (!item) {
        throw toDoItemNotFoundError();
      }

      const response: DeleteToDoItemResponse = {
        ok: true,
        itemId,
        item,
        mutationId,
        generatedAt: new Date().toISOString(),
      };

      response.push = await sendToDoListMutationPush(notificationService, item, 'deleted', request.actor);

      return response;
    },
  };
}

export function readToDoItemId(value: unknown): number {
  const id = typeof value === 'string' && value.trim().length > 0 ? Number(value) : Number.NaN;

  if (!Number.isInteger(id) || id < 1) {
    throw new HTTPError(400, 'itemId must be a positive integer.', 'invalid_todo_item');
  }

  return id;
}

export function todoMutationIdForRequest(req: Request, bodyMutationId?: string): string {
  const headerMutationId = req.get('X-Levy-Home-Mutation-ID')?.trim();

  return bodyMutationId ?? (headerMutationId && headerMutationId.length > 0 ? headerMutationId : crypto.randomUUID());
}

function toDoListMutationResponse(item: ToDoItem, mutationId: string): ToDoListMutationResponse {
  return {
    ok: true,
    item,
    mutationId,
    generatedAt: new Date().toISOString(),
  };
}

async function sendToDoListMutationPush(
  notificationService: Pick<NotificationService, 'sendListMutationPush'> | undefined,
  item: ToDoItem,
  action: ListMutationPushAction,
  actor?: string,
): Promise<EventPushStatus | undefined> {
  if (!notificationService) {
    return undefined;
  }

  try {
    return await notificationService.sendListMutationPush({
      listType: 'todo',
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

function toDoItemNotFoundError(): HTTPError {
  return new HTTPError(404, 'To-do item was not found.', 'todo_item_not_found');
}
