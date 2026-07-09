import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { EventPushStatus } from '../../../../src/contracts.js';
import {
  createWeatherAlertService,
  weatherAlertBody,
  weatherAlertEventsFromForecast,
  type WeatherAlertForecastPoint,
  type WeatherAlertForecastProvider,
} from '../../../../src/services/weather/weatherAlertService.js';
import type { WeatherAlertPushPayload } from '../../../../src/services/notifications/notificationService.js';

const baseConfig = {
  isEnabled: true,
  latitude: 39.5388289,
  longitude: -105.0305231,
  timeZone: 'America/Denver',
  forecastBaseURL: 'https://api.open-meteo.test/v1/forecast',
  pollIntervalMinutes: 30,
  leadTimeMinutes: 60,
  eventSeparationMinutes: 180,
};

test('weatherAlertEventsFromForecast keeps on-off precipitation inside a 3 hour period together', () => {
  const events = weatherAlertEventsFromForecast([
    forecastPoint('2026-07-01T14:00:00Z', 0),
    forecastPoint('2026-07-01T15:00:00Z', 0.35, 'light rain'),
    forecastPoint('2026-07-01T16:00:00Z', 0.25, 'light rain'),
    forecastPoint('2026-07-01T17:00:00Z', 0),
    forecastPoint('2026-07-01T19:00:00Z', 0.42, 'showers'),
    forecastPoint('2026-07-01T20:00:00Z', 0),
    forecastPoint('2026-07-01T23:00:00Z', 0.76, 'thunderstorms'),
    forecastPoint('2026-07-02T00:00:00Z', 0),
  ], 180);

  assert.equal(events.length, 2);
  assert.equal(events[0].start.toISOString(), '2026-07-01T15:00:00.000Z');
  assert.equal(events[0].end?.toISOString(), '2026-07-01T20:00:00.000Z');
  assert.equal(events[0].kind, 'showers');
  assert.equal(events[0].maximumChance, 0.42);
  assert.equal(events[1].start.toISOString(), '2026-07-01T23:00:00.000Z');
  assert.equal(events[1].kind, 'thunderstorms');
});

test('weatherAlertBody includes chance, kind, start time, and duration', () => {
  const event = weatherAlertEventsFromForecast([
    forecastPoint('2026-07-01T22:00:00Z', 0.74, 'thunderstorms'),
    forecastPoint('2026-07-02T01:00:00Z', 0),
  ], 180)[0];

  assert.equal(
    weatherAlertBody(event, new Date('2026-07-01T21:00:00Z'), 'America/Denver'),
    'High chance of thunderstorms in one hour, around 4 PM until 7 PM.',
  );
});

test('weather alert service sends due alerts once through notification service', async () => {
  const pushes: WeatherAlertPushPayload[] = [];
  const forecastProvider: WeatherAlertForecastProvider = {
    async fetchForecast() {
      return [
        forecastPoint('2026-07-01T14:00:00Z', 0),
        forecastPoint('2026-07-01T15:00:00Z', 0.28, 'light rain'),
        forecastPoint('2026-07-01T16:00:00Z', 0),
      ];
    },
  };
  const service = createWeatherAlertService({
    config: baseConfig,
    forecastProvider,
    logger: silentLogger(),
    now: () => new Date('2026-07-01T14:00:00Z'),
    notificationService: {
      async sendWeatherAlertPush(payload) {
        pushes.push(payload);
        return pushStatus(2);
      },
    },
  });

  const firstCheck = await service.checkNow();
  const secondCheck = await service.checkNow();

  assert.equal(firstCheck.length, 1);
  assert.equal(firstCheck[0].sentNotificationCount, 2);
  assert.equal(secondCheck.length, 0);
  assert.equal(pushes.length, 1);
  assert.equal(pushes[0].body, 'Slight chance of light rain in one hour, around 9 AM until 10 AM.');
});

test('weather alert service does not send alerts while disabled', async () => {
  const pushes: WeatherAlertPushPayload[] = [];
  const service = createWeatherAlertService({
    config: {
      ...baseConfig,
      isEnabled: false,
    },
    forecastProvider: {
      async fetchForecast() {
        return [
          forecastPoint('2026-07-01T15:00:00Z', 0.8, 'severe thunderstorms'),
        ];
      },
    },
    logger: silentLogger(),
    now: () => new Date('2026-07-01T14:00:00Z'),
    notificationService: {
      async sendWeatherAlertPush(payload) {
        pushes.push(payload);
        return pushStatus(1);
      },
    },
  });

  const statuses = await service.checkNow();

  assert.deepEqual(statuses, []);
  assert.deepEqual(pushes, []);
});

function forecastPoint(
  date: string,
  precipitationChance: number,
  kind?: WeatherAlertForecastPoint['kind'],
): WeatherAlertForecastPoint {
  return {
    date: new Date(date),
    precipitationChance,
    ...(kind ? { kind } : {}),
  };
}

function pushStatus(sentNotificationCount: number): EventPushStatus {
  return {
    attempted: true,
    skipped: false,
    sentNotificationCount,
  };
}

function silentLogger() {
  return {
    debug() {},
    error() {},
    info() {},
    warn() {},
  };
}
