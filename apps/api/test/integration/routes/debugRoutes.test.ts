import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import type { AddressInfo } from 'node:net';
import { afterEach, beforeEach, test } from 'node:test';

import { createApp } from '../../../src/app.js';
import type { PushSender } from '../../../src/integrations/apple/apnsPushSender.js';
import { FakePushSender } from '../../support/fakePushSender.js';
import { createRouteTestHarness } from '../../support/routeTestHarness.js';
import { testConfig } from '../../support/testConfig.js';

const routes = createRouteTestHarness();

beforeEach(async () => {
  await routes.start(createApp({ config: testConfig }));
});

afterEach(async () => {
  await routes.close();
});

test('GET /api/debug/kroger/products runs the Kroger product diagnostic lookup', async () => {
  let capturedQuery: string | undefined;

  await routes.restart(
    createApp({
      config: testConfig,
      krogerProductDiagnosticRunner: async (query) => {
        capturedQuery = query;

        return {
          ok: true,
          query: query ?? 'Soy Milk',
          generatedAt: '2026-06-23T12:00:00.000Z',
          stage: 'product_search',
          outputFilePath: '/tmp/kroger-product-response.json',
          normalizedOutputFilePath: '/tmp/kroger-products-normalized.json',
          tokenStatusCode: 200,
          productStatusCode: 200,
          products: [],
        };
      },
    }),
  );

  const response = await routes.getJSON('/api/debug/kroger/products?term=Soy%20Milk');

  assert.equal(capturedQuery, 'Soy Milk');
  assert.equal(response.ok, true);
  assert.equal(response.query, 'Soy Milk');
  assert.equal(response.outputFilePath, '/tmp/kroger-product-response.json');
  assert.equal(response.normalizedOutputFilePath, '/tmp/kroger-products-normalized.json');
  assert.equal(response.productStatusCode, 200);
});

test('POST /api/debug/send-test-push sends APNs test pushes with provider-neutral counts', async () => {
  const pushSender = new FakePushSender();

  await withTestServer(pushSender, async () => {
    await routes.postJSON('/api/devices/register', {
      token: 'sample-apns-token',
      platform: 'ios',
      provider: 'apns',
      environment: 'sandbox',
    });

    const response = await routes.postJSON('/api/debug/send-test-push', {
      title: 'Kitchen test',
      body: 'Testing Levy Home APNs.',
    });

    assert.equal(response.ok, true);
    assert.equal(response.provider, 'apns');
    assert.equal(response.registeredDeviceCount, 1);
    assert.equal(response.eligibleDeviceCount, 1);
    assert.equal(response.sentNotificationCount, 1);
    assert.equal(response.sentTicketCount, 1);
    assert.equal(response.failedNotificationCount, 0);
    assert.equal(response.invalidTokenCount, 0);
    assert.equal(pushSender.requests.length, 1);
    assert.equal(pushSender.requests[0].title, 'Kitchen test');
  });
});

test('POST /api/debug/notification-pipeline-test sends a push through the event pipeline', async () => {
  const pushSender = new FakePushSender();

  await withTestServer(pushSender, async () => {
    await routes.postJSON('/api/devices/register', {
      token: 'sample-apns-token',
      platform: 'ios',
      provider: 'apns',
      environment: 'sandbox',
    });

    const response = await routes.postJSON('/api/debug/notification-pipeline-test');
    const events = await routes.getJSON('/api/events');

    assert.equal(response.ok, true);
    assert.equal(response.provider, 'apns');
    assert.equal(response.event.type, 'garage_still_open_at_10pm');
    assert.equal(response.event.source, 'home_assistant_debug_pipeline_test');
    assert.equal(response.event.push.attempted, true);
    assert.equal(response.sentNotificationCount, 1);
    assert.equal(response.failedNotificationCount, 0);
    assert.equal(response.dedupeKey, 'garage_still_open_at_10pm:debug.notification_pipeline_test');
    assert.equal(events.events.length, 1);
    assert.equal(events.events[0].id, response.event.id);
    assert.equal(pushSender.requests.length, 1);
    assert.equal(pushSender.requests[0].title, 'Levy Home notification test');
    assert.equal(pushSender.requests[0].body, 'This push came through the Levy Home event pipeline.');
    assert.deepEqual(pushSender.requests[0].data, { category: 'garage_still_open_at_10pm' });
  });
});

test('phone entity discovery route requires the Home Assistant webhook secret', async () => {
  const response = await fetch(`${routes.baseURL()}/api/debug/home-assistant/phone-entities`);
  const body = (await response.json()) as { code: string };

  assert.equal(response.status, 401);
  assert.equal(body.code, 'unauthorized_home_assistant_webhook');
});

test('phone entity discovery returns sanitized Home Assistant candidates', async () => {
  await withLiveHomeAssistantStates(
    [
      {
        entity_id: 'sensor.josh_iphone_battery_level',
        state: '82',
        last_changed: '2026-06-15T17:00:00.000Z',
        last_updated: '2026-06-15T17:00:01.000Z',
        attributes: {
          friendly_name: "Joshs iPhone Battery Level",
          unit_of_measurement: '%',
          private_detail: 'should not be returned',
        },
      },
      {
        entity_id: 'device_tracker.mallorys_iphone',
        state: 'home',
        last_changed: '2026-06-15T17:01:00.000Z',
        last_updated: '2026-06-15T17:01:01.000Z',
        attributes: {
          friendly_name: "Mallorys iPhone",
        },
      },
      {
        entity_id: 'light.kitchen',
        state: 'on',
        last_changed: '2026-06-15T17:02:00.000Z',
        last_updated: '2026-06-15T17:02:01.000Z',
        attributes: {
          friendly_name: 'Kitchen',
        },
      },
    ],
    async () => {
      const response = await fetch(`${routes.baseURL()}/api/debug/home-assistant/phone-entities`, {
        headers: { Authorization: 'Bearer test-secret' },
      });
      const body = await response.json() as {
        ok: boolean;
        candidateCount: number;
        candidates: Array<Record<string, unknown>>;
      };

      assert.equal(response.ok, true);
      assert.equal(body.ok, true);
      assert.equal(body.candidateCount, 2);
      assert.deepEqual(
        body.candidates.map((candidate) => candidate.entityId),
        ['device_tracker.mallorys_iphone', 'sensor.josh_iphone_battery_level'],
      );
      assert.equal(body.candidates[0].domain, 'device_tracker');
      assert.equal(body.candidates[0].stateSummary, 'home');
      assert.equal(body.candidates[1].friendlyName, "Joshs iPhone Battery Level");
      assert.equal('attributes' in body.candidates[1], false);
      assert.equal(JSON.stringify(body).includes('test-home-assistant-token'), false);
      assert.equal(JSON.stringify(body).includes('should not be returned'), false);
    },
  );
});

test('phone entity discovery supports narrow keyword searches', async () => {
  await withLiveHomeAssistantStates(
    [
      {
        entity_id: 'sensor.josh_iphone_battery_level',
        state: '82',
        attributes: { friendly_name: "Joshs iPhone Battery Level" },
      },
      {
        entity_id: 'device_tracker.mallorys_iphone',
        state: 'home',
        attributes: { friendly_name: "Mallorys iPhone" },
      },
    ],
    async () => {
      const response = await fetch(`${routes.baseURL()}/api/debug/home-assistant/phone-entities?keywords=mallory`, {
        headers: { Authorization: 'Bearer test-secret' },
      });
      const body = await response.json() as {
        candidateCount: number;
        candidates: Array<Record<string, unknown>>;
      };

      assert.equal(response.ok, true);
      assert.equal(body.candidateCount, 1);
      assert.equal(body.candidates[0].entityId, 'device_tracker.mallorys_iphone');
      assert.deepEqual(body.candidates[0].matchedTerms, ['mallory']);
    },
  );
});

async function withTestServer(pushSender: PushSender, action: () => Promise<void>): Promise<void> {
  await routes.restart(createApp({ config: testConfig, pushSender }));
  await action();
}

async function withLiveHomeAssistantStates(
  states: Record<string, unknown>[],
  action: () => Promise<void>,
): Promise<void> {
  await routes.stop();

  const homeAssistantServer = createServer((req, res) => {
    if (req.url !== '/api/states') {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Not found' }));
      return;
    }

    if (req.headers.authorization !== 'Bearer test-home-assistant-token') {
      res.writeHead(401, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Unauthorized' }));
      return;
    }

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(states));
  });

  await new Promise<void>((resolve) => {
    homeAssistantServer.listen(0, '127.0.0.1', () => {
      resolve();
    });
  });

  const homeAssistantAddress = homeAssistantServer.address() as AddressInfo;
  const app = createApp({
    config: {
      ...testConfig,
      homeAssistant: {
        ...testConfig.homeAssistant,
        mode: 'live',
        baseURL: `http://127.0.0.1:${homeAssistantAddress.port}`,
        token: 'test-home-assistant-token',
      },
    },
  });

  await routes.start(app);

  try {
    await action();
  } finally {
    await routes.stop();
    await closeHttpServer(homeAssistantServer);
  }
}

async function closeHttpServer(server: ReturnType<typeof createServer>): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
        return;
      }

      resolve();
    });
  });
}
