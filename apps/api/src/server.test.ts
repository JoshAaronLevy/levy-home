import assert from 'node:assert/strict';
import { afterEach, beforeEach, test } from 'node:test';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';

import type { AppConfig } from './config.js';
import { createApp } from './server.js';

let server: Server | undefined;
let baseURL: string;

const testConfig: AppConfig = {
  port: 0,
  haWebhookSecret: 'test-secret',
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

async function getJSON(path: string): Promise<any> {
  const response = await fetch(`${baseURL}${path}`);
  assert.equal(response.ok, true);
  return response.json();
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
