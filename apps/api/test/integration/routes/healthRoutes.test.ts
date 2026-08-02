import assert from 'node:assert/strict';
import { afterEach, beforeEach, test } from 'node:test';

import { createApp } from '../../../src/app.js';
import type { DeviceRegistry } from '../../../src/services/notifications/deviceRegistry.js';
import { createRouteTestHarness } from '../../support/routeTestHarness.js';
import { testConfig } from '../../support/testConfig.js';

const routes = createRouteTestHarness();

beforeEach(async () => {
  await routes.start(createApp({ config: testConfig }));
});

afterEach(async () => {
  await routes.close();
});

test('GET /health returns API health metadata', async () => {
  const response = await routes.getJSON('/health');

  assert.equal(response.ok, true);
  assert.equal(response.service, 'levy-home-api');
  assert.equal(response.homeAssistantMode, 'mock');
  assert.equal(response.notificationPersistenceMode, 'memory');
  assert.equal(response.registeredDeviceCount, 0);
  assert.equal(response.recentEventCount, 0);
  assert.equal(typeof response.uptimeSeconds, 'number');
});

test('GET /ready returns dependency readiness without requiring optional APNs credentials', async () => {
  const response = await routes.getJSON('/ready');

  assert.equal(response.ok, true);
  assert.equal(response.checks.activity.persistenceMode, 'memory');
  assert.equal(response.checks.notificationPersistence.mode, 'memory');
  assert.equal(response.checks.notificationPersistence.registeredDeviceCount, 0);
  assert.equal(response.checks.homeAssistant.mode, 'mock');
  assert.equal(response.checks.apns.configured, false);
  assert.equal(response.checks.apns.required, false);
  assert.equal(response.checks.shoppingStockPriceChecks.enabled, false);
  assert.equal(response.checks.shoppingStockPriceChecks.checks.codexRuntime.code, 'site_scope_unavailable');
});

test('GET /health remains live when notification persistence count is unavailable', async () => {
  await routes.restart(createApp({
    config: testConfig,
    deviceRegistry: failingCountDeviceRegistry(),
    notificationPersistenceMode: 'postgres',
  }));

  const health = await routes.getJSON('/health');
  const readinessResponse = await fetch(`${routes.baseURL()}/ready`);
  const readiness = await readinessResponse.json() as { ok: boolean; checks: Record<string, any> };

  assert.equal(health.ok, true);
  assert.equal(health.registeredDeviceCount, null);
  assert.equal(readinessResponse.status, 503);
  assert.equal(readiness.ok, false);
  assert.equal(readiness.checks.notificationPersistence.code, 'notification_persistence_unavailable');
});

function failingCountDeviceRegistry(): DeviceRegistry {
  return {
    async count() {
      throw new Error('relation "push_devices" does not exist');
    },
    async getDevice() {
      return undefined;
    },
    async listDevices() {
      return [];
    },
    async invalidateDevice() {},
    async registerDevice() {
      throw new Error('not implemented');
    },
  };
}
