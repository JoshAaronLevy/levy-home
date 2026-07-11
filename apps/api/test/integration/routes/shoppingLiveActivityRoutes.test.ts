import assert from 'node:assert/strict';
import { afterEach, beforeEach, test } from 'node:test';

import { createApp } from '../../../src/app.js';
import { createPostgresShoppingListStore } from '../../../src/repositories/shoppingListRepository.js';
import { createPostgresShoppingLiveActivityStore } from '../../../src/repositories/shoppingLiveActivityRepository.js';
import { createPostgresShoppingTripStore } from '../../../src/repositories/shoppingTripRepository.js';
import { createPostgresPushDeviceRepository } from '../../../src/repositories/pushDeviceRepository.js';
import { createDeviceRegistry } from '../../../src/services/notifications/deviceRegistry.js';
import { createShoppingLiveActivityDeliveryService } from '../../../src/services/shopping/shoppingLiveActivityDeliveryService.js';
import { createRouteTestHarness } from '../../support/routeTestHarness.js';
import { createDisposableShoppingDatabase, type DisposableShoppingDatabase } from '../../support/pgliteDatabase.js';
import { testConfig } from '../../support/testConfig.js';

const routes = createRouteTestHarness();
let disposable: DisposableShoppingDatabase;
let store: ReturnType<typeof createPostgresShoppingLiveActivityStore>;

beforeEach(async () => {
  disposable = await createDisposableShoppingDatabase();
  await disposable.database`
    INSERT INTO push_devices (
      id, lookup_key, token_hash, token, platform, provider, environment, registered_at, last_seen_at
    )
    VALUES ('device-mallory', 'apns:sandbox:mallory', 'ordinary-hash', 'ordinary-token', 'ios', 'apns', 'sandbox', now(), now())
  `;
  const tripStore = createPostgresShoppingTripStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  store = createPostgresShoppingLiveActivityStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  const deliveryService = createShoppingLiveActivityDeliveryService({
    pushSender: {
      async send(request) {
        return {
          registrationId: request.registrationId,
          success: true,
          statusCode: 200,
          isInvalidToken: false,
        };
      },
    },
    shoppingLiveActivityStore: store,
    shoppingTripStore: tripStore,
  });

  await routes.start(createApp({
    config: testConfig,
    deviceRegistry: createDeviceRegistry(createPostgresPushDeviceRepository(disposable.database)),
    shoppingListStore: createPostgresShoppingListStore(disposable.database),
    shoppingTripStore: tripStore,
    shoppingLiveActivityStore: store,
    shoppingLiveActivityDeliveryService: deliveryService,
  }));
});

afterEach(async () => {
  await routes.close();
  await disposable.close();
});

test('ActivityKit token registration returns metadata without exposing its raw token', async () => {
  const token = 'a'.repeat(64);
  const response = await routes.postJSON('/api/shopping-list/live-activities/registrations', {
    pushDeviceId: 'device-mallory',
    resident: 'Mallory',
    environment: 'sandbox',
    tokenType: 'push_to_start',
    token,
  });

  assert.equal(response.ok, true);
  assert.equal(response.registration.token, undefined);
  assert.equal(JSON.stringify(response).includes(token), false);
  assert.deepEqual(
    (await store.findActiveRegistrations({ tokenType: 'push_to_start' })).map((registration) => registration.token),
    [token],
  );
});

test('ActivityKit registration rejects a device environment mismatch', async () => {
  const response = await fetch(`${routes.baseURL()}/api/shopping-list/live-activities/registrations`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      pushDeviceId: 'device-mallory',
      resident: 'Mallory',
      environment: 'production',
      tokenType: 'push_to_start',
      token: 'b'.repeat(64),
    }),
  });

  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), {
    error: 'ActivityKit environment does not match the registered APNs device.',
    code: 'shopping_live_activity_environment_mismatch',
  });
});
