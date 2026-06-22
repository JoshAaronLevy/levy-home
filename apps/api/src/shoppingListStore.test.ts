import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { DatabaseQuery } from './dbClient.js';
import { fetchShoppingListData } from './shoppingListStore.js';

test('fetchShoppingListData maps shopping list tables into API contracts', async () => {
  const database: DatabaseQuery = async <Row extends Record<string, unknown> = Record<string, unknown>>(
    strings: TemplateStringsArray,
  ): Promise<Row[]> => {
    const query = strings.join('');

    if (query.includes('FROM shopping_list')) {
      return [
        {
          id: 42,
          name: 'Whole milk',
          brand: 'Horizon',
          quantity: null,
          notes: 'Half gallon',
          purchased: null,
          createdAt: new Date('2026-06-22T12:00:00.000Z'),
          updatedAt: '2026-06-22T12:30:00Z',
          storeIds: '[1, "2", "not-an-id"]',
          categoryId: '3',
        },
      ] as unknown as Row[];
    }

    if (query.includes('FROM stores')) {
      return [
        { id: 1, name: 'Target', logo: 'target' },
        { id: '2', name: 'Costco', logo: null },
      ] as unknown as Row[];
    }

    if (query.includes('FROM categories')) {
      return [{ id: 3, name: 'Dairy' }] as unknown as Row[];
    }

    throw new Error(`Unexpected query: ${query}`);
  };

  const data = await fetchShoppingListData(database);

  assert.deepEqual(data, {
    items: [
      {
        id: 42,
        name: 'Whole milk',
        brand: 'Horizon',
        quantity: 1,
        notes: 'Half gallon',
        purchased: false,
        createdAt: '2026-06-22T12:00:00.000Z',
        updatedAt: '2026-06-22T12:30:00.000Z',
        storeIds: [1, 2],
        categoryId: 3,
      },
    ],
    stores: [
      { id: 1, name: 'Target', logo: 'target' },
      { id: 2, name: 'Costco' },
    ],
    categories: [{ id: 3, name: 'Dairy' }],
  });
});
