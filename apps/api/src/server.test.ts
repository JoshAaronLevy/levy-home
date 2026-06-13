import assert from 'node:assert/strict';
import { afterEach, beforeEach, test } from 'node:test';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';

import type { PushSender } from './apnsService.js';
import type { AppConfig } from './config.js';
import type { APNsSendRequest, APNsSendResult } from './contracts.js';
import { createApp } from './server.js';

let server: Server | undefined;
let baseURL: string;

const testConfig: AppConfig = {
  port: 0,
  haWebhookSecret: 'test-secret',
  apns: {
    bundleId: 'com.levy.home',
    defaultEnvironment: 'sandbox',
  },
  homeAssistant: {
    mode: 'mock',
    garageCoverEntityId: 'cover.test_garage',
    allLightsEntityId: 'light.test_all_lights',
    lightGroups: [
      { id: 'downstairs', name: 'Downstairs lights', entityId: 'light.downstairs' },
      { id: 'bedrooms', name: 'Bedroom lights', entityId: 'light.bedrooms' },
    ],
    mockTotalLightCount: 12,
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
  const app = createApp({ config: testConfig });

  await new Promise<void>((resolve) => {
    server = app.listen(0, () => {
      resolve();
    });
  });

  const address = server?.address() as AddressInfo;
  baseURL = `http://127.0.0.1:${address.port}`;
});

afterEach(async () => {
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
});

test('GET /api/home/overview returns a narrow home overview', async () => {
  const response = await getJSON('/api/home/overview');

  assert.equal(response.ok, true);
  assert.equal(response.overview.garageStatus.state, 'closed');
  assert.equal(response.overview.lightSummary.state, 'off');
  assert.equal(response.overview.lightSummary.groups.length, 2);
});

test('GET /api/home/actions returns curated action IDs and light groups', async () => {
  const response = await getJSON('/api/home/actions');

  assert.deepEqual(
    response.actions.map((action: { id: string }) => action.id),
    ['close_garage', 'turn_off_all_lights', 'turn_off_light_group'],
  );
  assert.deepEqual(response.lightGroups, [
    { id: 'downstairs', name: 'Downstairs lights' },
    { id: 'bedrooms', name: 'Bedroom lights' },
  ]);
});

test('POST /api/home/actions performs only curated actions', async () => {
  const response = await postJSON('/api/home/actions', {
    actionId: 'turn_off_light_group',
    groupId: 'downstairs',
  });

  assert.equal(response.ok, true);
  assert.equal(response.result.actionId, 'turn_off_light_group');
  assert.equal(response.result.status, 'success');
  assert.equal(response.result.refreshedHomeOverview.garageStatus.state, 'closed');
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
  const closeGarage = await postJSON('/api/home/actions/close-garage');
  const lightsOff = await postJSON('/api/home/actions/lights-off');
  const lightGroup = await postJSON('/api/home/actions/light-groups/bedrooms/off');

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
