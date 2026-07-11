import assert from 'node:assert/strict';
import { test } from 'node:test';

import type {
  ShoppingCategory,
  ShoppingListItem,
  ShoppingStore,
  ShoppingTripSnapshot,
} from '../../../../src/contracts.js';
import { HTTPError } from '../../../../src/http/errors.js';
import type { ShoppingListStore } from '../../../../src/repositories/shoppingListRepository.js';
import type { ShoppingListRealtimeBroadcaster } from '../../../../src/shoppingListRealtime.js';
import { createShoppingListMutationService } from '../../../../src/services/shopping/shoppingListMutationService.js';
import type { ListMutationPushPayload } from '../../../../src/services/notifications/notificationService.js';
import type { Logger } from '../../../../src/observability/logger.js';

test('shopping mutation service creates items, broadcasts successful mutations, and sends actor push', async () => {
  const broadcasts: string[] = [];
  const logs: RecordedLogEntry[] = [];
  const pushes: ListMutationPushPayload[] = [];
  const createdItem = shoppingItem({ id: 1, name: 'Whole milk' });
  const service = createShoppingListMutationService({
    logger: recordingLogger(logs),
    notificationService: recordingNotificationService(pushes),
    shoppingListRealtime: recordingRealtimeBroadcaster(broadcasts),
    shoppingListStore: shoppingStore({
      async createItem() {
        return createdItem;
      },
      async findItemByName() {
        return null;
      },
    }),
  });

  const response = await service.createItem({ name: 'Whole milk', actor: 'Josh' }, 'mutation-1');

  assert.equal(response.ok, true);
  assert.equal(response.item, createdItem);
  assert.equal(response.mutationId, 'mutation-1');
  assert.equal(response.push?.attempted, true);
  assert.deepEqual(broadcasts, ['created:1:mutation-1']);
  assert.deepEqual(logs.map((entry) => entry.message), [
    'Shopping list create committed.',
    'Shopping list create completed.',
  ]);
  assert.deepEqual(logs[0].details, {
    mutationId: 'mutation-1',
    actor: 'Josh',
    itemId: 1,
    itemName: 'Whole milk',
    purchased: false,
    categoryId: null,
    version: undefined,
  });
  assert.deepEqual(pushes, [
    {
      listType: 'shopping',
      action: 'created',
      itemName: 'Whole milk',
      actor: 'Josh',
    },
  ]);
});

test('shopping mutation service rejects duplicate item creates before writing', async () => {
  const service = createShoppingListMutationService({
    logger: silentLogger,
    shoppingListStore: shoppingStore({
      async createItem() {
        throw new Error('createItem should not be called for duplicates.');
      },
      async findItemByName() {
        return shoppingItem({ id: 2, name: 'Eggs' });
      },
    }),
  });

  await assert.rejects(
    () => service.createItem({ name: 'Eggs' }, 'mutation-2'),
    (error) =>
      error instanceof HTTPError &&
      error.statusCode === 409 &&
      error.code === 'duplicate_shopping_item',
  );
});

test('shopping mutation service updates items and broadcasts the updated item', async () => {
  const broadcasts: string[] = [];
  const updatedItem = shoppingItem({ id: 3, name: 'Greek yogurt', purchased: true });
  const service = createShoppingListMutationService({
    logger: silentLogger,
    shoppingListRealtime: recordingRealtimeBroadcaster(broadcasts),
    shoppingListStore: shoppingStore({
      async fetchItem() {
        return shoppingItem({ id: 3, name: 'Greek yogurt' });
      },
      async findItemByName() {
        return updatedItem;
      },
      async updateItem() {
        return updatedItem;
      },
    }),
  });

  const response = await service.updateItem(3, { purchased: true }, 'mutation-3');

  assert.equal(response.item, updatedItem);
  assert.deepEqual(broadcasts, ['updated:3:mutation-3']);
});

test('shopping mutation service returns not found for missing deletes', async () => {
  const service = createShoppingListMutationService({
    logger: silentLogger,
    shoppingListStore: shoppingStore({
      async deleteItem() {
        return null;
      },
    }),
  });

  await assert.rejects(
    () => service.deleteItem(42, 'mutation-4'),
    (error) =>
      error instanceof HTTPError &&
      error.statusCode === 404 &&
      error.code === 'shopping_item_not_found',
  );
});

function shoppingStore(overrides: Partial<ShoppingListStore>): ShoppingListStore {
  return {
    async fetchShoppingList() {
      return {
        items: [],
        stores: [],
        categories: [],
      };
    },
    async fetchItem() {
      return null;
    },
    async findItemByName() {
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

const silentLogger: Logger = {
  debug() {},
  error() {},
  info() {},
  warn() {},
};

type RecordedLogEntry = {
  level: keyof Logger;
  message: string;
  details?: Record<string, unknown>;
};

function recordingLogger(entries: RecordedLogEntry[]): Logger {
  const record = (level: keyof Logger) => (message: string, details?: Record<string, unknown>) => {
    entries.push({ level, message, details });
  };

  return {
    debug: record('debug'),
    error: record('error'),
    info: record('info'),
    warn: record('warn'),
  };
}

function recordingRealtimeBroadcaster(broadcasts: string[]): ShoppingListRealtimeBroadcaster {
  return {
    broadcastItemCreated(item, mutationId) {
      broadcasts.push(`created:${item.id}:${mutationId}`);
    },
    broadcastItemUpdated(item, mutationId) {
      broadcasts.push(`updated:${item.id}:${mutationId}`);
    },
    broadcastItemDeleted(itemId, mutationId) {
      broadcasts.push(`deleted:${itemId}:${mutationId}`);
    },
    broadcastStoresChanged(stores: ShoppingStore[], mutationId: string) {
      broadcasts.push(`stores:${stores.length}:${mutationId}`);
    },
    broadcastCategoriesChanged(categories: ShoppingCategory[], mutationId: string) {
      broadcasts.push(`categories:${categories.length}:${mutationId}`);
    },
    broadcastTripStarted(trip: ShoppingTripSnapshot, mutationId: string) {
      broadcasts.push(`trip-started:${trip.id}:${mutationId}`);
    },
    broadcastTripUpdated(trip: ShoppingTripSnapshot, mutationId: string) {
      broadcasts.push(`trip-updated:${trip.id}:${mutationId}`);
    },
    broadcastTripEnded(trip: ShoppingTripSnapshot, mutationId: string) {
      broadcasts.push(`trip-ended:${trip.id}:${mutationId}`);
    },
  };
}

function recordingNotificationService(pushes: ListMutationPushPayload[]) {
  return {
    async sendListMutationPush(payload: ListMutationPushPayload) {
      pushes.push(payload);

      return {
        attempted: true,
        skipped: false,
        sentNotificationCount: 1,
      };
    },
  };
}

function shoppingItem(overrides: Partial<ShoppingListItem> = {}): ShoppingListItem {
  return {
    id: 1,
    name: 'Sample item',
    quantity: 1,
    purchased: false,
    created: '2026-07-01T12:00:00.000Z',
    updated: '2026-07-01T12:00:00.000Z',
    categoryId: null,
    storeListings: [],
    ...overrides,
  };
}
