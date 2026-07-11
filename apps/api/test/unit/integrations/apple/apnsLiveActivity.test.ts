import assert from 'node:assert/strict';
import { test } from 'node:test';

import { buildShoppingLiveActivityAPNsRequest } from '../../../../src/integrations/apple/apnsPushSender.js';
import { buildShoppingLiveActivityPayload } from '../../../../src/services/shopping/shoppingLiveActivityDeliveryService.js';

const trip = {
  id: 'fca7f84a-8527-4a58-90b5-a78e4cde5b16',
  status: 'active' as const,
  startedBy: 'Josh' as const,
  startedAt: '2026-07-11T18:00:00.000Z',
  endedBy: null,
  endedAt: null,
  pickedUpCount: 2,
  remainingCount: 3,
  totalItemCount: 5,
  estimatedTotalCents: 1275,
  pricedPickedItemCount: 2,
  unpricedPickedItemCount: 0,
  currencyCode: 'USD',
  version: 4,
};

test('ActivityKit APNs requests use the required path, topic, type, priority, expiration, and start payload', () => {
  const payload = buildShoppingLiveActivityPayload('start', trip, 1_752_259_201);
  const request = buildShoppingLiveActivityAPNsRequest('com.levyhome.app', {
    registrationId: 'registration-1',
    token: 'a'.repeat(64),
    environment: 'sandbox',
    payload,
    priority: 10,
    expiration: 1_752_288_000,
  });

  assert.equal(request.endpoint, 'https://api.sandbox.push.apple.com');
  assert.equal(request.path, `/3/device/${'a'.repeat(64)}`);
  assert.equal(request.topic, 'com.levyhome.app.push-type.liveactivity');
  assert.equal(request.pushType, 'liveactivity');
  assert.equal(request.priority, 10);
  assert.equal(request.expiration, 1_752_288_000);
  assert.deepEqual(JSON.parse(request.payload), {
    aps: {
      timestamp: 1_752_259_201,
      event: 'start',
      'content-state': {
        status: 'active',
        pickedUpCount: 2,
        remainingCount: 3,
        totalItemCount: 5,
        estimatedTotalCents: 1275,
        pricedPickedItemCount: 2,
        unpricedPickedItemCount: 0,
        currencyCode: 'USD',
        stateVersion: 4,
        updatedAtEpochSeconds: 1_752_259_201,
      },
      'attributes-type': 'ShoppingTripActivityAttributes',
      attributes: {
        tripID: trip.id,
        startedByName: 'Josh',
        startedAtEpochSeconds: 1_783_792_800,
      },
      'input-push-token': 1,
      alert: {
        title: 'Shopping trip started',
        body: 'Josh started a shopping trip.',
      },
    },
  });
});

test('ActivityKit update and end payloads use lower priority content semantics and final dismissal', () => {
  const update = buildShoppingLiveActivityPayload('update', trip, 1_752_259_202);
  const end = buildShoppingLiveActivityPayload('end', { ...trip, status: 'completed', version: 5 }, 1_752_259_203);

  assert.equal(update.aps.event, 'update');
  assert.equal(update.aps['attributes-type'], undefined);
  assert.equal(update.aps['input-push-token'], undefined);
  assert.equal(end.aps.event, 'end');
  assert.equal(end.aps['dismissal-date'], 1_752_260_103);
  assert.equal(end.aps['content-state'].status, 'completed');
});
