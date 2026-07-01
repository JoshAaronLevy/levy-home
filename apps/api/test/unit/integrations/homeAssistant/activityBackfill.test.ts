import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { AppConfig } from '../../../../src/config.js';
import {
  backfillHomeAssistantActivity,
  fetchHomeAssistantActivityWindow,
} from '../../../../src/integrations/homeAssistant/activityBackfill.js';
import type { HomeAssistantStateChangedEvent } from '../../../../src/integrations/homeAssistant/activityListener.js';

const baseConfig: AppConfig = {
  port: 0,
  kroger: {
    apiBaseURL: 'https://api.kroger.test/v1',
    productResponseFilePath: '/tmp/kroger-product-response.json',
    normalizedProductResponseFilePath: '/tmp/kroger-products-normalized.json',
    productSearchLimit: 10,
    locationId: '62000008',
    shoppingStoreId: 2,
    shoppingStoreName: 'King Soopers',
  },
  apns: {
    bundleId: 'com.levyhome.app',
    defaultEnvironment: 'sandbox',
  },
  homeAssistant: {
    mode: 'live',
    baseURL: 'http://home-assistant.local',
    token: 'test-home-assistant-token',
    garageCoverEntityId: 'cover.main_garage_door',
    allLightsEntityId: 'light.all_lights',
    lightGroups: [],
    lightEntities: [],
    mockTotalLightCount: 12,
    activity: {
      isEnabled: true,
      trackedPhoneEntities: [
        { entityId: 'device_tracker.mallorys_iphone', person: 'Mallory', deviceName: "Mallorys iPhone" },
      ],
      trackedPhoneEntityPatterns: [
        { pattern: 'device_tracker.josh_*', person: 'Josh', deviceName: "Joshs iPhone" },
        { pattern: 'sensor.josh_iphone_*', person: 'Josh', deviceName: "Joshs iPhone" },
      ],
    },
  },
};

test('backfills meaningful home presence activity from Home Assistant history', async () => {
  const requests: URL[] = [];
  const events: HomeAssistantStateChangedEvent[] = [];
  const fetchImpl: typeof fetch = async (input, init) => {
    const url = new URL(input.toString());
    requests.push(url);

    assert.equal((init?.headers as Record<string, string> | undefined)?.Authorization, 'Bearer test-home-assistant-token');

    if (url.pathname === '/api/states') {
      return jsonResponse([
        { entity_id: 'device_tracker.josh_iphone', state: 'not_home' },
        { entity_id: 'sensor.josh_iphone_activity', state: 'stationary' },
        { entity_id: 'sensor.josh_iphone_battery_level', state: '81' },
        { entity_id: 'light.kitchen', state: 'on' },
      ]);
    }

    if (url.pathname === '/api/history/period/2026-06-14T18:00:00.000Z') {
      assert.equal(url.searchParams.get('end_time'), '2026-06-15T18:00:00.000Z');
      assert.equal(
        url.searchParams.get('filter_entity_id'),
        'device_tracker.josh_iphone,device_tracker.mallorys_iphone',
      );

      return jsonResponse([
        [
          {
            entity_id: 'device_tracker.mallorys_iphone',
            state: 'home',
            last_changed: '2026-06-15T16:45:00.000Z',
            attributes: { friendly_name: "Mallorys iPhone" },
          },
          {
            entity_id: 'device_tracker.mallorys_iphone',
            state: 'not_home',
            last_changed: '2026-06-15T17:00:00.000Z',
            attributes: { friendly_name: "Mallorys iPhone" },
          },
        ],
        [
          {
            entity_id: 'device_tracker.josh_iphone',
            state: 'not_home',
            last_changed: '2026-06-15T17:15:00.000Z',
            attributes: { friendly_name: "Joshs iPhone" },
          },
          {
            entity_id: 'device_tracker.josh_iphone',
            state: 'home',
            last_changed: '2026-06-15T17:30:00.000Z',
            attributes: { friendly_name: "Joshs iPhone" },
          },
        ],
      ]);
    }

    return jsonResponse({ error: 'Not found' }, 404);
  };

  const eventCount = await backfillHomeAssistantActivity(baseConfig, {
    fetchImpl,
    now: () => new Date('2026-06-15T18:00:00.000Z'),
    onStateChanged: (event) => events.push(event),
  });

  assert.equal(eventCount, 2);
  assert.deepEqual(
    requests.map((request) => request.pathname),
    ['/api/states', '/api/history/period/2026-06-14T18:00:00.000Z'],
  );
  assert.deepEqual(
    events.map((event) => event.entityId),
    [
      'device_tracker.mallorys_iphone',
      'device_tracker.josh_iphone',
    ],
  );
  assert.deepEqual(
    events.map((event) => event.occurredAt),
    [
      '2026-06-15T17:00:00.000Z',
      '2026-06-15T17:30:00.000Z',
    ],
  );
  assert.equal(events[0].ingestionSource, 'history');
  assert.match(events[0].id ?? '', /^ha-history-[a-f0-9]{24}$/);
  assert.equal(events[0].isInitialBackfillState, false);
  assert.equal(events[0].oldState, 'home');
  assert.equal(events[0].newState, 'not_home');
  assert.equal(events[1].oldState, 'not_home');
  assert.equal(events[1].newState, 'home');
  assert.equal(JSON.stringify(events).includes('test-home-assistant-token'), false);
  assert.equal(JSON.stringify(events).includes('sensor.josh_iphone_battery_level'), false);
  assert.equal(JSON.stringify(events).includes('light.kitchen'), false);
});

test('fetchHomeAssistantActivityWindow requests the provided absolute time window', async () => {
  const requestedPaths: string[] = [];
  const fetchImpl: typeof fetch = async (input) => {
    const url = new URL(input.toString());
    requestedPaths.push(`${url.pathname}?${url.searchParams.toString()}`);

    if (url.pathname === '/api/states') {
      return jsonResponse([]);
    }

    if (url.pathname === '/api/history/period/2026-06-13T18:00:00.000Z') {
      assert.equal(url.searchParams.get('end_time'), '2026-06-14T18:00:00.000Z');
      return jsonResponse([
        [
          {
            entity_id: 'device_tracker.mallorys_iphone',
            state: 'home',
            last_changed: '2026-06-13T18:30:00.000Z',
          },
          {
            entity_id: 'device_tracker.mallorys_iphone',
            state: 'not_home',
            last_changed: '2026-06-13T19:00:00.000Z',
          },
        ],
      ]);
    }

    return jsonResponse({ error: 'Not found' }, 404);
  };

  const events = await fetchHomeAssistantActivityWindow(baseConfig, {
    fetchImpl,
    startTime: new Date('2026-06-13T18:00:00.000Z'),
    endTime: new Date('2026-06-14T18:00:00.000Z'),
  });

  assert.deepEqual(
    requestedPaths,
    ['/api/states?', '/api/history/period/2026-06-13T18:00:00.000Z?end_time=2026-06-14T18%3A00%3A00.000Z&filter_entity_id=device_tracker.mallorys_iphone'],
  );
  assert.equal(events.length, 1);
  assert.equal(events[0].entityId, 'device_tracker.mallorys_iphone');
  assert.equal(events[0].occurredAt, '2026-06-13T19:00:00.000Z');
});

test('backfill skips when Home Assistant activity ingestion is disabled', async () => {
  let requestCount = 0;
  const eventCount = await backfillHomeAssistantActivity(
    {
      ...baseConfig,
      homeAssistant: {
        ...baseConfig.homeAssistant,
        activity: {
          ...baseConfig.homeAssistant.activity,
          isEnabled: false,
        },
      },
    },
    {
      fetchImpl: (async () => {
        requestCount += 1;
        return jsonResponse([]);
      }) as typeof fetch,
    },
  );

  assert.equal(eventCount, 0);
  assert.equal(requestCount, 0);
});

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
    },
  });
}
