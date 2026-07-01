import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import type { AddressInfo } from 'node:net';
import { afterEach, beforeEach, test } from 'node:test';

import { normalizePhoneStateChangedEvent } from '../../../src/activityNormalizer.js';
import { createRecentActivityStore } from '../../../src/activityStore.js';
import { createApp } from '../../../src/app.js';
import type { LevyHomeEvent } from '../../../src/contracts.js';
import type { HomeAssistantStateChangedEvent } from '../../../src/homeAssistantActivityClient.js';
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

test('garage event pushes honor per-device notification preferences', async () => {
  const pushSender = new FakePushSender();

  await routes.restart(createApp({ config: testConfig, pushSender }));

  await routes.postJSON('/api/devices/register', {
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
  });
  await routes.putJSON('/api/notification-preferences', {
    deviceToken: 'sample-apns-token',
    provider: 'apns',
    environment: 'sandbox',
    preferences: [{ category: 'garage_opened', isEnabled: false }],
  });

  const disabledEvent = await routes.postJSON(
    '/api/ha/events',
    {
      type: 'garage_opened',
      category: 'garage',
      severity: 'normal',
      entityId: 'cover.test_garage',
      source: 'home_assistant',
    },
    { Authorization: 'Bearer test-secret' },
  );
  const enabledEvent = await routes.postJSON(
    '/api/ha/events',
    {
      type: 'garage_closed',
      category: 'garage',
      severity: 'normal',
      entityId: 'cover.test_garage',
      source: 'home_assistant',
    },
    { Authorization: 'Bearer test-secret' },
  );

  assert.equal(disabledEvent.event.push.attempted, false);
  assert.equal(disabledEvent.event.push.skipped, true);
  assert.equal(disabledEvent.event.push.reason, 'All registered APNs devices have this notification disabled.');
  assert.equal(enabledEvent.event.push.attempted, true);
  assert.equal(enabledEvent.event.push.sentNotificationCount, 1);
  assert.equal(pushSender.requests.length, 1);
  assert.equal(pushSender.requests[0].title, 'Garage closed');
});

test('event webhook stores events and /api/events returns them', async () => {
  const created = await routes.postJSON(
    '/api/ha/events',
    {
      type: 'garage_opened',
      category: 'garage',
      severity: 'normal',
      entityId: 'cover.test_garage',
      source: 'home_assistant',
    },
    { Authorization: 'Bearer test-secret' },
  );
  const events = await routes.getJSON('/api/events');

  assert.equal(created.ok, true);
  assert.equal(events.events.length, 1);
  assert.equal(events.events[0].type, 'garage_opened');
});

test('/api/events disables HTTP caching for the live timeline', async () => {
  const firstResponse = await fetch(`${routes.baseURL()}/api/events?limit=50`);
  const etag = firstResponse.headers.get('etag');

  assert.equal(firstResponse.status, 200);
  assert.equal(firstResponse.headers.get('cache-control'), 'no-store');
  assert.equal(etag, null);

  const conditionalResponse = await fetch(`${routes.baseURL()}/api/events?limit=50`, {
    headers: { 'If-None-Match': etag ?? '"stale-event-feed"' },
  });

  assert.equal(conditionalResponse.status, 200);
  assert.equal(conditionalResponse.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await conditionalResponse.json(), { ok: true, events: [] });
});

test('phone activity webhook events omit push metadata', async () => {
  const created = await routes.postJSON(
    '/api/ha/events',
    {
      type: 'phone_state_changed',
      category: 'phone',
      severity: 'normal',
      entityId: 'sensor.josh_iphone_battery_level',
      source: 'home_assistant',
      title: "Joshs iPhone changed",
      message: '82 -> 81',
    },
    { Authorization: 'Bearer test-secret' },
  );

  assert.equal(created.ok, true);
  assert.equal(created.event.type, 'phone_state_changed');
  assert.equal(created.event.category, 'phone');
  assert.equal(created.event.display.title, 'Phone changed');
  assert.equal(created.event.push, undefined);
});

test('/api/events returns normalized Home Assistant phone activity from the shared activity store', async () => {
  const activityStore = createRecentActivityStore();
  const app = createApp({ config: testConfig, activityStore });

  await routes.restart(app);

  activityStore.add(normalizePhoneStateChangedEvent(sampleStateChangedEvent()));

  const response = await routes.getJSON('/api/events?limit=50');

  assert.equal(response.ok, true);
  assert.equal(response.events.length, 1);
  assert.equal(response.events[0].type, 'phone_state_changed');
  assert.equal(response.events[0].category, 'phone');
  assert.equal(response.events[0].entityId, 'device_tracker.josh_iphone');
  assert.equal(response.events[0].title, 'Josh arrived home');
  assert.equal(response.events[0].metadata.person, 'Josh');
  assert.equal(response.events[0].push, undefined);
});

test('/api/events filters recent activity by since timestamp', async () => {
  const activityStore = createRecentActivityStore(500);
  const app = createApp({ config: testConfig, activityStore });

  await routes.restart(app);

  activityStore.add(testActivityEvent('old', '2026-06-14T16:59:59.000Z'));
  activityStore.add(testActivityEvent('first-recent', '2026-06-14T17:00:00.000Z'));
  activityStore.add(testActivityEvent('newest', '2026-06-15T17:00:00.000Z'));

  const response = await routes.getJSON('/api/events?limit=500&since=2026-06-14T17:00:00.000Z');

  assert.equal(response.ok, true);
  assert.deepEqual(
    response.events.map((event: LevyHomeEvent) => event.id),
    ['newest', 'first-recent'],
  );
});

test('/api/events returns local events and Home Assistant history for an explicit time window', async () => {
  await routes.stop();

  const homeAssistantRequests: string[] = [];
  const homeAssistantServer = createServer((req, res) => {
    const url = new URL(req.url ?? '/', 'http://home-assistant.test');
    homeAssistantRequests.push(`${url.pathname}?${url.searchParams.toString()}`);

    if (req.headers.authorization !== 'Bearer test-home-assistant-token') {
      res.writeHead(401, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Unauthorized' }));
      return;
    }

    if (url.pathname === '/api/history/period/2026-06-14T18:00:00.000Z') {
      assert.equal(url.searchParams.get('end_time'), '2026-06-15T18:00:00.000Z');
      assert.equal(url.searchParams.get('filter_entity_id'), 'device_tracker.josh_iphone');
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify([
        [
          {
            entity_id: 'device_tracker.josh_iphone',
            state: 'not_home',
            last_changed: '2026-06-14T18:30:00.000Z',
            attributes: { friendly_name: "Joshs iPhone" },
          },
          {
            entity_id: 'device_tracker.josh_iphone',
            state: 'home',
            last_changed: '2026-06-14T19:00:00.000Z',
            attributes: { friendly_name: "Joshs iPhone" },
          },
        ],
      ]));
      return;
    }

    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not found' }));
  });

  await listenOnLoopback(homeAssistantServer);

  const homeAssistantAddress = homeAssistantServer.address() as AddressInfo;
  const activityStore = createRecentActivityStore(500);
  activityStore.add(testActivityEvent('local-event', '2026-06-14T18:45:00.000Z'));

  const app = createApp({
    config: {
      ...testConfig,
      homeAssistant: {
        ...testConfig.homeAssistant,
        mode: 'live',
        baseURL: `http://127.0.0.1:${homeAssistantAddress.port}`,
        token: 'test-home-assistant-token',
        activity: {
          isEnabled: true,
          trackedPhoneEntities: [
            { entityId: 'device_tracker.josh_iphone', person: 'Josh', deviceName: "Joshs iPhone" },
            { entityId: 'sensor.josh_iphone_battery_level', person: 'Josh', deviceName: "Joshs iPhone" },
          ],
          trackedPhoneEntityPatterns: [],
        },
      },
    },
    activityStore,
  });

  await routes.start(app);

  try {
    const response = await routes.getJSON(
      '/api/events?limit=500&start=2026-06-14T18:00:00.000Z&end=2026-06-15T18:00:00.000Z',
    );

    assert.equal(response.ok, true);
    assert.deepEqual(
      response.events.map((event: LevyHomeEvent) => event.occurredAt),
      [
        '2026-06-14T19:00:00.000Z',
        '2026-06-14T18:45:00.000Z',
      ],
    );
    assert.equal(response.events[0].type, 'phone_state_changed');
    assert.equal(response.events[0].metadata.ingestionSource, 'history');
    assert.equal(response.events[0].title, 'Josh arrived home');
    assert.equal(response.events[1].id, 'local-event');
    assert.deepEqual(homeAssistantRequests, [
      '/api/history/period/2026-06-14T18:00:00.000Z?end_time=2026-06-15T18%3A00%3A00.000Z&filter_entity_id=device_tracker.josh_iphone',
    ]);
  } finally {
    await routes.stop();
    await closeHttpServer(homeAssistantServer);
  }
});

test('/api/events returns local events when Home Assistant history is unavailable', async () => {
  await routes.stop();

  const homeAssistantServer = createServer((_req, res) => {
    res.writeHead(503, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Home Assistant unavailable' }));
  });

  await listenOnLoopback(homeAssistantServer);

  const homeAssistantAddress = homeAssistantServer.address() as AddressInfo;
  const activityStore = createRecentActivityStore(500);
  activityStore.add(testActivityEvent('local-event', '2026-06-14T18:45:00.000Z'));

  const app = createApp({
    config: {
      ...testConfig,
      homeAssistant: {
        ...testConfig.homeAssistant,
        mode: 'live',
        baseURL: `http://127.0.0.1:${homeAssistantAddress.port}`,
        token: 'test-home-assistant-token',
        activity: {
          isEnabled: true,
          trackedPhoneEntities: [
            { entityId: 'device_tracker.josh_iphone', person: 'Josh', deviceName: "Joshs iPhone" },
          ],
          trackedPhoneEntityPatterns: [],
        },
      },
    },
    activityStore,
  });

  await routes.start(app);

  try {
    const response = await routes.getJSON(
      '/api/events?limit=500&start=2026-06-14T18:00:00.000Z&end=2026-06-15T18:00:00.000Z',
    );

    assert.equal(response.ok, true);
    assert.deepEqual(
      response.events.map((event: LevyHomeEvent) => event.id),
      ['local-event'],
    );
  } finally {
    await routes.stop();
    await closeHttpServer(homeAssistantServer);
  }
});

test('/api/events rejects invalid explicit activity windows', async () => {
  const response = await fetch(
    `${routes.baseURL()}/api/events?start=2026-06-15T18:00:00.000Z&end=2026-06-14T18:00:00.000Z`,
  );
  const body = (await response.json()) as { code: string };

  assert.equal(response.status, 400);
  assert.equal(body.code, 'invalid_activity_window');
});

function sampleStateChangedEvent(): HomeAssistantStateChangedEvent {
  return {
    entityId: 'device_tracker.josh_iphone',
    person: 'Josh',
    deviceName: "Joshs iPhone",
    oldState: 'not_home',
    newState: 'home',
    occurredAt: '2026-06-15T17:00:00.000Z',
    friendlyName: "Joshs iPhone",
    rawEvent: {
      event_type: 'state_changed',
      time_fired: '2026-06-15T17:00:00.000Z',
      context: {
        id: 'event-context-id',
      },
      data: {
        entity_id: 'device_tracker.josh_iphone',
        old_state: {
          entity_id: 'device_tracker.josh_iphone',
          state: 'not_home',
          attributes: {
            friendly_name: "Joshs iPhone",
          },
        },
        new_state: {
          entity_id: 'device_tracker.josh_iphone',
          state: 'home',
          attributes: {
            friendly_name: "Joshs iPhone",
          },
        },
      },
    },
  };
}

function testActivityEvent(id: string, occurredAt: string): LevyHomeEvent {
  return {
    id,
    type: 'phone_state_changed',
    category: 'phone',
    severity: 'normal',
    entityId: `sensor.${id}`,
    source: 'home_assistant',
    occurredAt,
    receivedAt: occurredAt,
    display: {
      title: 'Phone changed',
      body: 'State changed',
      severity: 'info',
    },
  };
}

async function listenOnLoopback(server: ReturnType<typeof createServer>): Promise<void> {
  await new Promise<void>((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      resolve();
    });
  });
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
