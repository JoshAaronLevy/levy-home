import assert from 'node:assert/strict';
import { afterEach, beforeEach, test } from 'node:test';
import type { AddressInfo } from 'node:net';
import { createServer, type Server } from 'node:http';

import { normalizePhoneStateChangedEvent } from './activityNormalizer.js';
import { createRecentActivityStore } from './activityStore.js';
import type { PushSender } from './apnsService.js';
import type { AppConfig } from './config.js';
import type { APNsSendRequest, APNsSendResult } from './contracts.js';
import type { LevyHomeEvent } from './contracts.js';
import type { HomeAssistantStateChangedEvent } from './homeAssistantActivityClient.js';
import { createApp } from './server.js';

let server: Server | undefined;
let baseURL: string;

const testConfig: AppConfig = {
  port: 0,
  haWebhookSecret: 'test-secret',
  apns: {
    bundleId: 'com.levyhome.app',
    defaultEnvironment: 'sandbox',
  },
  homeAssistant: {
    mode: 'mock',
    garageCoverEntityId: 'cover.test_garage',
    allLightsEntityId: 'light.test_all_lights',
    lightGroups: [
      { id: 'upstairs_hallway', name: 'Upstairs Hallway', entityId: 'light.upstairs_hallway' },
      { id: 'playroom_lamp', name: 'Playroom', entityId: 'light.playroom_lamp' },
    ],
    lightEntities: [],
    mockTotalLightCount: 12,
    activity: {
      isEnabled: false,
      trackedPhoneEntities: [],
      trackedPhoneEntityPatterns: [],
    },
  },
};

class FakePushSender implements PushSender {
  readonly requests: APNsSendRequest[] = [];

  constructor(private readonly results: Partial<APNsSendResult>[] = []) {}

  async send(request: APNsSendRequest): Promise<APNsSendResult> {
    this.requests.push(request);
    const result = this.results.shift();

    return {
      provider: 'apns',
      deviceId: request.device.id,
      success: true,
      statusCode: 200,
      isInvalidToken: false,
      ...result,
    };
  }
}

beforeEach(async () => {
  await startTestServer(createApp({ config: testConfig }));
});

afterEach(async () => {
  await stopTestServer();
});

test('GET /api/shopping-list returns shopping data from the configured store', async () => {
  await restartTestServer(
    createApp({
      config: testConfig,
      shoppingListStore: {
        async fetchShoppingList() {
          return {
            items: [
              {
                id: 1,
                name: 'Whole milk',
                brand: 'Horizon',
                quantity: 2,
                notes: 'Half gallon',
                purchased: false,
                createdAt: '2026-06-22T12:00:00.000Z',
                updatedAt: '2026-06-22T12:30:00.000Z',
                storeIds: [1],
                categoryId: 2,
              },
            ],
            stores: [{ id: 1, name: 'Target', logo: 'target' }],
            categories: [{ id: 2, name: 'Dairy' }],
          };
        },
      },
    }),
  );

  const response = await getJSON('/api/shopping-list');

  assert.equal(response.ok, true);
  assert.equal(typeof response.generatedAt, 'string');
  assert.deepEqual(response.items, [
    {
      id: 1,
      name: 'Whole milk',
      brand: 'Horizon',
      quantity: 2,
      notes: 'Half gallon',
      purchased: false,
      createdAt: '2026-06-22T12:00:00.000Z',
      updatedAt: '2026-06-22T12:30:00.000Z',
      storeIds: [1],
      categoryId: 2,
    },
  ]);
  assert.deepEqual(response.stores, [{ id: 1, name: 'Target', logo: 'target' }]);
  assert.deepEqual(response.categories, [{ id: 2, name: 'Dairy' }]);
});

async function restartTestServer(app: ReturnType<typeof createApp>): Promise<void> {
  await stopTestServer();
  await startTestServer(app);
}

async function startTestServer(app: ReturnType<typeof createApp>): Promise<void> {
  await new Promise<void>((resolve) => {
    server = app.listen(0, () => {
      resolve();
    });
  });

  const address = server?.address() as AddressInfo;
  baseURL = `http://127.0.0.1:${address.port}`;
}

async function stopTestServer(): Promise<void> {
  if (!server) {
    return;
  }

  await new Promise<void>((resolve, reject) => {
    server?.close((error) => {
      if (error) {
        reject(error);
        return;
      }

      resolve();
    });
  });

  server = undefined;
}

test('GET /api/home/overview returns a narrow home overview', async () => {
  const response = await getJSON('/api/home/overview');

  assert.equal(response.ok, true);
  assert.equal(response.overview.garageStatus.state, 'closed');
  assert.equal(response.overview.lightSummary.state, 'off');
  assert.equal(response.overview.lightSummary.groups.length, 2);
  assert.deepEqual(response.overview.presence, []);
});

test('GET /api/home/actions returns curated action IDs and light groups', async () => {
  const response = await getJSON('/api/home/actions');

  assert.deepEqual(
    response.actions.map((action: { id: string }) => action.id),
    ['open_garage', 'close_garage', 'turn_off_all_lights', 'turn_off_light_group'],
  );
  assert.equal(
    response.actions.find((action: { id: string }) => action.id === 'open_garage')?.requiresConfirmation,
    false,
  );
  assert.equal(
    response.actions.find((action: { id: string }) => action.id === 'close_garage')?.requiresConfirmation,
    true,
  );
  assert.deepEqual(response.lightGroups, [
    { id: 'upstairs_hallway', name: 'Upstairs Hallway' },
    { id: 'playroom_lamp', name: 'Playroom' },
  ]);
});

test('POST /api/home/actions performs only curated actions', async () => {
  const response = await postJSON('/api/home/actions', {
    actionId: 'open_garage',
  });

  assert.equal(response.ok, true);
  assert.equal(response.result.actionId, 'open_garage');
  assert.equal(response.result.status, 'success');
  assert.equal(response.result.refreshedHomeOverview.garageStatus.state, 'open');
});

test('POST /api/home/actions performs curated light group actions', async () => {
  const response = await postJSON('/api/home/actions', {
    actionId: 'turn_off_light_group',
    groupId: 'upstairs_hallway',
  });

  assert.equal(response.ok, true);
  assert.equal(response.result.actionId, 'turn_off_light_group');
  assert.equal(response.result.status, 'success');
});

test('POST /api/home/actions rejects arbitrary Home Assistant payloads', async () => {
  const response = await fetch(`${baseURL}/api/home/actions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      domain: 'light',
      service: 'turn_on',
      entity_id: 'light.everything',
    }),
  });
  const body = (await response.json()) as { error: string; code: string };

  assert.equal(response.status, 400);
  assert.equal(body.code, 'arbitrary_home_assistant_payload_rejected');
});

test('explicit curated action endpoints work', async () => {
  const openGarage = await postJSON('/api/home/actions/open-garage');
  const closeGarage = await postJSON('/api/home/actions/close-garage');
  const lightsOff = await postJSON('/api/home/actions/lights-off');
  const lightGroup = await postJSON('/api/home/actions/light-groups/playroom_lamp/off');

  assert.equal(openGarage.result.actionId, 'open_garage');
  assert.equal(closeGarage.result.actionId, 'close_garage');
  assert.equal(lightsOff.result.actionId, 'turn_off_all_lights');
  assert.equal(lightGroup.result.actionId, 'turn_off_light_group');
});

test('POST /api/devices/register stores APNs registrations by provider and environment', async () => {
  const sandbox = await postJSON('/api/devices/register', {
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
    appVersion: '0.1.0',
    deviceName: 'Josh iPhone',
  });
  const production = await postJSON('/api/devices/register', {
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
  const response = await postJSON('/api/devices/register', {
    pushToken: 'ExponentPushToken[sample]',
    platform: 'ios',
  });

  assert.equal(response.ok, true);
  assert.equal(response.registeredDeviceCount, 1);
  assert.equal(response.device.provider, 'expo');
  assert.equal(response.device.platform, 'ios');
});

test('POST /api/devices/register rejects ambiguous APNs registrations', async () => {
  const response = await fetch(`${baseURL}/api/devices/register`, {
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

test('notification preferences can be synced and fetched by device token or device ID', async () => {
  const registered = await postJSON('/api/devices/register', {
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
  });

  const tokenSync = await putJSON('/api/notification-preferences', {
    deviceToken: 'sample-apns-token',
    provider: 'apns',
    environment: 'sandbox',
    preferences: [
      { category: 'garage_opened', isEnabled: false },
      { category: 'garage_left_open', isEnabled: false },
    ],
  });
  const tokenFetch = await getJSON(
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

  const deviceSync = await putJSON('/api/notification-preferences', {
    deviceId: registered.device.id,
    preferences: [{ category: 'garage_closed', isEnabled: false }],
  });
  const deviceFetch = await getJSON(`/api/notification-preferences?deviceId=${registered.device.id}`);

  assert.equal(deviceSync.ok, true);
  assert.equal(
    deviceFetch.preferences.find((preference: { category: string }) => preference.category === 'garage_closed')
      .isEnabled,
    false,
  );
});

test('POST /api/debug/send-test-push sends APNs test pushes with provider-neutral counts', async () => {
  const pushSender = new FakePushSender();

  await withTestServer(pushSender, async () => {
    await postJSON('/api/devices/register', {
      token: 'sample-apns-token',
      platform: 'ios',
      provider: 'apns',
      environment: 'sandbox',
    });

    const response = await postJSON('/api/debug/send-test-push', {
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

test('garage event pushes honor per-device notification preferences', async () => {
  const pushSender = new FakePushSender();

  await withTestServer(pushSender, async () => {
    await postJSON('/api/devices/register', {
      token: 'sample-apns-token',
      platform: 'ios',
      provider: 'apns',
      environment: 'sandbox',
    });
    await putJSON('/api/notification-preferences', {
      deviceToken: 'sample-apns-token',
      provider: 'apns',
      environment: 'sandbox',
      preferences: [{ category: 'garage_opened', isEnabled: false }],
    });

    const disabledEvent = await postJSON(
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
    const enabledEvent = await postJSON(
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
});

test('event webhook stores events and /api/events returns them', async () => {
  const created = await postJSON(
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
  const events = await getJSON('/api/events');

  assert.equal(created.ok, true);
  assert.equal(events.events.length, 1);
  assert.equal(events.events[0].type, 'garage_opened');
});

test('/api/events disables HTTP caching for the live timeline', async () => {
  const firstResponse = await fetch(`${baseURL}/api/events?limit=50`);
  const etag = firstResponse.headers.get('etag');

  assert.equal(firstResponse.status, 200);
  assert.equal(firstResponse.headers.get('cache-control'), 'no-store');
  assert.equal(etag, null);

  const conditionalResponse = await fetch(`${baseURL}/api/events?limit=50`, {
    headers: { 'If-None-Match': etag ?? '"stale-event-feed"' },
  });

  assert.equal(conditionalResponse.status, 200);
  assert.equal(conditionalResponse.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await conditionalResponse.json(), { ok: true, events: [] });
});

test('phone activity webhook events omit push metadata', async () => {
  const created = await postJSON(
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
  await closeServer();
  const activityStore = createRecentActivityStore();
  const app = createApp({ config: testConfig, activityStore });

  await new Promise<void>((resolve) => {
    server = app.listen(0, () => {
      resolve();
    });
  });

  const address = server?.address() as AddressInfo;
  baseURL = `http://127.0.0.1:${address.port}`;

  activityStore.add(normalizePhoneStateChangedEvent(sampleStateChangedEvent()));

  const response = await getJSON('/api/events?limit=50');

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
  await closeServer();
  const activityStore = createRecentActivityStore(500);
  const app = createApp({ config: testConfig, activityStore });

  await new Promise<void>((resolve) => {
    server = app.listen(0, () => {
      resolve();
    });
  });

  const address = server?.address() as AddressInfo;
  baseURL = `http://127.0.0.1:${address.port}`;

  activityStore.add(testActivityEvent('old', '2026-06-14T16:59:59.000Z'));
  activityStore.add(testActivityEvent('first-recent', '2026-06-14T17:00:00.000Z'));
  activityStore.add(testActivityEvent('newest', '2026-06-15T17:00:00.000Z'));

  const response = await getJSON('/api/events?limit=500&since=2026-06-14T17:00:00.000Z');

  assert.equal(response.ok, true);
  assert.deepEqual(
    response.events.map((event: LevyHomeEvent) => event.id),
    ['newest', 'first-recent'],
  );
});

test('/api/events returns local events and Home Assistant history for an explicit time window', async () => {
  await closeServer();

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

  await new Promise<void>((resolve) => {
    homeAssistantServer.listen(0, '127.0.0.1', () => {
      resolve();
    });
  });

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

  await new Promise<void>((resolve) => {
    server = app.listen(0, () => {
      resolve();
    });
  });

  const address = server?.address() as AddressInfo;
  baseURL = `http://127.0.0.1:${address.port}`;

  try {
    const response = await getJSON(
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
    await closeServer();
    await new Promise<void>((resolve, reject) => {
      homeAssistantServer.close((error) => {
        if (error) {
          reject(error);
          return;
        }

        resolve();
      });
    });
  }
});

test('/api/events returns local events when Home Assistant history is unavailable', async () => {
  await closeServer();

  const homeAssistantServer = createServer((_req, res) => {
    res.writeHead(503, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Home Assistant unavailable' }));
  });

  await new Promise<void>((resolve) => {
    homeAssistantServer.listen(0, '127.0.0.1', () => {
      resolve();
    });
  });

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

  await new Promise<void>((resolve) => {
    server = app.listen(0, () => {
      resolve();
    });
  });

  const address = server?.address() as AddressInfo;
  baseURL = `http://127.0.0.1:${address.port}`;

  try {
    const response = await getJSON(
      '/api/events?limit=500&start=2026-06-14T18:00:00.000Z&end=2026-06-15T18:00:00.000Z',
    );

    assert.equal(response.ok, true);
    assert.deepEqual(
      response.events.map((event: LevyHomeEvent) => event.id),
      ['local-event'],
    );
  } finally {
    await closeServer();
    await new Promise<void>((resolve, reject) => {
      homeAssistantServer.close((error) => {
        if (error) {
          reject(error);
          return;
        }

        resolve();
      });
    });
  }
});

test('/api/events rejects invalid explicit activity windows', async () => {
  const response = await fetch(`${baseURL}/api/events?start=2026-06-15T18:00:00.000Z&end=2026-06-14T18:00:00.000Z`);
  const body = (await response.json()) as { code: string };

  assert.equal(response.status, 400);
  assert.equal(body.code, 'invalid_activity_window');
});

test('phone entity discovery route requires the Home Assistant webhook secret', async () => {
  const response = await fetch(`${baseURL}/api/debug/home-assistant/phone-entities`);
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
      const response = await fetch(`${baseURL}/api/debug/home-assistant/phone-entities`, {
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
      const response = await fetch(`${baseURL}/api/debug/home-assistant/phone-entities?keywords=mallory`, {
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
  await closeServer();
  const app = createApp({ config: testConfig, pushSender });

  await new Promise<void>((resolve) => {
    server = app.listen(0, () => {
      resolve();
    });
  });

  const address = server?.address() as AddressInfo;
  baseURL = `http://127.0.0.1:${address.port}`;

  await action();
}

async function withLiveHomeAssistantStates(
  states: Record<string, unknown>[],
  action: () => Promise<void>,
): Promise<void> {
  await closeServer();

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

  await new Promise<void>((resolve) => {
    server = app.listen(0, () => {
      resolve();
    });
  });

  const address = server?.address() as AddressInfo;
  baseURL = `http://127.0.0.1:${address.port}`;

  try {
    await action();
  } finally {
    await closeServer();
    await new Promise<void>((resolve, reject) => {
      homeAssistantServer.close((error) => {
        if (error) {
          reject(error);
          return;
        }

        resolve();
      });
    });
  }
}

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

async function getJSON(path: string): Promise<any> {
  const response = await fetch(`${baseURL}${path}`);
  assert.equal(response.ok, true);
  return response.json();
}

async function closeServer(): Promise<void> {
  if (!server) {
    return;
  }

  await new Promise<void>((resolve, reject) => {
    server?.close((error) => {
      if (error) {
        reject(error);
        return;
      }

      resolve();
    });
  });

  server = undefined;
}

async function postJSON(
  path: string,
  body?: Record<string, unknown>,
  headers: Record<string, string> = {},
): Promise<any> {
  const response = await fetch(`${baseURL}${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...headers,
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });

  assert.equal(response.ok, true);
  return response.json();
}

async function putJSON(
  path: string,
  body: Record<string, unknown>,
  headers: Record<string, string> = {},
): Promise<any> {
  const response = await fetch(`${baseURL}${path}`, {
    method: 'PUT',
    headers: {
      'Content-Type': 'application/json',
      ...headers,
    },
    body: JSON.stringify(body),
  });

  assert.equal(response.ok, true);
  return response.json();
}
