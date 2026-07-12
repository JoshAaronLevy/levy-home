import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { test } from 'node:test';

import { createPostgresShoppingListStore } from '../../../src/repositories/shoppingListRepository.js';
import { createPostgresShoppingTripStore } from '../../../src/repositories/shoppingTripRepository.js';
import { createShoppingListMutationService } from '../../../src/services/shopping/shoppingListMutationService.js';
import { createDisposableShoppingDatabase } from '../../support/pgliteDatabase.js';

test('active-trip mutations atomically maintain trip state without per-item counterpart pushes', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  await disposable.database`
    INSERT INTO shopping_list (name, quantity, purchased, store_listings)
    VALUES
      ('Milk', 1, false, ${JSON.stringify([{ storeId: 2, source: 'King Soopers', price: { regular: 3.5 } }])}::jsonb),
      ('Apples', 2, false, ${JSON.stringify([{ storeId: 2, source: 'King Soopers', price: { promo: 1.25 } }])}::jsonb)
  `;

  const shoppingListStore = createPostgresShoppingListStore(disposable.database);
  const shoppingTripStore = createPostgresShoppingTripStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  const trip = await shoppingTripStore.startTrip({ startedBy: 'Josh', mutationId: randomUUID() });
  const realtimeVersions: number[] = [];
  const activityVersions: number[] = [];
  const service = createShoppingListMutationService({
    logger: {
      debug() {},
      error() {},
      info() {},
      warn() {},
    },
    shoppingListRealtime: {
      broadcastItemCreated() {},
      broadcastItemUpdated() {},
      broadcastItemDeleted() {},
      broadcastStoresChanged() {},
      broadcastCategoriesChanged() {},
      broadcastTripStarted() {},
      broadcastTripUpdated(updatedTrip) { realtimeVersions.push(updatedTrip.version); },
      broadcastTripEnded() {},
    },
    shoppingListStore,
    shoppingTripStore,
    transactionRunner: disposable.transactionRunner,
    shoppingLiveActivityDeliveryService: {
      async enqueueEvent({ trip: updatedTrip }) {
        activityVersions.push(updatedTrip.version);
        return [];
      },
    },
  });
  const milk = await shoppingListStore.findItemByName('Milk');
  const apples = await shoppingListStore.findItemByName('Apples');
  assert.ok(milk && apples);

  await assert.rejects(
    service.updateItem(milk.id, { purchased: true }, randomUUID()),
    { code: 'shopping_trip_actor_required' },
  );
  assert.equal((await shoppingListStore.fetchItem(milk.id))?.purchased, false);
  assert.equal((await shoppingTripStore.fetchActiveTrip())?.version, trip.version);

  const picked = await service.updateItem(milk.id, { purchased: true, actor: 'Josh' }, randomUUID());
  assert.equal(picked.activeTrip?.pickedUpCount, 1);
  assert.equal(picked.activeTrip?.remainingCount, 1);
  assert.equal(picked.activeTrip?.estimatedTotalCents, 350);
  assert.equal(picked.activeTrip?.version, trip.version + 1);
  assert.ok((picked.activeTrip?.activityUpdatedAtEpochSeconds ?? 0) > 0);

  const repeatedPick = await service.updateItem(milk.id, { purchased: true, actor: 'Josh' }, randomUUID());
  assert.equal(repeatedPick.activeTrip?.version, picked.activeTrip?.version);

  const unpicked = await service.updateItem(milk.id, { purchased: false, actor: 'Mallory' }, randomUUID());
  assert.equal(unpicked.activeTrip?.pickedUpCount, 0);
  assert.equal(unpicked.activeTrip?.remainingCount, 2);
  assert.ok(
    (unpicked.activeTrip?.activityUpdatedAtEpochSeconds ?? 0)
      > (picked.activeTrip?.activityUpdatedAtEpochSeconds ?? 0),
  );

  const created = await service.createItem({ name: 'Bread', quantity: 1, actor: 'Mallory' }, randomUUID());
  assert.equal(created.activeTrip?.remainingCount, 3);
  assert.ok(
    (created.activeTrip?.activityUpdatedAtEpochSeconds ?? 0)
      > (unpicked.activeTrip?.activityUpdatedAtEpochSeconds ?? 0),
  );

  const deletedRemaining = await service.deleteItem(apples.id, randomUUID(), { actor: 'Josh' });
  assert.equal(deletedRemaining.activeTrip?.remainingCount, 2);

  const repickedMilk = await service.updateItem(milk.id, { purchased: true, actor: 'Josh' }, randomUUID());
  const deletedPicked = await service.deleteItem(milk.id, randomUUID(), { actor: 'Josh' });
  assert.equal(deletedPicked.activeTrip?.pickedUpCount, 1);
  assert.equal(deletedPicked.activeTrip?.version, repickedMilk.activeTrip?.version);
  assert.equal(await shoppingListStore.fetchItem(milk.id), null);

  assert.deepEqual(realtimeVersions, activityVersions);
  assert.deepEqual(realtimeVersions, [...realtimeVersions].sort((first, second) => first - second));
});

test('a trip-snapshot failure rolls back the corresponding global Shopping mutation', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  await disposable.database`
    INSERT INTO shopping_list (name, quantity, purchased, store_listings)
    VALUES ('Milk', 1, false, '[]'::jsonb)
  `;
  const shoppingListStore = createPostgresShoppingListStore(disposable.database);
  const shoppingTripStore = createPostgresShoppingTripStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  const trip = await shoppingTripStore.startTrip({ startedBy: 'Josh', mutationId: randomUUID() });
  const milk = await shoppingListStore.findItemByName('Milk');
  assert.ok(milk);
  const service = createShoppingListMutationService({
    logger: { debug() {}, error() {}, info() {}, warn() {} },
    shoppingListStore,
    shoppingTripStore,
    transactionRunner: disposable.transactionRunner,
  });

  // Route validation rejects blank names before this point. Calling the domain
  // service directly induces the snapshot CHECK failure after the global row
  // update has been attempted, proving both writes share the transaction.
  await assert.rejects(service.updateItem(milk.id, { name: '', actor: 'Josh' }, randomUUID()));

  assert.equal((await shoppingListStore.fetchItem(milk.id))?.name, 'Milk');
  assert.equal((await shoppingTripStore.fetchActiveTrip())?.version, trip.version);
});

test('a Live Activity enqueue failure does not turn a committed Shopping edit into an HTTP failure', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  await disposable.database`
    INSERT INTO shopping_list (name, quantity, purchased, store_listings)
    VALUES ('Milk', 1, false, '[]'::jsonb)
  `;
  const shoppingListStore = createPostgresShoppingListStore(disposable.database);
  const shoppingTripStore = createPostgresShoppingTripStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  await shoppingTripStore.startTrip({ startedBy: 'Josh', mutationId: randomUUID() });
  const milk = await shoppingListStore.findItemByName('Milk');
  assert.ok(milk);
  const warnings: string[] = [];
  const service = createShoppingListMutationService({
    logger: {
      debug() {},
      error() {},
      info() {},
      warn(message) { warnings.push(message); },
    },
    shoppingListStore,
    shoppingTripStore,
    transactionRunner: disposable.transactionRunner,
    shoppingLiveActivityDeliveryService: {
      async enqueueEvent() {
        throw new Error('delivery queue temporarily unavailable');
      },
    },
  });

  const response = await service.updateItem(
    milk.id,
    { purchased: true, actor: 'Josh' },
    randomUUID(),
  );

  assert.equal(response.item.purchased, true);
  assert.equal((await shoppingListStore.fetchItem(milk.id))?.purchased, true);
  assert.deepEqual(warnings, ['Shopping Live Activity update enqueue failed after list commit.']);
});
