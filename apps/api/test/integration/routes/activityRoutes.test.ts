import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import type { AddressInfo } from 'node:net';
import { afterEach, beforeEach, test } from 'node:test';

import { normalizePhoneStateChangedEvent } from '../../../src/integrations/homeAssistant/activityNormalizer.js';
import { createRecentActivityStore } from '../../../src/activityStore.js';
import { createApp } from '../../../src/app.js';
import type { LevyHomeEvent } from '../../../src/contracts.js';
import type { HomeAssistantStateChangedEvent } from '../../../src/integrations/homeAssistant/activityListener.js';
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
    deviceName: 'Josh',
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

test('garage left open Home Assistant automation payload sends a Levy Home push notification', async () => {
  const pushSender = new FakePushSender();

  await routes.restart(createApp({ config: testConfig, pushSender }));

  await routes.postJSON('/api/devices/register', {
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
    deviceName: 'Josh',
  });

  const created = await routes.postJSON(
    '/api/ha/events',
    {
      type: 'garage_left_open_10_min',
      category: 'garage',
      severity: 'normal',
      entityId: 'cover.meross_garage_door',
      source: 'home_assistant',
      occurredAt: '2026-07-04T12:00:00.000Z',
      title: 'Garage left open',
      message: 'The garage has been open for 10 minutes',
    },
    { Authorization: 'Bearer test-secret' },
  );

  assert.equal(created.ok, true);
  assert.equal(created.event.type, 'garage_left_open_10_min');
  assert.equal(created.event.category, 'garage');
  assert.equal(created.event.entityId, 'cover.meross_garage_door');
  assert.equal(created.event.display.title, 'Garage left open');
  assert.equal(created.event.display.body, 'The garage has been open for 10 minutes.');
  assert.equal(created.event.title, 'Garage left open');
  assert.equal(created.event.message, 'The garage has been open for 10 minutes');
  assert.equal(created.event.push.attempted, true);
  assert.equal(created.event.push.sentNotificationCount, 1);
  assert.equal(pushSender.requests.length, 1);
  assert.equal(pushSender.requests[0].title, 'Garage left open');
  assert.equal(pushSender.requests[0].body, 'The garage has been open for 10 minutes');
  assert.deepEqual(pushSender.requests[0].data, { category: 'garage_left_open' });
});

test('laundry Home Assistant events send Levy Home push notifications through the laundry preference', async () => {
  const pushSender = new FakePushSender();

  await routes.restart(createApp({ config: testConfig, pushSender }));

  await routes.postJSON('/api/devices/register', {
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
  });

  for (const event of [
    {
      type: 'washer_cycle_finished',
      entityId: 'sensor.washer_job_state',
      title: 'Washer cycle complete',
      message: 'The washer cycle has finished.',
    },
    {
      type: 'dryer_cycle_finished',
      entityId: 'sensor.dryer_job_state',
      title: 'Dryer cycle complete',
      message: 'The dryer cycle has finished.',
    },
    {
      type: 'washer_transfer_reminder',
      entityId: 'input_boolean.laundry_needs_transfer',
      occurredAt: '2026-08-24T20:30:00-06:00',
      title: 'Laundry may still be in the washer',
      message: "The washer finished, but the dryer hasn't been started since. You may still need to move the laundry over.",
    },
  ]) {
    const created = await routes.postJSON(
      '/api/ha/events',
      {
        ...event,
        category: 'laundry',
        severity: 'normal',
        source: 'home_assistant',
      },
      { Authorization: 'Bearer test-secret' },
    );

    assert.equal(created.ok, true);
    assert.equal(created.event.type, event.type);
    assert.equal(created.event.category, 'laundry');
    assert.equal(created.event.display.title, event.title);
    assert.equal(created.event.display.body, event.message);
    assert.equal(created.event.push.attempted, true);
    assert.equal(created.event.push.sentNotificationCount, 1);

    if (event.type === 'washer_transfer_reminder') {
      assert.equal(created.event.entityId, 'input_boolean.laundry_needs_transfer');
      assert.equal(created.event.severity, 'normal');
      assert.equal(created.event.source, 'home_assistant');
      assert.equal(created.event.occurredAt, '2026-08-24T20:30:00-06:00');
    }
  }

  assert.deepEqual(
    pushSender.requests.map(({ title, body, data }) => ({ title, body, data })),
    [
      {
        title: 'Washer cycle complete',
        body: 'The washer cycle has finished.',
        data: { category: 'laundry' },
      },
      {
        title: 'Dryer cycle complete',
        body: 'The dryer cycle has finished.',
        data: { category: 'laundry' },
      },
      {
        title: 'Laundry may still be in the washer',
        body: "The washer finished, but the dryer hasn't been started since. You may still need to move the laundry over.",
        data: { category: 'laundry' },
      },
    ],
  );
});

test('refrigerator and freezer door Home Assistant automations send Levy Home push notifications', async () => {
  const pushSender = new FakePushSender();

  await routes.restart(createApp({ config: testConfig, pushSender }));

  await routes.postJSON('/api/devices/register', {
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
  });

  for (const event of [
    {
      type: 'freezer_door_left_open_5_min',
      category: 'freezer',
      entityId: 'binary_sensor.refrigerator_freezer_door',
      title: 'Freezer door left open',
      message: 'The freezer door has been open for 5 minutes.',
    },
    {
      type: 'refrigerator_door_left_open_5_min',
      category: 'refrigerator',
      entityId: 'binary_sensor.refrigerator_fridge_door',
      title: 'Refrigerator door left open',
      message: 'The refrigerator door has been open for 5 minutes.',
    },
  ]) {
    const created = await routes.postJSON(
      '/api/ha/events',
      {
        ...event,
        severity: 'normal',
        source: 'home_assistant',
      },
      { Authorization: 'Bearer test-secret' },
    );

    assert.equal(created.ok, true);
    assert.equal(created.event.type, event.type);
    assert.equal(created.event.category, event.category);
    assert.equal(created.event.display.title, event.title);
    assert.equal(created.event.display.body, event.message);
    assert.equal(created.event.push.attempted, true);
    assert.equal(created.event.push.sentNotificationCount, 1);
  }

  assert.deepEqual(
    pushSender.requests.map(({ title, body, data }) => ({ title, body, data })),
    [
      {
        title: 'Freezer door left open',
        body: 'The freezer door has been open for 5 minutes.',
        data: { category: 'freezer' },
      },
      {
        title: 'Refrigerator door left open',
        body: 'The refrigerator door has been open for 5 minutes.',
        data: { category: 'refrigerator' },
      },
    ],
  );
});

test('thermostat high-setpoint automation notifies every registered household device', async () => {
  const pushSender = new FakePushSender();

  await routes.restart(createApp({ config: testConfig, pushSender }));

  await routes.postJSON('/api/devices/register', {
    token: 'josh-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
    deviceName: 'Josh iPhone',
  });
  await routes.postJSON('/api/devices/register', {
    token: 'mallory-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
    deviceName: 'Mallory iPhone',
  });

  const created = await routes.postJSON(
    '/api/ha/events',
    {
      type: 'thermostat_setpoint_high',
      category: 'thermostat',
      severity: 'normal',
      entityId: 'climate.thermostat',
      source: 'home_assistant',
      occurredAt: '2026-08-08T21:45:00.000Z',
      title: 'Thermostat changed',
      message: 'Thermostat was changed to 65° / 73°.',
    },
    { Authorization: 'Bearer test-secret' },
  );

  assert.equal(created.ok, true);
  assert.equal(created.event.type, 'thermostat_setpoint_high');
  assert.equal(created.event.category, 'thermostat');
  assert.equal(created.event.display.title, 'Thermostat changed');
  assert.equal(created.event.display.body, 'Thermostat was changed to 65° / 73°.');
  assert.equal(created.event.push.attempted, true);
  assert.equal(created.event.push.sentNotificationCount, 2);
  assert.equal(pushSender.requests.length, 2);
  assert.deepEqual(pushSender.requests.map((request) => request.device.token).sort(), [
    'josh-apns-token',
    'mallory-apns-token',
  ]);
  assert.deepEqual(pushSender.requests.map((request) => request.body), [
    'Thermostat was changed to 65° / 73°.',
    'Thermostat was changed to 65° / 73°.',
  ]);
  assert.deepEqual(pushSender.requests.map((request) => request.data), [
    { category: 'thermostat_setpoint_high' },
    { category: 'thermostat_setpoint_high' },
  ]);
});

test('partner presence webhook event sends a Levy Home push notification', async () => {
  const pushSender = new FakePushSender();

  await routes.restart(createApp({ config: testConfig, pushSender }));

  await routes.postJSON('/api/devices/register', {
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
    deviceName: 'Josh',
  });

  const created = await routes.postJSON(
    '/api/ha/events',
    {
      type: 'partner_left_home',
      category: 'presence',
      severity: 'normal',
      entityId: 'device_tracker.mallorys_iphone',
      source: 'home_assistant',
      title: 'Mallory left home',
      message: 'Mallory left home.',
      metadata: {
        actor: 'Mallory',
        recipient: 'Josh',
        oldState: 'home',
        newState: 'not_home',
      },
    },
    { Authorization: 'Bearer test-secret' },
  );

  assert.equal(created.ok, true);
  assert.equal(created.event.type, 'partner_left_home');
  assert.equal(created.event.category, 'presence');
  assert.equal(created.event.display.title, 'Mallory left home');
  assert.equal(created.event.display.body, 'Mallory left home.');
  assert.equal(created.event.push.attempted, true);
  assert.equal(created.event.push.sentNotificationCount, 1);
  assert.equal(pushSender.requests.length, 1);
  assert.equal(pushSender.requests[0].title, 'Mallory left home');
  assert.equal(pushSender.requests[0].body, 'Mallory left home.');
});

test('lighting automation webhook event sends a Levy Home push notification', async () => {
  const pushSender = new FakePushSender();

  await routes.restart(createApp({ config: testConfig, pushSender }));

  await routes.postJSON('/api/devices/register', {
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
  });

  const created = await routes.postJSON(
    '/api/ha/events',
    {
      type: 'study_lights_on',
      category: 'lighting',
      severity: 'normal',
      entityId: 'automation.study_on_bright',
      source: 'home_assistant',
      message: 'Study: Let there be light!',
      metadata: {
        automation: 'Study On Bright',
      },
    },
    { Authorization: 'Bearer test-secret' },
  );

  assert.equal(created.ok, true);
  assert.equal(created.event.type, 'study_lights_on');
  assert.equal(created.event.category, 'lighting');
  assert.equal(created.event.display.title, 'Study lights on');
  assert.equal(created.event.display.body, 'Study: Let there be light!');
  assert.equal(created.event.push.attempted, true);
  assert.equal(created.event.push.sentNotificationCount, 1);
  assert.equal(pushSender.requests.length, 1);
  assert.equal(pushSender.requests[0].title, 'Study lights on');
  assert.equal(pushSender.requests[0].body, 'Study: Let there be light!');
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
