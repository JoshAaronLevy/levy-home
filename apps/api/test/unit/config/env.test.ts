import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';

import { readConfig } from '../../../src/config.js';

const testApnsPrivateKey = crypto
  .generateKeyPairSync('ec', { namedCurve: 'prime256v1' })
  .privateKey.export({ type: 'pkcs8', format: 'pem' })
  .toString();

test('readConfig defaults Home Assistant activity ingestion to disabled with no tracked phone entities', () => {
  const config = readConfig({});

  assert.equal(config.homeAssistant.activity.isEnabled, false);
  assert.equal(config.homeAssistant.activity.webSocketURL, undefined);
  assert.deepEqual(config.homeAssistant.activity.trackedPhoneEntities, []);
  assert.deepEqual(config.homeAssistant.activity.trackedPhoneEntityPatterns, []);
});

test('readConfig defaults Home Assistant light targets to empty instead of demo entities', () => {
  const config = readConfig({});

  assert.equal(config.homeAssistant.allLightsEntityId, undefined);
  assert.deepEqual(config.homeAssistant.lightGroups, []);
  assert.deepEqual(config.homeAssistant.lightEntities, []);
});

test('readConfig uses the verified thermostat climate entity and accepts a climate override', () => {
  assert.equal(readConfig({}).homeAssistant.thermostatClimateEntityId, 'climate.thermostat');
  assert.equal(
    readConfig({ HOME_ASSISTANT_THERMOSTAT_CLIMATE_ENTITY_ID: 'climate.downstairs' }).homeAssistant
      .thermostatClimateEntityId,
    'climate.downstairs',
  );
  assert.throws(
    () => readConfig({ HOME_ASSISTANT_THERMOSTAT_CLIMATE_ENTITY_ID: 'sensor.thermostat_temperature' }),
    /must be a climate entity ID/,
  );
});

test('readConfig uses the verified room-temperature sensors and accepts an exact override', () => {
  assert.deepEqual(readConfig({}).homeAssistant.roomTemperatureSensors, [
    { id: 'study', name: 'Study', entityId: 'sensor.study_thermometer_study_temperature', occupancyEntityId: 'schedule.study_occupied' },
    { id: 'kitchen_family', name: 'Kitchen / Family', entityId: 'sensor.study_govee_thermometer_study_temperature', occupancyEntityId: 'schedule.kitchen_family_room_occupied' },
    { id: 'nursery', name: 'Nursery', entityId: 'sensor.nursery_thermometer_nursery_temperature', occupancyEntityId: 'schedule.nursery_occupied' },
    { id: 'master_bedroom', name: 'Master Bedroom', entityId: 'sensor.master_bedroom_thermometer_master_bedroom_temperature', occupancyEntityId: 'schedule.master_bedroom_occupied' },
    { id: 'playroom', name: 'Playroom', entityId: 'sensor.playroom_thermometer_playroom_temperature', occupancyEntityId: 'schedule.playroom_occupied' },
  ]);

  const config = readConfig({
    HOME_ASSISTANT_ROOM_TEMPERATURE_SENSORS:
      'study:Study:sensor.study_temperature,kitchen_family:Kitchen / Family:sensor.family_temperature,nursery:Nursery:sensor.nursery_temperature,master_bedroom:Master Bedroom:sensor.master_temperature,playroom:Playroom:sensor.playroom_temperature',
  });

  assert.equal(config.homeAssistant.roomTemperatureSensors?.[1]?.entityId, 'sensor.family_temperature');
  assert.equal(config.homeAssistant.roomTemperatureSensors?.[1]?.occupancyEntityId, 'schedule.kitchen_family_room_occupied');
  assert.throws(
    () => readConfig({ HOME_ASSISTANT_ROOM_TEMPERATURE_SENSORS: 'study:Study:sensor.study_temperature' }),
    /must configure each of the five Levy Home room IDs exactly once/,
  );
});

test('readConfig uses the occupied-mean temperature helper and accepts a sensor override', () => {
  assert.equal(readConfig({}).homeAssistant.occupiedMeanTemperatureEntityId, 'sensor.occupied_mean_temperature');
  assert.equal(
    readConfig({ HOME_ASSISTANT_OCCUPIED_MEAN_TEMPERATURE_ENTITY_ID: 'sensor.downstairs_occupied_mean_temperature' })
      .homeAssistant.occupiedMeanTemperatureEntityId,
    'sensor.downstairs_occupied_mean_temperature',
  );
  assert.throws(
    () => readConfig({ HOME_ASSISTANT_OCCUPIED_MEAN_TEMPERATURE_ENTITY_ID: 'input_number.occupied_mean_temperature' }),
    /must be a sensor entity ID/,
  );
});

test('readConfig uses only the curated Kids Room camera and validates its entity types', () => {
  const defaults = readConfig({});
  assert.deepEqual(defaults.homeAssistant.camera, {
    id: 'kids_room',
    displayName: 'Kids Room',
    entityId: 'camera.kids_room',
    speakerVolumeEntityId: 'number.kids_room_speaker_volume',
  });

  const configured = readConfig({
    HOME_ASSISTANT_KIDS_ROOM_CAMERA_ENTITY_ID: 'camera.nursery',
    HOME_ASSISTANT_KIDS_ROOM_SPEAKER_VOLUME_ENTITY_ID: 'number.nursery_speaker_volume',
  });
  assert.equal(configured.homeAssistant.camera.entityId, 'camera.nursery');
  assert.equal(configured.homeAssistant.camera.speakerVolumeEntityId, 'number.nursery_speaker_volume');

  assert.throws(
    () => readConfig({ HOME_ASSISTANT_KIDS_ROOM_CAMERA_ENTITY_ID: 'light.nursery' }),
    /Kids Room camera configuration/,
  );
  assert.throws(
    () => readConfig({ HOME_ASSISTANT_MODE: 'live' }),
    /LEVY_HOME_CAMERA_ACCESS_TOKEN is required/,
  );
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

test('readConfig requests up to 50 Kroger products by default and clamps larger limits', () => {
  assert.equal(readConfig({}).kroger.productSearchLimit, 50);
  assert.equal(readConfig({ KROGER_PRODUCT_SEARCH_LIMIT: '75' }).kroger.productSearchLimit, 50);
});

test('readConfig parses weather alert configuration', () => {
  const config = readConfig({
    WEATHER_ALERTS_ENABLED: 'true',
    WEATHER_ALERTS_LATITUDE: '39.5',
    WEATHER_ALERTS_LONGITUDE: '-105.1',
    WEATHER_ALERTS_TIME_ZONE: 'America/Denver',
    WEATHER_ALERTS_FORECAST_BASE_URL: 'https://api.open-meteo.test/v1/forecast',
    WEATHER_ALERTS_POLL_INTERVAL_MINUTES: '15',
    WEATHER_ALERTS_LEAD_TIME_MINUTES: '60',
    WEATHER_ALERTS_EVENT_SEPARATION_MINUTES: '180',
  });

  assert.equal(config.weatherAlerts.isEnabled, true);
  assert.equal(config.weatherAlerts.latitude, 39.5);
  assert.equal(config.weatherAlerts.longitude, -105.1);
  assert.equal(config.weatherAlerts.timeZone, 'America/Denver');
  assert.equal(config.weatherAlerts.forecastBaseURL, 'https://api.open-meteo.test/v1/forecast');
  assert.equal(config.weatherAlerts.pollIntervalMinutes, 15);
  assert.equal(config.weatherAlerts.leadTimeMinutes, 60);
  assert.equal(config.weatherAlerts.eventSeparationMinutes, 180);
});

test('readConfig parses quoted APNs private key env values with escaped newlines', () => {
  const config = readConfig({
    APNS_PRIVATE_KEY: `"${testApnsPrivateKey.replace(/\n/g, '\\n')}"`,
  });

  assert.equal(config.apns.privateKey, testApnsPrivateKey.trim());
  assert.equal(config.apns.privateKeySource, 'inline');
});

test('readConfig loads APNs private key env values from APNS_PRIVATE_KEY_PATH', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'levy-home-apns-'));
  const privateKeyPath = path.join(tempDir, 'AuthKey_TEST.p8');

  fs.writeFileSync(privateKeyPath, testApnsPrivateKey);

  const config = readConfig({
    APNS_PRIVATE_KEY_PATH: privateKeyPath,
  });

  assert.equal(config.apns.privateKey, testApnsPrivateKey.trim());
  assert.equal(config.apns.privateKeySource, 'path');
  assert.equal(config.apns.privateKeyPath, privateKeyPath);
  assert.equal(config.apns.inlinePrivateKeyIgnored, false);
});

test('readConfig prefers APNS_PRIVATE_KEY_PATH over APNS_PRIVATE_KEY', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'levy-home-apns-'));
  const privateKeyPath = path.join(tempDir, 'AuthKey_TEST.p8');

  fs.writeFileSync(privateKeyPath, testApnsPrivateKey);

  const config = readConfig({
    APNS_PRIVATE_KEY_PATH: privateKeyPath,
    APNS_PRIVATE_KEY: 'not-used',
  });

  assert.equal(config.apns.privateKey, testApnsPrivateKey.trim());
  assert.equal(config.apns.privateKeySource, 'path');
  assert.equal(config.apns.inlinePrivateKeyIgnored, true);
});

test('readConfig reports APNS_PRIVATE_KEY_PATH load failures without falling back to inline keys', () => {
  const config = readConfig({
    APNS_PRIVATE_KEY_PATH: '/tmp/levy-home-missing-apns-key.p8',
    APNS_PRIVATE_KEY: `"${testApnsPrivateKey.replace(/\n/g, '\\n')}"`,
  });

  assert.equal(config.apns.privateKey, undefined);
  assert.equal(config.apns.privateKeySource, 'path');
  assert.match(config.apns.privateKeyLoadError ?? '', /ENOENT/);
  assert.equal(config.apns.inlinePrivateKeyIgnored, true);
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
      'light.foyer_lights: Foyer, light.upstairs_hallway: Upstairs Hallway, light.playroom: Playroom',
  });

  assert.deepEqual(config.homeAssistant.lightEntities, [
    { id: 'foyer_lights', name: 'Foyer', entityId: 'light.foyer_lights' },
    { id: 'upstairs_hallway', name: 'Upstairs Hallway', entityId: 'light.upstairs_hallway' },
    { id: 'playroom', name: 'Playroom', entityId: 'light.playroom' },
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
