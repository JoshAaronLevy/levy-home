import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { afterEach, beforeEach, test } from 'node:test';

import { createApp } from '../../../src/app.js';
import type { DatabaseQuery } from '../../../src/db/client.js';
import { createPostgresShoppingListStore } from '../../../src/repositories/shoppingListRepository.js';
import { createPostgresShoppingTripStore } from '../../../src/repositories/shoppingTripRepository.js';
import type { ShoppingListRealtimeBroadcaster } from '../../../src/shoppingListRealtime.js';
import { createRouteTestHarness } from '../../support/routeTestHarness.js';
import {
  createDisposableShoppingDatabase,
  type DisposableShoppingDatabase,
} from '../../support/pgliteDatabase.js';
import { testConfig } from '../../support/testConfig.js';

const routes = createRouteTestHarness();
let disposable: DisposableShoppingDatabase;
let broadcasts: string[];

beforeEach(async () => {
  disposable = await createDisposableShoppingDatabase();
  broadcasts = [];
  await routes.start(createShoppingTripApp());
});

afterEach(async () => {
  await routes.close();
  await disposable.close();
});

test('active-trip reads and Shopping snapshots return null before a trip starts', async () => {
  const active = await routes.getJSON('/api/shopping-list/trip');
  const snapshot = await routes.getJSON('/api/shopping-list');

  assert.equal(active.ok, true);
  assert.equal(active.activeTrip, null);
  assert.equal(snapshot.activeTrip, null);
});

test('start is durable, idempotent, and converges second-resident starts', async () => {
  await seedShoppingItem(disposable.database, 'Milk');
  const mutationId = randomUUID();

  const created = await routes.postJSON('/api/shopping-list/trip/start', {
    actor: 'Josh',
    mutationId,
  });
  const replay = await routes.postJSON('/api/shopping-list/trip/start', {
    actor: 'Josh',
    mutationId,
  });
  const concurrentResident = await routes.postJSON('/api/shopping-list/trip/start', {
    actor: 'Mallory',
    mutationId: randomUUID(),
  });

  assert.equal(created.trip.status, 'active');
  assert.equal(created.activeTrip.id, created.trip.id);
  assert.equal(replay.trip.id, created.trip.id);
  assert.equal(concurrentResident.trip.id, created.trip.id);
  assert.deepEqual(broadcasts, [`started:${created.trip.id}:${mutationId}`]);

  const shoppingSnapshot = await routes.getJSON('/api/shopping-list');
  assert.equal(shoppingSnapshot.activeTrip.id, created.trip.id);

  await routes.restart(createShoppingTripApp());
  const activeAfterRestart = await routes.getJSON('/api/shopping-list/trip');

  assert.equal(activeAfterRestart.activeTrip.id, created.trip.id);
  assert.equal(activeAfterRestart.activeTrip.startedBy, 'Josh');
});

test('start rejects an empty needed list with the documented domain error', async () => {
  const response = await fetch(`${routes.baseURL()}/api/shopping-list/trip/start`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ actor: 'Mallory', mutationId: randomUUID() }),
  });

  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), {
    error: 'A shopping trip requires at least one needed item.',
    code: 'shopping_trip_has_no_needed_items',
  });

  const unknownActor = await fetch(`${routes.baseURL()}/api/shopping-list/trip/start`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ actor: 'Sam', mutationId: randomUUID() }),
  });

  assert.equal(unknownActor.status, 400);
  assert.deepEqual(await unknownActor.json(), {
    error: 'actor must be Josh or Mallory.',
    code: 'invalid_shopping_trip',
  });
});

test('end is durable and idempotent, and a wrong trip id is rejected', async () => {
  await seedShoppingItem(disposable.database, 'Eggs');
  const started = await routes.postJSON('/api/shopping-list/trip/start', {
    actor: 'Josh',
    mutationId: randomUUID(),
  });
  const endMutationId = randomUUID();
  const ended = await routes.postJSON('/api/shopping-list/trip/end', {
    tripId: started.trip.id,
    actor: 'Mallory',
    mutationId: endMutationId,
    summaryRecipient: 'Josh',
  });
  const replay = await routes.postJSON('/api/shopping-list/trip/end', {
    tripId: started.trip.id,
    actor: 'Mallory',
    mutationId: endMutationId,
    summaryRecipient: 'Josh',
  });

  assert.equal(ended.trip.status, 'completed');
  assert.equal(ended.activeTrip, null);
  assert.equal(replay.trip.id, ended.trip.id);
  assert.deepEqual(broadcasts, [
    `started:${started.trip.id}:${started.mutationId}`,
    `ended:${started.trip.id}:${endMutationId}`,
  ]);

  const wrongTripResponse = await fetch(`${routes.baseURL()}/api/shopping-list/trip/end`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      tripId: randomUUID(),
      actor: 'Josh',
      mutationId: randomUUID(),
    }),
  });

  assert.equal(wrongTripResponse.status, 404);
  assert.deepEqual(await wrongTripResponse.json(), {
    error: 'Shopping trip was not found.',
    code: 'shopping_trip_not_found',
  });
});

function createShoppingTripApp() {
  const shoppingTripStore = createPostgresShoppingTripStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });

  return createApp({
    config: testConfig,
    shoppingListStore: createPostgresShoppingListStore(disposable.database),
    shoppingListRealtime: recordingRealtimeBroadcaster(broadcasts),
    shoppingTripStore,
  });
}

async function seedShoppingItem(database: DatabaseQuery, name: string): Promise<void> {
  await database`
    INSERT INTO shopping_list (name, quantity, purchased, store_listings)
    VALUES (${name}, 1, false, '[]'::jsonb)
  `;
}

function recordingRealtimeBroadcaster(events: string[]): ShoppingListRealtimeBroadcaster {
  return {
    broadcastItemCreated() {},
    broadcastItemUpdated() {},
    broadcastItemDeleted() {},
    broadcastStoresChanged() {},
    broadcastCategoriesChanged() {},
    broadcastTripStarted(trip, mutationId) {
      events.push(`started:${trip.id}:${mutationId}`);
    },
    broadcastTripUpdated() {},
    broadcastTripEnded(trip, mutationId) {
      events.push(`ended:${trip.id}:${mutationId}`);
    },
  };
}
