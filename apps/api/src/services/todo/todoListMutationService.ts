import crypto from 'node:crypto';
import type { Request } from 'express';

import type {
  CreateToDoItemRequest,
  DeleteToDoItemRequest,
  DeleteToDoItemResponse,
  ToDoItem,
  ToDoListMutationResponse,
  UpdateToDoItemRequest,
} from '../../contracts.js';
import { TODO_FAMILY_USER_IDS } from '../../contracts.js';
import { HTTPError } from '../../http/errors.js';
import type { ToDoListStore } from '../../repositories/todoListRepository.js';
import type { ToDoListRealtimeMutationReporter } from '../../todoListRealtime.js';

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
  toDoListRealtime?: ToDoListRealtimeMutationReporter;
  toDoListStore: ToDoListStore;
}): ToDoListMutationService {
  const { toDoListRealtime, toDoListStore } = options;

  return {
    async createItem(request, mutationId) {
      const item = await toDoListStore.createItem(request);
      const response = toDoListMutationResponse(item, mutationId);

      toDoListRealtime?.broadcastItemCreated(item, mutationId);
      recordSharedItemMutation(toDoListRealtime, item, mutationId, 'created', request.actor);

      return response;
    },
    async updateItem(itemId, request, mutationId) {
      const item = await toDoListStore.updateItem(itemId, request);

      if (!item) {
        throw toDoItemNotFoundError();
      }

      const response = toDoListMutationResponse(item, mutationId);

      toDoListRealtime?.broadcastItemUpdated(item, mutationId);
      recordSharedItemMutation(
        toDoListRealtime,
        item,
        mutationId,
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

      toDoListRealtime?.broadcastItemDeleted(item, mutationId);
      recordSharedItemMutation(toDoListRealtime, item, mutationId, 'deleted', request.actor);

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

export function readOptionalToDoVisibleToUserId(value: unknown): number | undefined {
  if (value === undefined) {
    return undefined;
  }

  const id = typeof value === 'string' && value.trim().length > 0 ? Number(value) : Number.NaN;

  if (!Number.isInteger(id) || id < 1) {
    throw new HTTPError(400, 'visibleTo must be a positive integer.', 'invalid_todo_item');
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

function toDoItemNotFoundError(): HTTPError {
  return new HTTPError(404, 'To-do item was not found.', 'todo_item_not_found');
}

function recordSharedItemMutation(
  realtime: ToDoListRealtimeMutationReporter | undefined,
  item: ToDoItem,
  mutationId: string,
  action: 'created' | 'updated' | 'deleted' | 'completed',
  actor?: string,
): void {
  if (!isFamilyToDoItem(item)) {
    return;
  }

  realtime?.recordItemMutation(item, mutationId, action, actor);
}

function isFamilyToDoItem(item: ToDoItem): boolean {
  return TODO_FAMILY_USER_IDS.every((userId) => item.createdFor.includes(userId));
}
