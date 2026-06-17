import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { AppConfig } from './config.js';
import {
  backfillHomeAssistantActivity,
  fetchHomeAssistantActivityWindow,
} from './homeAssistantActivityBackfill.js';
import type { HomeAssistantStateChangedEvent } from './homeAssistantActivityClient.js';

const baseConfig: AppConfig = {
  port: 0,
  apns: {
    bundleId: 'com.levy.home',
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
        { pattern: 'sensor.josh_iphone_*', person: 'Josh', deviceName: "Joshs iPhone" },
      ],
    },
  },
};

test('backfills matching phone activity from Home Assistant history', async () => {
  const requests: URL[] = [];
  const events: HomeAssistantStateChangedEvent[] = [];
  const fetchImpl: typeof fetch = async (input, init) => {
    const url = new URL(input.toString());
    requests.push(url);

    assert.equal((init?.headers as Record<string, string> | undefined)?.Authorization, 'Bearer test-home-assistant-token');

    if (url.pathname === '/api/states') {
      return jsonResponse([
        { entity_id: 'sensor.josh_iphone_activity', state: 'stationary' },
        { entity_id: 'sensor.josh_iphone_battery_level', state: '81' },
        { entity_id: 'light.kitchen', state: 'on' },
      ]);
    }

    if (url.pathname === '/api/history/period/2026-06-14T18:00:00.000Z') {
      assert.equal(url.searchParams.get('end_time'), '2026-06-15T18:00:00.000Z');
      assert.equal(
        url.searchParams.get('filter_entity_id'),
        'device_tracker.mallorys_iphone,sensor.josh_iphone_activity,sensor.josh_iphone_battery_level',
      );

      return jsonResponse([
        [
          {
            entity_id: 'device_tracker.mallorys_iphone',
            state: 'home',
            last_changed: '2026-06-15T17:00:00.000Z',
            attributes: { friendly_name: "Mallorys iPhone" },
          },
        ],
        [
          {
            entity_id: 'sensor.josh_iphone_activity',
            state: 'stationary',
            last_changed: '2026-06-15T16:00:00.000Z',
            attributes: { friendly_name: "Joshs iPhone Activity" },
          },
          {
            entity_id: 'sensor.josh_iphone_activity',
            state: 'walking',
            last_changed: '2026-06-15T17:30:00.000Z',
            attributes: { friendly_name: "Joshs iPhone Activity" },
          },
        ],
        [
          {
            entity_id: 'sensor.josh_iphone_battery_level',
            state: '81',
            last_changed: '2026-06-15T15:30:00.000Z',
            attributes: { friendly_name: "Joshs iPhone Battery Level", unit_of_measurement: '%' },
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

  assert.equal(eventCount, 4);
  assert.deepEqual(
    requests.map((request) => request.pathname),
    ['/api/states', '/api/history/period/2026-06-14T18:00:00.000Z'],
  );
  assert.deepEqual(
    events.map((event) => event.entityId),
    [
      'sensor.josh_iphone_battery_level',
      'sensor.josh_iphone_activity',
      'device_tracker.mallorys_iphone',
      'sensor.josh_iphone_activity',
    ],
  );
  assert.deepEqual(
    events.map((event) => event.occurredAt),
    [
      '2026-06-15T15:30:00.000Z',
      '2026-06-15T16:00:00.000Z',
      '2026-06-15T17:00:00.000Z',
      '2026-06-15T17:30:00.000Z',
    ],
  );
  assert.equal(events[0].ingestionSource, 'history');
  assert.match(events[0].id ?? '', /^ha-history-[a-f0-9]{24}$/);
  assert.equal(events[0].isInitialBackfillState, true);
  assert.equal(events[3].oldState, 'stationary');
  assert.equal(events[3].newState, 'walking');
  assert.equal(JSON.stringify(events).includes('test-home-assistant-token'), false);
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
