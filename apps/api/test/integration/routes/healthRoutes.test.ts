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

test('GET /health returns API health metadata', async () => {
  const response = await routes.getJSON('/health');

  assert.equal(response.ok, true);
  assert.equal(response.service, 'levy-home-api');
  assert.equal(response.homeAssistantMode, 'mock');
  assert.equal(response.registeredDeviceCount, 0);
  assert.equal(response.recentEventCount, 0);
  assert.equal(typeof response.uptimeSeconds, 'number');
});
