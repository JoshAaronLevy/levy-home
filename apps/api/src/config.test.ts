import assert from 'node:assert/strict';
import { test } from 'node:test';

import { readConfig } from './config.js';

test('readConfig defaults Home Assistant activity ingestion to disabled with no tracked phone entities', () => {
  const config = readConfig({});

  assert.equal(config.homeAssistant.activity.isEnabled, false);
  assert.equal(config.homeAssistant.activity.webSocketURL, undefined);
  assert.deepEqual(config.homeAssistant.activity.trackedPhoneEntities, []);
  assert.deepEqual(config.homeAssistant.activity.trackedPhoneEntityPatterns, []);
});

test('readConfig defaults Home Assistant light groups to empty instead of demo entities', () => {
  const config = readConfig({});

  assert.deepEqual(config.homeAssistant.lightGroups, []);
});

test('readConfig parses Kroger API diagnostic configuration', () => {
  const config = readConfig({
    KROGER_CLIENT_ID: 'client-id',
    KROGER_CLIENT_SECRET: 'client-secret',
    KROGER_API_BASE_URL: 'https://api.kroger.test/v1',
    KROGER_PRODUCT_RESPONSE_PATH: '/tmp/kroger-product-response.json',
    KROGER_NORMALIZED_PRODUCT_RESPONSE_PATH: '/tmp/kroger-products-normalized.json',
    KROGER_PRODUCT_SEARCH_LIMIT: '7',
    KROGER_LOCATION_ID: '62000008',
    KROGER_SHOPPING_STORE_ID: '2',
    KROGER_SHOPPING_STORE_NAME: 'King Soopers',
  });

  assert.equal(config.kroger.clientId, 'client-id');
  assert.equal(config.kroger.clientSecret, 'client-secret');
  assert.equal(config.kroger.apiBaseURL, 'https://api.kroger.test/v1');
  assert.equal(config.kroger.productResponseFilePath, '/tmp/kroger-product-response.json');
  assert.equal(config.kroger.normalizedProductResponseFilePath, '/tmp/kroger-products-normalized.json');
  assert.equal(config.kroger.productSearchLimit, 7);
  assert.equal(config.kroger.locationId, '62000008');
  assert.equal(config.kroger.shoppingStoreId, 2);
  assert.equal(config.kroger.shoppingStoreName, 'King Soopers');
});

test('readConfig parses quoted APNs private key env values with escaped newlines', () => {
  const config = readConfig({
    APNS_PRIVATE_KEY: '"-----BEGIN PRIVATE KEY-----\\nabc123\\n-----END PRIVATE KEY-----"',
  });

  assert.equal(config.apns.privateKey, '-----BEGIN PRIVATE KEY-----\nabc123\n-----END PRIVATE KEY-----');
});

test('readConfig rejects APNs private key values without .p8 markers', () => {
  assert.throws(
    () => readConfig({ APNS_PRIVATE_KEY: '"not-a-p8-key"' }),
    /APNS_PRIVATE_KEY is not a valid \.p8 private key value\./,
  );
});

test('readConfig parses curated Home Assistant light entities', () => {
  const config = readConfig({
    HOME_ASSISTANT_LIGHT_ENTITIES:
      'light.foyer_lights: Foyer, light.upstairs_hallway: Upstairs Hallway, light.playroom_lamp: Playroom',
  });

  assert.deepEqual(config.homeAssistant.lightEntities, [
    { id: 'foyer_lights', name: 'Foyer', entityId: 'light.foyer_lights' },
    { id: 'upstairs_hallway', name: 'Upstairs Hallway', entityId: 'light.upstairs_hallway' },
    { id: 'playroom_lamp', name: 'Playroom', entityId: 'light.playroom_lamp' },
  ]);
});

test('readConfig parses tracked Home Assistant phone activity configuration', () => {
  const config = readConfig({
    HOME_ASSISTANT_ACTIVITY_ENABLED: 'true',
    HOME_ASSISTANT_WEBSOCKET_URL: 'wss://example.ui.nabu.casa/api/websocket',
    HOME_ASSISTANT_PHONE_ENTITIES:
      "sensor.josh_iphone_battery_level:Josh:Joshs iPhone,device_tracker.mallorys_iphone:Mallory:Mallorys iPhone",
    HOME_ASSISTANT_PHONE_ENTITY_PATTERNS:
      "sensor.josh_iphone_*:Josh:Joshs iPhone,sensor.iphone_*:Mallory:Mallorys iPhone",
  });

  assert.equal(config.homeAssistant.activity.isEnabled, true);
  assert.equal(config.homeAssistant.activity.webSocketURL, 'wss://example.ui.nabu.casa/api/websocket');
  assert.deepEqual(config.homeAssistant.activity.trackedPhoneEntities, [
    {
      entityId: 'sensor.josh_iphone_battery_level',
      person: 'Josh',
      deviceName: "Joshs iPhone",
    },
    {
      entityId: 'device_tracker.mallorys_iphone',
      person: 'Mallory',
      deviceName: "Mallorys iPhone",
    },
  ]);
  assert.deepEqual(config.homeAssistant.activity.trackedPhoneEntityPatterns, [
    {
      pattern: 'sensor.josh_iphone_*',
      person: 'Josh',
      deviceName: "Joshs iPhone",
    },
    {
      pattern: 'sensor.iphone_*',
      person: 'Mallory',
      deviceName: "Mallorys iPhone",
    },
  ]);
});

test('readConfig rejects malformed phone activity configuration', () => {
  assert.throws(
    () => readConfig({ HOME_ASSISTANT_ACTIVITY_ENABLED: 'sometimes' }),
    /Invalid HOME_ASSISTANT_ACTIVITY_ENABLED/,
  );
  assert.throws(
    () => readConfig({ HOME_ASSISTANT_PHONE_ENTITIES: 'sensor.no_person' }),
    /Invalid HOME_ASSISTANT_PHONE_ENTITIES/,
  );
  assert.throws(
    () => readConfig({ HOME_ASSISTANT_PHONE_ENTITY_PATTERNS: 'bad pattern:Josh' }),
    /Invalid HOME_ASSISTANT_PHONE_ENTITY_PATTERNS/,
  );
});
