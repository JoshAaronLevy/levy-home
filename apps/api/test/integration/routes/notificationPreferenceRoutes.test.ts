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

test('notification preferences can be synced and fetched by device token or device ID', async () => {
  const registered = await routes.postJSON('/api/devices/register', {
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
  });

  const tokenSync = await routes.putJSON('/api/notification-preferences', {
    deviceToken: 'sample-apns-token',
    provider: 'apns',
    environment: 'sandbox',
    preferences: [
      { category: 'garage_opened', isEnabled: false },
      { category: 'garage_left_open', isEnabled: false },
    ],
  });
  const tokenFetch = await routes.getJSON(
    '/api/notification-preferences?deviceToken=sample-apns-token&provider=apns&environment=sandbox',
  );

  assert.equal(tokenSync.ok, true);
  assert.equal(tokenFetch.preferences.length, 5);
  assert.equal(
    tokenFetch.preferences.find((preference: { category: string }) => preference.category === 'garage_opened')
      .isEnabled,
    false,
  );
  assert.equal(
    tokenFetch.preferences.find((preference: { category: string }) => preference.category === 'garage_closed')
      .isEnabled,
    true,
  );

  const deviceSync = await routes.putJSON('/api/notification-preferences', {
    deviceId: registered.device.id,
    preferences: [{ category: 'garage_closed', isEnabled: false }],
  });
  const deviceFetch = await routes.getJSON(`/api/notification-preferences?deviceId=${registered.device.id}`);

  assert.equal(deviceSync.ok, true);
  assert.equal(
    deviceFetch.preferences.find((preference: { category: string }) => preference.category === 'garage_closed')
      .isEnabled,
    false,
  );
});
