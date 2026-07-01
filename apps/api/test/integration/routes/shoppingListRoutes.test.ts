import assert from 'node:assert/strict';
import { afterEach, beforeEach, test } from 'node:test';

import { createApp } from '../../../src/app.js';
import { createRouteTestHarness } from '../../support/routeTestHarness.js';
import { testConfig } from '../../support/testConfig.js';

const routes = createRouteTestHarness();

beforeEach(async () => {
  await routes.start(createApp({ config: testConfig }));
});

afterEach(async () => {
  await routes.close();
});

test('GET /api/shopping-list returns shopping data from the configured store', async () => {
  await routes.restart(
    createApp({
      config: testConfig,
      shoppingListStore: {
        async fetchShoppingList() {
          return {
            items: [
              {
                id: 1,
                name: 'Whole milk',
                brand: 'Horizon',
                quantity: 2,
                notes: 'Half gallon',
                purchased: false,
                created: '2026-06-22T12:00:00.000Z',
                updated: '2026-06-22T12:30:00.000Z',
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
                ],
                categoryId: 2,
              },
            ],
            stores: [{ id: 1, name: 'Target', logo: 'target' }],
            categories: [{ id: 2, name: 'Dairy' }],
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
      },
    }),
  );

  const response = await routes.getJSON('/api/shopping-list');

  assert.equal(response.ok, true);
  assert.equal(typeof response.generatedAt, 'string');
  assert.deepEqual(response.items, [
    {
      id: 1,
      name: 'Whole milk',
      brand: 'Horizon',
      quantity: 2,
      notes: 'Half gallon',
      purchased: false,
      created: '2026-06-22T12:00:00.000Z',
      updated: '2026-06-22T12:30:00.000Z',
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
      ],
      categoryId: 2,
    },
  ]);
  assert.deepEqual(response.stores, [{ id: 1, name: 'Target', logo: 'target' }]);
  assert.deepEqual(response.categories, [{ id: 2, name: 'Dairy' }]);
});

test('GET /api/shopping-list/products/search returns Kroger product candidates', async () => {
  let capturedQuery: string | undefined;

  await routes.restart(
    createApp({
      config: testConfig,
      krogerProductSearchRunner: async (query) => {
        capturedQuery = query;

        return {
          ok: true,
          query: query ?? 'Pasta Sauce',
          generatedAt: '2026-06-23T12:00:00.000Z',
          productStatusCode: 200,
          products: [
            {
              productId: '0085002473501',
              upc: '0085002473501',
              productPageURI: '/p/carbone-tomato-basil-sauce-24-oz/0085002473501',
              aisles: [],
              brand: 'Carbone',
              name: 'Carbone Tomato Basil Sauce 24 oz',
              description: 'Carbone Tomato Basil Sauce 24 oz',
              image: 'https://www.kroger.com/product/images/large/front/0085002473501',
              storeListings: [
                {
                  storeId: 2,
                  storeName: 'King Soopers',
                  krogerLocationId: '62000008',
                  aisle: {
                    display: '15:3',
                  },
                  price: {
                    regular: 9.29,
                    promo: 6.99,
                  },
                  inventory: {
                    stockLevel: 'LOW',
                  },
                },
              ],
            },
          ],
        };
      },
    }),
  );

  const response = await routes.getJSON('/api/shopping-list/products/search?term=Carbone%20Tomato%20Basil');

  assert.equal(capturedQuery, 'Carbone Tomato Basil');
  assert.equal(response.ok, true);
  assert.equal(response.products[0].storeListings[0].aisle.display, '15:3');
  assert.equal(response.products[0].storeListings[0].price.promo, 6.99);
  assert.equal(response.products[0].storeListings[0].inventory.stockLevel, 'LOW');
});
