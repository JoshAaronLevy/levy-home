import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { ShoppingListItem } from '../../../src/contracts.js';
import {
  createPostgresShoppingTripStore,
  estimateShoppingItem,
  priceToCents,
} from '../../../src/repositories/shoppingTripRepository.js';

function itemWithListings(
  storeListings: ShoppingListItem['storeListings'],
): Pick<ShoppingListItem, 'storeListings'> {
  return { storeListings };
}

test('priceToCents rounds currency values and rejects invalid prices', () => {
  assert.equal(priceToCents(0), 0);
  assert.equal(priceToCents(1.005), 101);
  assert.equal(priceToCents(2.345), 235);
  assert.equal(priceToCents(-1), null);
  assert.equal(priceToCents(Number.NaN), null);
  assert.equal(priceToCents(Number.POSITIVE_INFINITY), null);
});

test('estimateShoppingItem uses promo before regular and chooses the highest listing', () => {
  const estimate = estimateShoppingItem(itemWithListings([
    {
      storeId: 1,
      storeName: 'Target',
      source: 'target_catalog',
      price: { regular: 5, promo: 4 },
    },
    {
      storeId: 2,
      storeName: 'King Soopers',
      source: 'king_soopers_catalog',
      price: { regular: 4.25 },
    },
  ]));

  assert.deepEqual(estimate, {
    estimatedUnitPriceCents: 425,
    priceSource: 'king_soopers_catalog',
    storeId: 2,
  });
});

test('estimateShoppingItem falls back to regular and preserves missing-price items', () => {
  assert.deepEqual(
    estimateShoppingItem(itemWithListings([
      {
        storeId: 3,
        storeName: 'Costco',
        price: { regular: 3.5, promo: Number.NaN },
      },
    ])),
    {
      estimatedUnitPriceCents: 350,
      priceSource: 'Costco',
      storeId: 3,
    },
  );

  assert.deepEqual(estimateShoppingItem(itemWithListings([])), {
    estimatedUnitPriceCents: null,
    priceSource: null,
    storeId: null,
  });
});

test('shopping trip store requires injected query and transaction boundaries together', () => {
  assert.throws(
    () => createPostgresShoppingTripStore({ database: async () => [] }),
    /must be injected together/,
  );
});
