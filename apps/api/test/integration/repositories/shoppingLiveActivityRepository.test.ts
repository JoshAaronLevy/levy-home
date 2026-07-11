import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { test } from 'node:test';

import { createPostgresShoppingLiveActivityStore } from '../../../src/repositories/shoppingLiveActivityRepository.js';
import { createPostgresShoppingTripStore } from '../../../src/repositories/shoppingTripRepository.js';
import { buildShoppingLiveActivityPayload } from '../../../src/services/shopping/shoppingLiveActivityDeliveryService.js';
import { createDisposableShoppingDatabase } from '../../support/pgliteDatabase.js';

const firstToken = 'a'.repeat(64);
const rotatedToken = 'b'.repeat(64);
const updateToken = 'c'.repeat(64);

test('ActivityKit registrations rotate safely and durable deliveries claim once', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  await disposable.database`
    INSERT INTO push_devices (
      id, lookup_key, token_hash, token, platform, provider, environment, registered_at, last_seen_at
    )
    VALUES ('device-josh', 'apns:sandbox:ordinary', 'ordinary-hash', 'ordinary-token', 'ios', 'apns', 'sandbox', now(), now())
  `;
  await disposable.database`
    INSERT INTO shopping_list (name, quantity, purchased, store_listings)
    VALUES ('Milk', 1, false, '[]'::jsonb)
  `;
  const tripStore = createPostgresShoppingTripStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  const trip = await tripStore.startTrip({ startedBy: 'Josh', mutationId: randomUUID() });
  const store = createPostgresShoppingLiveActivityStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });

  const first = await store.register({
    pushDeviceId: 'device-josh',
    resident: 'Josh',
    environment: 'sandbox',
    tokenType: 'push_to_start',
    token: firstToken,
  });
  const rotated = await store.register({
    pushDeviceId: 'device-josh',
    resident: 'Josh',
    environment: 'sandbox',
    tokenType: 'push_to_start',
    token: rotatedToken,
  });

  assert.equal('token' in first, false);
  assert.notEqual(first.id, rotated.id);
  assert.deepEqual(
    (await store.findActiveRegistrations({ tokenType: 'push_to_start' })).map((registration) => registration.token),
    [rotatedToken],
  );

  const startPayload = buildShoppingLiveActivityPayload('start', trip, 1_752_259_200);
  const ambiguousStart = await store.enqueueDelivery({
    tripId: trip.id,
    registrationId: rotated.id,
    eventType: 'start',
    stateVersion: trip.version,
    payload: startPayload,
  });
  const [claimedStart] = await store.claimDueDeliveries(10);
  assert.equal(claimedStart?.id, ambiguousStart.id);
  await store.markDeliveryAmbiguous(ambiguousStart.id, 'connection reset before APNs response', new Date(0));
  // A duplicate start can create another Activity, so an ambiguous start stays
  // out of the retry queue until an update token proves the Activity exists.
  assert.deepEqual(await store.claimDueDeliveries(10), []);
  await store.reconcileAmbiguousStartDeliveries({ tripId: trip.id, pushDeviceId: 'device-josh' });
  const reconciledStart = await store.enqueueDelivery({
    tripId: trip.id,
    registrationId: rotated.id,
    eventType: 'start',
    stateVersion: trip.version,
    payload: startPayload,
  });
  assert.equal(reconciledStart.status, 'sent');

  const updateRegistration = await store.register({
    pushDeviceId: 'device-josh',
    resident: 'Josh',
    environment: 'sandbox',
    tokenType: 'activity_update',
    token: updateToken,
    tripId: trip.id,
  });
  const payload = buildShoppingLiveActivityPayload('update', trip, 1_752_259_201);
  const delivery = await store.enqueueDelivery({
    tripId: trip.id,
    registrationId: updateRegistration.id,
    eventType: 'update',
    stateVersion: trip.version,
    payload,
  });
  const duplicate = await store.enqueueDelivery({
    tripId: trip.id,
    registrationId: updateRegistration.id,
    eventType: 'update',
    stateVersion: trip.version,
    payload,
  });

  assert.equal(delivery.id, duplicate.id);
  const [claimed] = await store.claimDueDeliveries(10);
  assert.ok(claimed);
  assert.equal(claimed.registration.token, updateToken);
  assert.equal(claimed.payload.aps.event, 'update');
  assert.equal(claimed.status, 'sending');

  await store.markDeliverySent(claimed.id, 'apns-id-1');
  assert.deepEqual(await store.claimDueDeliveries(10), []);

  const diagnostics = await store.getDiagnostics();
  assert.equal(diagnostics.activePushToStartRegistrationCount, 1);
  assert.equal(diagnostics.activeUpdateRegistrationCount, 1);
  assert.equal(diagnostics.latestDelivery?.id, claimed.id);
  assert.equal(diagnostics.latestDelivery?.stateVersion, trip.version);
  assert.equal(diagnostics.latestDelivery?.status, 'sent');
  assert.equal('payload' in (diagnostics.latestDelivery ?? {}), false);

  const [acceptedRegistration] = await disposable.database<{ lastAcceptedStateVersion: unknown; lastAcceptedAt: unknown }>`
    SELECT
      last_accepted_state_version AS "lastAcceptedStateVersion",
      last_accepted_at AS "lastAcceptedAt"
    FROM shopping_live_activity_registrations
    WHERE id = ${updateRegistration.id}
  `;
  assert.equal(acceptedRegistration?.lastAcceptedStateVersion, trip.version);
  assert.ok(acceptedRegistration?.lastAcceptedAt);
});
