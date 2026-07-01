import assert from 'node:assert/strict';
import { test } from 'node:test';

import type {
  ShoppingCategory,
  ShoppingListItem,
  ShoppingStore,
} from '../../../../src/contracts.js';
import { HTTPError } from '../../../../src/http/errors.js';
import type { ShoppingListRealtimeBroadcaster } from '../../../../src/shoppingListRealtime.js';
import type { ShoppingListStore } from '../../../../src/shoppingListStore.js';
import { createShoppingListMutationService } from '../../../../src/services/shopping/shoppingListMutationService.js';

test('shopping mutation service creates items and broadcasts successful mutations', async () => {
  const broadcasts: string[] = [];
  const createdItem = shoppingItem({ id: 1, name: 'Whole milk' });
  const service = createShoppingListMutationService({
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

  const response = await service.createItem({ name: 'Whole milk' }, 'mutation-1');

  assert.equal(response.ok, true);
  assert.equal(response.item, createdItem);
  assert.equal(response.mutationId, 'mutation-1');
  assert.deepEqual(broadcasts, ['created:1:mutation-1']);
});

test('shopping mutation service rejects duplicate item creates before writing', async () => {
  const service = createShoppingListMutationService({
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
