import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { ToDoItem } from '../../../../src/contracts.js';
import { HTTPError } from '../../../../src/http/errors.js';
import type { ToDoListStore } from '../../../../src/repositories/todoListRepository.js';
import type { ToDoListRealtimeSessionRecorder } from '../../../../src/todoListRealtime.js';
import { createToDoListMutationService } from '../../../../src/services/todo/todoListMutationService.js';

test('to-do mutation service records created items for session push instead of sending immediate pushes', async () => {
  const recordings: string[] = [];
  const createdItem = todoItem({ id: 7, name: 'Schedule dentist' });
  const service = createToDoListMutationService({
    toDoListRealtime: recordingRealtimeSessionRecorder(recordings),
    toDoListStore: todoListStore({
      async createItem() {
        return createdItem;
      },
    }),
  });

  const response = await service.createItem({ name: 'Schedule dentist', actor: 'Josh' }, 'mutation-1');

  assert.equal(response.ok, true);
  assert.equal(response.item, createdItem);
  assert.equal(response.mutationId, 'mutation-1');
  assert.equal(response.push, undefined);
  assert.deepEqual(recordings, ['created:7:mutation-1:Josh']);
});

test('to-do mutation service updates items without recording session pushes', async () => {
  const recordings: string[] = [];
  const updatedItem = todoItem({ id: 9, name: 'Book camp', status: 'completed' });
  const service = createToDoListMutationService({
    toDoListRealtime: recordingRealtimeSessionRecorder(recordings),
    toDoListStore: todoListStore({
      async updateItem() {
        return updatedItem;
      },
    }),
  });

  const response = await service.updateItem(9, { status: 'completed', actor: 'Mallory' }, 'mutation-2');

  assert.equal(response.item, updatedItem);
  assert.equal(response.push, undefined);
  assert.deepEqual(recordings, []);
});

test('to-do mutation service returns not found for missing deletes', async () => {
  const service = createToDoListMutationService({
    toDoListStore: todoListStore({
      async deleteItem() {
        return null;
      },
    }),
  });

  await assert.rejects(
    () => service.deleteItem(42, 'mutation-3'),
    (error) =>
      error instanceof HTTPError &&
      error.statusCode === 404 &&
      error.code === 'todo_item_not_found',
  );
});

function recordingRealtimeSessionRecorder(recordings: string[]): ToDoListRealtimeSessionRecorder {
  return {
    recordItemCreated(item, mutationId, actor) {
      recordings.push(`created:${item.id}:${mutationId}:${actor ?? ''}`);
    },
    async flushPendingSessionForViewerId() {
      return undefined;
    },
  };
}

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
    createdDate: '2026-07-03T12:00:00.000Z',
    ...overrides,
  };
}
