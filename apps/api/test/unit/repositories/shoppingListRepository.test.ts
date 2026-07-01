import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { DatabaseQuery } from '../../../src/db/client.js';
import { fetchShoppingListData } from '../../../src/repositories/shoppingListRepository.js';

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
          created: new Date('2026-06-22T12:00:00.000Z'),
          updated: '2026-06-22T12:30:00Z',
          categoryId: '3',
          image: 'https://example.test/milk.png',
          storeListings: JSON.stringify([
            {
              storeId: 1,
              storeName: 'Target',
              source: 'manual',
              availability: {
                status: 'unknown',
              },
            },
            {
              storeId: 2,
              storeName: 'King Soopers',
              aisle: {
                display: '13:2',
              },
            },
          ]),
        },
      ] as unknown as Row[];
    }

    if (query.includes('FROM shopping_locations')) {
      return [
        { id: 1, name: 'Target', logo: 'target' },
        { id: '2', name: 'Costco', logo: null },
      ] as unknown as Row[];
    }

    if (query.includes('FROM shopping_categories')) {
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
        created: '2026-06-22T12:00:00.000Z',
        updated: '2026-06-22T12:30:00.000Z',
        categoryId: 3,
        image: 'https://example.test/milk.png',
        storeListings: [
          {
            storeId: 1,
            storeName: 'Target',
            source: 'manual',
            availability: {
              status: 'unknown',
            },
          },
          {
            storeId: 2,
            storeName: 'King Soopers',
            aisle: {
              display: '13:2',
            },
          },
        ],
      },
    ],
    stores: [
      { id: 1, name: 'Target', logo: 'target' },
      { id: 2, name: 'Costco' },
    ],
    categories: [{ id: 3, name: 'Dairy' }],
  });
});
