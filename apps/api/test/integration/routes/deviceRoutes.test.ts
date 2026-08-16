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

test('POST /api/devices/register stores APNs registrations by provider and environment', async () => {
  const sandbox = await routes.postJSON('/api/devices/register', {
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
    appVersion: '0.1.0',
    deviceName: 'Josh iPhone',
  });
  const production = await routes.postJSON('/api/devices/register', {
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'production',
  });

  assert.equal(sandbox.ok, true);
  assert.equal(sandbox.registeredDeviceCount, 1);
  assert.equal(sandbox.device.provider, 'apns');
  assert.equal(sandbox.device.environment, 'sandbox');
  assert.equal(sandbox.device.token, undefined);
  assert.equal(production.registeredDeviceCount, 2);
  assert.notEqual(sandbox.device.id, production.device.id);
});

test('POST /api/devices/register preserves legacy Expo push token registration', async () => {
  const response = await routes.postJSON('/api/devices/register', {
    pushToken: 'ExponentPushToken[sample]',
    platform: 'ios',
  });

  assert.equal(response.ok, true);
  assert.equal(response.registeredDeviceCount, 1);
  assert.equal(response.device.provider, 'expo');
  assert.equal(response.device.platform, 'ios');
});

test('POST /api/devices/register can skip the active-device count for modern clients', async () => {
  const response = await routes.postJSON('/api/devices/register', {
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
    includeDeviceCount: false,
  });

  assert.equal(response.ok, true);
  assert.equal(response.registeredDeviceCount, undefined);
  assert.equal(response.device.id.startsWith('apns-sandbox-'), true);
});

test('POST /api/devices/register rejects ambiguous APNs registrations', async () => {
  const response = await fetch(`${routes.baseURL()}/api/devices/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      token: 'sample-apns-token',
      platform: 'ios',
      provider: 'apns',
    }),
  });
  const body = (await response.json()) as { error: string; code: string };

  assert.equal(response.status, 400);
  assert.equal(body.code, 'missing_apns_environment');
});
