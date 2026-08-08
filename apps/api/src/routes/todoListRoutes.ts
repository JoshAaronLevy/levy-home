import { Router } from 'express';

import { asyncHandler } from '../http/asyncHandler.js';
import type { ToDoListStore } from '../repositories/todoListRepository.js';
import type { ToDoListMutationService } from '../services/todo/todoListMutationService.js';
import {
  readOptionalToDoVisibleToUserId,
  readToDoItemId,
  todoMutationIdForRequest,
} from '../services/todo/todoListMutationService.js';
import {
  validateCreateToDoItemBody,
  validateDeleteToDoItemBody,
  validateUpdateToDoItemBody,
} from '../validation/todoValidation.js';

export type ToDoListRouteDependencies = {
  toDoListMutationService: ToDoListMutationService;
  toDoListStore: ToDoListStore;
};

export function createToDoListRoutes(deps: ToDoListRouteDependencies): Router {
  const router = Router();

  router.get('/api/todo-list', asyncHandler(async (req, res) => {
    const visibleToUserId = readOptionalToDoVisibleToUserId(req.query.visibleTo);
    const todoList = await deps.toDoListStore.fetchToDoList(visibleToUserId);

    res.json({
      ok: true,
      ...todoList,
      generatedAt: new Date().toISOString(),
    });
  }));

  router.post('/api/todo-list/items', asyncHandler(async (req, res) => {
    const request = validateCreateToDoItemBody(req.body);
    const mutationId = todoMutationIdForRequest(req, request.mutationId);
    const response = await deps.toDoListMutationService.createItem(request, mutationId);

    res.status(201).json(response);
  }));

  router.patch('/api/todo-list/items/:itemId', asyncHandler(async (req, res) => {
    const itemId = readToDoItemId(req.params.itemId);
    const request = validateUpdateToDoItemBody(req.body);
    const mutationId = todoMutationIdForRequest(req, request.mutationId);
    const response = await deps.toDoListMutationService.updateItem(itemId, request, mutationId);

    res.json(response);
  }));

  router.delete('/api/todo-list/items/:itemId', asyncHandler(async (req, res) => {
    const itemId = readToDoItemId(req.params.itemId);
    const request = validateDeleteToDoItemBody(req.body);
    const mutationId = todoMutationIdForRequest(req, request.mutationId);
    const response = await deps.toDoListMutationService.deleteItem(itemId, mutationId, request);

    res.json(response);
  }));

  return router;
}
