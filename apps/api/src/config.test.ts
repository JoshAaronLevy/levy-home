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

test('readConfig parses tracked Home Assistant phone activity configuration', () => {
  const config = readConfig({
    HOME_ASSISTANT_ACTIVITY_ENABLED: 'true',
    HOME_ASSISTANT_WEBSOCKET_URL: 'wss://example.ui.nabu.casa/api/websocket',
    HOME_ASSISTANT_PHONE_ENTITIES:
      "sensor.joshs_iphone_battery_level:Josh:Josh's iPhone,device_tracker.mallorys_iphone:Mallory:Mallory's iPhone",
    HOME_ASSISTANT_PHONE_ENTITY_PATTERNS:
      "sensor.joshs_iphone_*:Josh:Josh's iPhone,sensor.mallorys_iphone_*:Mallory:Mallory's iPhone",
  });

  assert.equal(config.homeAssistant.activity.isEnabled, true);
  assert.equal(config.homeAssistant.activity.webSocketURL, 'wss://example.ui.nabu.casa/api/websocket');
  assert.deepEqual(config.homeAssistant.activity.trackedPhoneEntities, [
    {
      entityId: 'sensor.joshs_iphone_battery_level',
      person: 'Josh',
      deviceName: "Josh's iPhone",
    },
    {
      entityId: 'device_tracker.mallorys_iphone',
      person: 'Mallory',
      deviceName: "Mallory's iPhone",
    },
  ]);
  assert.deepEqual(config.homeAssistant.activity.trackedPhoneEntityPatterns, [
    {
      pattern: 'sensor.joshs_iphone_*',
      person: 'Josh',
      deviceName: "Josh's iPhone",
    },
    {
      pattern: 'sensor.mallorys_iphone_*',
      person: 'Mallory',
      deviceName: "Mallory's iPhone",
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
