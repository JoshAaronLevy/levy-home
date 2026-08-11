import assert from 'node:assert/strict';
import { afterEach, beforeEach, test } from 'node:test';

import { createApp } from '../../../src/app.js';
import type {
  CreateToDoItemRequest,
  ToDoItem,
  UpdateToDoItemRequest,
} from '../../../src/contracts.js';
import type { ToDoListStore } from '../../../src/repositories/todoListRepository.js';
import { createRouteTestHarness } from '../../support/routeTestHarness.js';
import { testConfig } from '../../support/testConfig.js';

const routes = createRouteTestHarness();

beforeEach(async () => {
  await routes.start(createApp({ config: testConfig }));
});

afterEach(async () => {
  await routes.close();
});

test('GET, POST, and PATCH /api/todo-list use the configured to-do list store', async () => {
  let capturedCreate: CreateToDoItemRequest | undefined;
  let capturedUpdate: UpdateToDoItemRequest | undefined;
  let capturedVisibleToUserId: number | undefined;

  await routes.restart(
    createApp({
      config: testConfig,
      toDoListStore: todoListStore({
        async fetchToDoList(visibleToUserId) {
          capturedVisibleToUserId = visibleToUserId;

          return {
            items: [
              todoItem({
                id: 9,
                name: 'Schedule dentist',
                locationDisplayText: 'Cherry Creek Dental',
              }),
            ],
            categories: [
              {
                id: 1,
                name: 'Appointments',
                updatedAt: '2026-07-03T12:00:00.000Z',
              },
            ],
            locations: [],
          };
        },
        async createItem(request) {
          capturedCreate = request;

          return todoItem({
            id: 10,
            name: request.name,
            locationIds: request.locationIds ?? [],
            locationDisplayText: 'No location',
            createdBy: request.createdBy ?? undefined,
          });
        },
        async updateItem(id, request) {
          capturedUpdate = request;

          return todoItem({
            id,
            name: 'Schedule dentist',
            status: request.status ?? 'open',
            createdFor: request.createdFor ?? [1, 2],
          });
        },
      }),
    }),
  );

  const list = await routes.getJSON('/api/todo-list?visibleTo=2');
  const created = await routes.postJSON('/api/todo-list/items', {
    name: 'Book summer camp',
    locationIds: [],
    notes: 'Bring the registration packet.',
    alerts: [{ recipient: 'both', timing: 'morningOf' }],
    subtasks: [{ id: 'subtask-1', title: 'Print forms', assignedTo: [1] }],
    createdBy: 2,
    createdFor: [1, 2],
    actor: 'Mallory',
  });
  const patchResponse = await fetch(`${routes.baseURL()}/api/todo-list/items/9`, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      status: 'completed',
      notes: null,
      alerts: null,
      subtasks: [],
      createdFor: [2],
      actor: 'Josh',
    }),
  });
  const updated = await patchResponse.json();

  assert.equal(list.ok, true);
  assert.equal(capturedVisibleToUserId, 2);
  assert.equal(list.items[0].name, 'Schedule dentist');
  assert.equal(list.categories[0].id, 1);
  assert.deepEqual(capturedCreate, {
    name: 'Book summer camp',
    status: 'open',
    locationIds: [],
    notes: 'Bring the registration packet.',
    alerts: [{ recipient: 'both', timing: 'morningOf' }],
    subtasks: [{ id: 'subtask-1', title: 'Print forms', assignedTo: [1] }],
    createdBy: 2,
    createdFor: [1, 2],
    actor: 'Mallory',
  });
  assert.equal(created.ok, true);
  assert.equal(created.item.name, 'Book summer camp');
  assert.equal(patchResponse.ok, true);
  assert.deepEqual(capturedUpdate, {
    status: 'completed',
    notes: null,
    alerts: null,
    subtasks: [],
    createdFor: [2],
    actor: 'Josh',
  });
  assert.equal(updated.ok, true);
  assert.equal(updated.item.status, 'completed');
  assert.deepEqual(updated.item.createdFor, [2]);
});

function todoListStore(overrides: Partial<ToDoListStore>): ToDoListStore {
  return {
    async fetchToDoList() {
      return {
        items: [],
        categories: [],
        locations: [],
      };
    },
    async fetchItem() {
      return null;
    },
    async createItem() {
      throw new Error('Unexpected createItem call.');
    },
    async updateItem() {
      return null;
    },
    async deleteItem() {
      return null;
    },
    ...overrides,
  };
}

function todoItem(overrides: Partial<ToDoItem> = {}): ToDoItem {
  return {
    id: 1,
    name: 'Sample to-do',
    status: 'open',
    locationIds: [],
    locationDisplayText: 'No location',
    alerts: [],
    subtasks: [],
    createdFor: [1, 2],
    createdDate: '2026-07-03T12:00:00.000Z',
    ...overrides,
  };
}
