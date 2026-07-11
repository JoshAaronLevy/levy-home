import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { test } from 'node:test';

import { createPostgresShoppingTripStore } from '../../../src/repositories/shoppingTripRepository.js';
import { createPostgresShoppingTripSummaryStore } from '../../../src/repositories/shoppingTripSummaryRepository.js';
import { createShoppingTripSummaryDeliveryService } from '../../../src/services/shopping/shoppingTripSummaryDeliveryService.js';
import { createDisposableShoppingDatabase } from '../../support/pgliteDatabase.js';

test('trip completion persists one counterpart summary and dispatcher sends it once', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  await disposable.database`
    INSERT INTO push_devices (
      id, lookup_key, token_hash, token, platform, provider, environment, device_name, registered_at, last_seen_at
    )
    VALUES ('device-mallory', 'apns:sandbox:mallory', 'mallory-hash', 'mallory-token', 'ios', 'apns', 'sandbox', 'Mallory iPhone', now(), now())
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
  const completed = await tripStore.completeTrip({
    tripId: trip.id,
    endedBy: 'Josh',
    mutationId: randomUUID(),
  });
  assert.equal(completed?.status, 'completed');

  const summaryStore = createPostgresShoppingTripSummaryStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  const sent: string[] = [];
  const service = createShoppingTripSummaryDeliveryService({
    logger: { debug() {}, error() {}, info() {}, warn() {} },
    shoppingTripSummaryStore: summaryStore,
    deviceRegistry: {
      async getDevice(deviceId) {
        return deviceId === 'device-mallory'
          ? {
            id: deviceId,
            token: 'mallory-token',
            platform: 'ios',
            provider: 'apns',
            environment: 'sandbox',
            deviceName: 'Mallory iPhone',
            registeredAt: new Date().toISOString(),
            lastSeenAt: new Date().toISOString(),
          }
          : undefined;
      },
    },
    notificationPreferenceStore: { async isNotificationEnabled() { return true; } },
    pushSender: {
      async send(request) {
        sent.push(`${request.device.id}:${request.body}`);
        return { provider: 'apns', deviceId: request.device.id, success: true, apnsId: 'summary-apns-id', isInvalidToken: false };
      },
    },
  });

  await service.processPending();
  await service.processPending();

  assert.deepEqual(sent, ['device-mallory:Josh ended the trip: 0 picked up • 1 left']);
  const [row] = await disposable.database<{ status: unknown; apnsId: unknown }>`
    SELECT status, apns_id AS "apnsId"
    FROM shopping_trip_summary_deliveries
    WHERE trip_id = ${trip.id} AND push_device_id = 'device-mallory'
  `;
  assert.deepEqual(row, { status: 'sent', apnsId: 'summary-apns-id' });
});

test('summary delivery is terminally skipped when the recipient disabled shopping notifications', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  await disposable.database`
    INSERT INTO push_devices (
      id, lookup_key, token_hash, token, platform, provider, environment, device_name, registered_at, last_seen_at
    )
    VALUES ('device-josh', 'apns:sandbox:josh', 'josh-hash', 'josh-token', 'ios', 'apns', 'sandbox', 'Josh iPhone', now(), now())
  `;
  await disposable.database`
    INSERT INTO shopping_list (name, quantity, purchased, store_listings)
    VALUES ('Bread', 1, false, '[]'::jsonb)
  `;
  const tripStore = createPostgresShoppingTripStore({ database: disposable.database, transactionRunner: disposable.transactionRunner });
  const trip = await tripStore.startTrip({ startedBy: 'Mallory', mutationId: randomUUID() });
  await tripStore.completeTrip({ tripId: trip.id, endedBy: 'Mallory', mutationId: randomUUID() });
  const store = createPostgresShoppingTripSummaryStore({ database: disposable.database, transactionRunner: disposable.transactionRunner });
  let sendCount = 0;
  const service = createShoppingTripSummaryDeliveryService({
    logger: { debug() {}, error() {}, info() {}, warn() {} },
    shoppingTripSummaryStore: store,
    deviceRegistry: { async getDevice() { return { id: 'device-josh', token: 'josh-token', platform: 'ios', provider: 'apns', environment: 'sandbox', deviceName: 'Josh iPhone', registeredAt: '', lastSeenAt: '' }; } },
    notificationPreferenceStore: { async isNotificationEnabled() { return false; } },
    pushSender: { async send() { sendCount += 1; throw new Error('should not send'); } },
  });

  await service.processPending();
  assert.equal(sendCount, 0);
  const [row] = await disposable.database<{ status: unknown }>`SELECT status FROM shopping_trip_summary_deliveries WHERE trip_id = ${trip.id}`;
  assert.equal(row?.status, 'skipped');
});
