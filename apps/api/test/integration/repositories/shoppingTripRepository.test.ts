import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { test } from 'node:test';

import type { DatabaseQuery } from '../../../src/db/client.js';
import {
  createPostgresShoppingTripStore,
  ShoppingTripHasNoNeededItemsError,
} from '../../../src/repositories/shoppingTripRepository.js';
import { createDisposableShoppingDatabase } from '../../support/pgliteDatabase.js';

type SeedItem = {
  name: string;
  quantity?: number;
  purchased?: boolean;
  storeListings?: unknown[];
};

async function seedShoppingItem(database: DatabaseQuery, item: SeedItem): Promise<number> {
  const [row] = await database<{ id: number }>`
    INSERT INTO shopping_list (name, quantity, purchased, store_listings)
    VALUES (
      ${item.name},
      ${item.quantity ?? 1},
      ${item.purchased ?? false},
      ${JSON.stringify(item.storeListings ?? [])}::jsonb
    )
    RETURNING id
  `;

  assert.ok(row);
  return row.id;
}

test('migration and repository persist snapshots, prices, and aggregates', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());

  const promoItemId = await seedShoppingItem(disposable.database, {
    name: 'Milk',
    storeListings: [{
      storeId: 1,
      storeName: 'Target',
      source: 'target_catalog',
      price: { regular: 5, promo: 4 },
    }],
  });
  await seedShoppingItem(disposable.database, {
    name: 'Yogurt',
    quantity: 2,
    storeListings: [{
      storeId: 2,
      storeName: 'King Soopers',
      price: { regular: 2.345 },
    }],
  });
  await seedShoppingItem(disposable.database, {
    name: 'Coffee',
    storeListings: [
      { storeId: 1, source: 'target_catalog', price: { regular: 8, promo: 3 } },
      { storeId: 3, source: 'costco_catalog', price: { regular: 4.25 } },
    ],
  });
  await seedShoppingItem(disposable.database, { name: 'Bananas' });
  await seedShoppingItem(disposable.database, { name: 'Already bought', purchased: true });

  const store = createPostgresShoppingTripStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  const started = await store.startTrip({
    startedBy: 'Josh',
    mutationId: randomUUID(),
  });

  assert.equal(started.status, 'active');
  assert.equal(started.pickedUpCount, 0);
  assert.equal(started.remainingCount, 4);
  assert.equal(started.totalItemCount, 4);
  assert.equal(started.estimatedTotalCents, 0);

  const items = await store.fetchTripItems(started.id);
  assert.deepEqual(
    items.map((item) => ({
      name: item.name,
      quantity: item.quantity,
      cents: item.estimatedUnitPriceCents,
      source: item.priceSource,
      storeId: item.storeId,
    })),
    [
      { name: 'Milk', quantity: 1, cents: 400, source: 'target_catalog', storeId: 1 },
      { name: 'Yogurt', quantity: 2, cents: 235, source: 'King Soopers', storeId: 2 },
      { name: 'Coffee', quantity: 1, cents: 425, source: 'costco_catalog', storeId: 3 },
      { name: 'Bananas', quantity: 1, cents: null, source: null, storeId: null },
    ],
  );

  const restartedStore = createPostgresShoppingTripStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  assert.equal((await restartedStore.fetchActiveTrip())?.id, started.id);

  await disposable.database`
    UPDATE shopping_trip_items
    SET state = 'picked_up', picked_up_by = 'Josh', picked_up_at = now()
    WHERE trip_id = ${started.id}
  `;
  const picked = await restartedStore.fetchTrip(started.id);

  assert.ok(picked);
  assert.equal(picked.pickedUpCount, 4);
  assert.equal(picked.remainingCount, 0);
  assert.equal(picked.estimatedTotalCents, 1295);
  assert.equal(picked.pricedPickedItemCount, 3);
  assert.equal(picked.unpricedPickedItemCount, 1);
  assert.equal(items.find((item) => item.shoppingItemId === promoItemId)?.name, 'Milk');

  const completed = await restartedStore.completeTrip({
    tripId: started.id,
    endedBy: 'Mallory',
    mutationId: randomUUID(),
    summaryRecipient: 'Josh',
  });
  assert.equal(completed?.status, 'completed');
  assert.equal(completed?.endedBy, 'Mallory');
  assert.equal(completed?.version, 2);
  assert.equal(await restartedStore.fetchActiveTrip(), null);
});

test('database constraint rejects a second active trip', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  await seedShoppingItem(disposable.database, { name: 'Milk' });
  const store = createPostgresShoppingTripStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });

  await store.startTrip({ startedBy: 'Josh', mutationId: randomUUID() });
  await assert.rejects(
    store.startTrip({ startedBy: 'Mallory', mutationId: randomUUID() }),
    (error: unknown) => (
      error instanceof Error
      && /shopping_trips_one_active_idx|unique constraint/i.test(error.message)
    ),
  );

  const [count] = await disposable.database<{ count: string }>`
    SELECT COUNT(*)::text AS count FROM shopping_trips
  `;
  assert.equal(count?.count, '1');
});

test('deleting a shopping-list row preserves its historical trip snapshot', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  const shoppingItemId = await seedShoppingItem(disposable.database, { name: 'Eggs' });
  const store = createPostgresShoppingTripStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  const trip = await store.startTrip({ startedBy: 'Josh', mutationId: randomUUID() });

  await disposable.database`DELETE FROM shopping_list WHERE id = ${shoppingItemId}`;
  const [snapshot] = await store.fetchTripItems(trip.id);

  assert.ok(snapshot);
  assert.equal(snapshot.shoppingItemId, null);
  assert.equal(snapshot.name, 'Eggs');
  assert.equal(snapshot.quantity, 1);
});

test('an induced snapshot failure rolls back both the trip and its items', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  await seedShoppingItem(disposable.database, { name: 'Valid first snapshot' });
  await seedShoppingItem(disposable.database, { name: '   ' });
  const store = createPostgresShoppingTripStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });

  await assert.rejects(
    store.startTrip({ startedBy: 'Josh', mutationId: randomUUID() }),
    /blank name/,
  );

  const [counts] = await disposable.database<{ trips: string; items: string }>`
    SELECT
      (SELECT COUNT(*) FROM shopping_trips)::text AS trips,
      (SELECT COUNT(*) FROM shopping_trip_items)::text AS items
  `;
  assert.deepEqual(counts, { trips: '0', items: '0' });
});

test('starting with no needed items rolls back and returns a domain error', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  await seedShoppingItem(disposable.database, { name: 'Purchased', purchased: true });
  const store = createPostgresShoppingTripStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });

  await assert.rejects(
    store.startTrip({ startedBy: 'Mallory', mutationId: randomUUID() }),
    ShoppingTripHasNoNeededItemsError,
  );

  const [count] = await disposable.database<{ count: number }>`
    SELECT COUNT(*)::integer AS count FROM shopping_trips
  `;
  assert.equal(count?.count, 0);
});
