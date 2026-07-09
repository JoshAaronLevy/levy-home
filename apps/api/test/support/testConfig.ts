import type { AppConfig } from '../../src/config.js';

export const testConfig: AppConfig = {
  port: 0,
  haWebhookSecret: 'test-secret',
  weatherAlerts: {
    isEnabled: false,
    latitude: 39.5388289,
    longitude: -105.0305231,
    timeZone: 'America/Denver',
    forecastBaseURL: 'https://api.open-meteo.test/v1/forecast',
    pollIntervalMinutes: 30,
    leadTimeMinutes: 60,
    eventSeparationMinutes: 180,
  },
  kroger: {
    clientId: 'test-kroger-client-id',
    clientSecret: 'test-kroger-client-secret',
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
