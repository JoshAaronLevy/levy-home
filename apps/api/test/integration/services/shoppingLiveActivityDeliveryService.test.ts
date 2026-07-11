import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { test } from 'node:test';

import { createPostgresShoppingLiveActivityStore } from '../../../src/repositories/shoppingLiveActivityRepository.js';
import { createPostgresShoppingTripStore } from '../../../src/repositories/shoppingTripRepository.js';
import { createShoppingLiveActivityDeliveryService } from '../../../src/services/shopping/shoppingLiveActivityDeliveryService.js';
import { createDisposableShoppingDatabase } from '../../support/pgliteDatabase.js';

test('an ambiguous remote start is retained without sending a duplicate start', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  await disposable.database`
    INSERT INTO push_devices (
      id, lookup_key, token_hash, token, platform, provider, environment, registered_at, last_seen_at
    )
    VALUES ('device-mallory', 'apns:sandbox:ordinary', 'ordinary-hash', 'ordinary-token', 'ios', 'apns', 'sandbox', now(), now())
  `;
  await disposable.database`
    INSERT INTO shopping_list (name, quantity, purchased, store_listings)
    VALUES ('Milk', 1, false, '[]'::jsonb)
  `;

  const tripStore = createPostgresShoppingTripStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  const activityStore = createPostgresShoppingLiveActivityStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  const trip = await tripStore.startTrip({ startedBy: 'Josh', mutationId: randomUUID() });
  await activityStore.register({
    pushDeviceId: 'device-mallory',
    resident: 'Mallory',
    environment: 'sandbox',
    tokenType: 'push_to_start',
    token: 'a'.repeat(64),
  });

  let sendCount = 0;
  const service = createShoppingLiveActivityDeliveryService({
    logger: {
      debug() {},
      error() {},
      info() {},
      warn() {},
    },
    pushSender: {
      async send() {
        sendCount += 1;
        throw new Error('connection closed before APNs returned a response');
      },
    },
    shoppingLiveActivityStore: activityStore,
    shoppingTripStore: tripStore,
  });

  await service.enqueueEvent({ event: 'start', trip });
  // enqueueEvent starts processing in the background. Running it again waits
  // for the same pass, then proves the ambiguous start is not claimed again.
  await service.processPending();
  await service.processPending();

  assert.equal(sendCount, 1);
});
