import assert from 'node:assert/strict';
import { createServer, type IncomingMessage, type RequestListener, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { test } from 'node:test';

import type { AppConfig } from '../../../../src/config.js';
import { createHomeAssistantFacade } from '../../../../src/integrations/homeAssistant/facade.js';
import { LiveCameraFacade } from '../../../../src/integrations/homeAssistant/liveCameraFacade.js';

test('live Home Assistant facade opens and closes the configured garage cover', async () => {
  const serviceCalls: Array<{ path: string; body: unknown }> = [];
  const server = await startHomeAssistantServer(async (req, res) => {
    if (!req.url?.startsWith('/api/services/cover/')) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Not found' }));
      return;
    }

    serviceCalls.push({
      path: req.url,
      body: await readJSONBody(req),
    });

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify([]));
  });

  try {
    const facade = createHomeAssistantFacade(liveConfig(server.baseURL));

    await facade.openGarage();
    await facade.closeGarage();

    assert.deepEqual(serviceCalls, [
      {
        path: '/api/services/cover/open_cover',
        body: { entity_id: 'cover.meross_garage_door' },
      },
      {
        path: '/api/services/cover/close_cover',
        body: { entity_id: 'cover.meross_garage_door' },
      },
    ]);
  } finally {
    await server.close();
  }
});

test('live Home Assistant facade retrieves the configured thermostat temperatures', async () => {
  const server = await startHomeAssistantServer((req, res) => {
    assert.equal(req.url, '/api/states/climate.main_thermostat');
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      entity_id: 'climate.main_thermostat',
      state: 'heat_cool',
      last_updated: '2026-08-08T20:18:22.599773+00:00',
      attributes: {
        current_temperature: 74.2,
        target_temp_low: 65,
        target_temp_high: 70,
        min_temp: 44.6,
        max_temp: 95,
        target_temp_step: 0.5,
        hvac_action: 'cooling',
      },
    }));
  });

  try {
    const thermostat = await createHomeAssistantFacade(liveConfig(server.baseURL)).getThermostatStatus();

    assert.deepEqual(thermostat, {
      currentTemperature: 74.2,
      targetTemperatureLow: 65,
      targetTemperatureHigh: 70,
      minimumTemperature: 44.6,
      maximumTemperature: 95,
      temperatureStep: 0.5,
      hvacAction: 'cooling',
      lastUpdatedAt: '2026-08-08T20:18:22.599773+00:00',
      isStale: false,
    });
  } finally {
    await server.close();
  }
});

test('live Home Assistant facade retrieves the curated room temperatures without failing the whole overview for one unavailable sensor', async () => {
  const states = new Map<string, unknown>([
    [
      '/api/states/sensor.study_thermometer_study_temperature',
      { entity_id: 'sensor.study_thermometer_study_temperature', state: '73.94', last_updated: '2026-08-10T02:43:30.515809+00:00', attributes: {} },
    ],
    [
      '/api/states/sensor.study_govee_thermometer_study_temperature',
      { entity_id: 'sensor.study_govee_thermometer_study_temperature', state: '69.8', last_updated: '2026-08-10T02:43:04.904630+00:00', attributes: {} },
    ],
    [
      '/api/states/sensor.nursery_thermometer_nursery_temperature',
      { entity_id: 'sensor.nursery_thermometer_nursery_temperature', state: '70.52', last_updated: '2026-08-10T02:43:50.491549+00:00', attributes: {} },
    ],
    [
      '/api/states/sensor.master_bedroom_thermometer_master_bedroom_temperature',
      { entity_id: 'sensor.master_bedroom_thermometer_master_bedroom_temperature', state: '72.68', last_updated: '2026-08-10T02:43:15.585695+00:00', attributes: {} },
    ],
    [
      '/api/states/schedule.study_occupied',
      { entity_id: 'schedule.study_occupied', state: 'on', attributes: {} },
    ],
    [
      '/api/states/schedule.kitchen_family_room_occupied',
      { entity_id: 'schedule.kitchen_family_room_occupied', state: 'on', attributes: {} },
    ],
    [
      '/api/states/schedule.nursery_occupied',
      { entity_id: 'schedule.nursery_occupied', state: 'on', attributes: {} },
    ],
    [
      '/api/states/schedule.master_bedroom_occupied',
      { entity_id: 'schedule.master_bedroom_occupied', state: 'off', attributes: {} },
    ],
    [
      '/api/states/schedule.playroom_occupied',
      { entity_id: 'schedule.playroom_occupied', state: 'off', attributes: {} },
    ],
  ]);
  const server = await startHomeAssistantServer((req, res) => {
    const state = req.url ? states.get(req.url) : undefined;

    if (!state) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Not found' }));
      return;
    }

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(state));
  });

  try {
    const temperatures = await createHomeAssistantFacade(liveConfig(server.baseURL)).getRoomTemperatures();

    assert.deepEqual(temperatures, [
      { id: 'study', name: 'Study', temperature: 73.94, isOccupied: true, lastUpdatedAt: '2026-08-10T02:43:30.515809+00:00', isStale: false },
      { id: 'kitchen_family', name: 'Kitchen / Family', temperature: 69.8, isOccupied: true, lastUpdatedAt: '2026-08-10T02:43:04.904630+00:00', isStale: false },
      { id: 'nursery', name: 'Nursery', temperature: 70.52, isOccupied: true, lastUpdatedAt: '2026-08-10T02:43:50.491549+00:00', isStale: false },
      { id: 'master_bedroom', name: 'Master Bedroom', temperature: 72.68, isOccupied: false, lastUpdatedAt: '2026-08-10T02:43:15.585695+00:00', isStale: false },
      { id: 'playroom', name: 'Playroom', temperature: null, isOccupied: false, isStale: true },
    ]);
  } finally {
    await server.close();
  }
});

test('live Home Assistant facade retrieves the occupied mean temperature helper without making the overview fail if it is unavailable', async () => {
  const server = await startHomeAssistantServer((req, res) => {
    if (req.url !== '/api/states/sensor.occupied_mean_temperature') {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Not found' }));
      return;
    }

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ entity_id: 'sensor.occupied_mean_temperature', state: '73.8', attributes: {} }));
  });

  try {
    const facade = createHomeAssistantFacade(liveConfig(server.baseURL));

    assert.equal(await facade.getOccupiedMeanTemperature(), 73.8);
  } finally {
    await server.close();
  }
});

test('live Home Assistant facade sets the configured thermostat range', async () => {
  const serviceCalls: Array<{ path: string; body: unknown }> = [];
  const server = await startHomeAssistantServer(async (req, res) => {
    assert.equal(req.url, '/api/services/climate/set_temperature');
    serviceCalls.push({
      path: req.url,
      body: await readJSONBody(req),
    });
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify([]));
  });

  try {
    await createHomeAssistantFacade(liveConfig(server.baseURL)).setThermostatTemperatures(63, 70);

    assert.deepEqual(serviceCalls, [
      {
        path: '/api/services/climate/set_temperature',
        body: {
          entity_id: 'climate.main_thermostat',
          target_temp_low: 63,
          target_temp_high: 70,
        },
      },
    ]);
  } finally {
    await server.close();
  }
});

test('live Home Assistant facade summarizes configured light groups without an all-lights entity', async () => {
  const requestedPaths: string[] = [];
  const states = new Map<string, unknown>([
    [
      '/api/states/light.foyer_lights',
      {
        entity_id: 'light.foyer_lights',
        state: 'on',
        attributes: { entity_id: ['light.foyer_entry', 'light.foyer_stairway'] },
      },
    ],
    [
      '/api/states/light.playroom',
      {
        entity_id: 'light.playroom',
        state: 'off',
        attributes: {
          entity_id: ['light.playroom_1', 'light.playroom_2', 'light.playroom_3', 'light.playroom_4'],
        },
      },
    ],
  ]);
  const server = await startHomeAssistantServer(async (req, res) => {
    requestedPaths.push(req.url ?? '');
    const state = req.url ? states.get(req.url) : undefined;

    if (!state) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Not found' }));
      return;
    }

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(state));
  });

  try {
    const facade = createHomeAssistantFacade({
      ...liveConfig(server.baseURL),
      homeAssistant: {
        ...liveConfig(server.baseURL).homeAssistant,
        allLightsEntityId: undefined,
        lightGroups: [
          { id: 'foyer', name: 'Foyer', entityId: 'light.foyer_lights' },
          { id: 'playroom', name: 'Playroom', entityId: 'light.playroom' },
        ],
      },
    });

    const summary = await facade.getLightSummaryInputs();

    assert.deepEqual(requestedPaths.sort(), [
      '/api/states/light.foyer_lights',
      '/api/states/light.playroom',
    ]);
    assert.deepEqual(summary, {
      allLights: {
        id: 'all_lights',
        name: 'All lights',
        state: 'partially_on',
        lightsOnCount: 2,
        totalLightCount: 6,
      },
      groups: [
        {
          id: 'foyer',
          name: 'Foyer',
          state: 'on',
          lightsOnCount: 2,
          totalLightCount: 2,
        },
        {
          id: 'playroom',
          name: 'Playroom',
          state: 'off',
          lightsOnCount: 0,
          totalLightCount: 4,
        },
      ],
    });
  } finally {
    await server.close();
  }
});

test('live Home Assistant facade preserves unavailable light state', async () => {
  const states = new Map<string, unknown>([
    [
      '/api/states/light.study_lamp_1',
      {
        entity_id: 'light.study_lamp_1',
        state: 'unavailable',
      },
    ],
  ]);
  const server = await startHomeAssistantServer(async (req, res) => {
    const state = req.url ? states.get(req.url) : undefined;

    if (!state) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Not found' }));
      return;
    }

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(state));
  });

  try {
    const facade = createHomeAssistantFacade({
      ...liveConfig(server.baseURL),
      homeAssistant: {
        ...liveConfig(server.baseURL).homeAssistant,
        allLightsEntityId: undefined,
        lightGroups: [],
        lightEntities: [{ id: 'study_lamp_1', name: 'Study Lamp 1', entityId: 'light.study_lamp_1' }],
      },
    });

    const summary = await facade.getLightSummaryInputs();

    assert.deepEqual(summary, {
      allLights: {
        id: 'all_lights',
        name: 'All lights',
        state: 'unavailable',
        lightsOnCount: 0,
        totalLightCount: 1,
      },
      groups: [
        {
          id: 'study_lamp_1',
          name: 'Study Lamp 1',
          state: 'unavailable',
          lightsOnCount: 0,
          totalLightCount: 1,
        },
      ],
    });
  } finally {
    await server.close();
  }
});

test('live Home Assistant facade counts grouped light entities configured as light targets', async () => {
  const states = new Map<string, unknown>([
    [
      '/api/states/light.playroom',
      {
        entity_id: 'light.playroom',
        state: 'on',
        attributes: {
          entity_id: ['light.playroom_1', 'light.playroom_2', 'light.playroom_3', 'light.playroom_4'],
        },
      },
    ],
    [
      '/api/states/light.garage_entry',
      {
        entity_id: 'light.garage_entry',
        state: 'off',
        attributes: {
          entity_id: ['light.garage_entry_light'],
        },
      },
    ],
  ]);
  const server = await startHomeAssistantServer(async (req, res) => {
    const state = req.url ? states.get(req.url) : undefined;

    if (!state) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Not found' }));
      return;
    }

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(state));
  });

  try {
    const facade = createHomeAssistantFacade({
      ...liveConfig(server.baseURL),
      homeAssistant: {
        ...liveConfig(server.baseURL).homeAssistant,
        allLightsEntityId: undefined,
        lightGroups: [],
        lightEntities: [
          { id: 'playroom', name: 'Playroom', entityId: 'light.playroom' },
          { id: 'garage_entry', name: 'Garage Entry', entityId: 'light.garage_entry' },
        ],
      },
    });

    const summary = await facade.getLightSummaryInputs();

    assert.deepEqual(summary, {
      allLights: {
        id: 'all_lights',
        name: 'All lights',
        state: 'partially_on',
        lightsOnCount: 4,
        totalLightCount: 5,
      },
      groups: [
        {
          id: 'playroom',
          name: 'Playroom',
          state: 'on',
          lightsOnCount: 4,
          totalLightCount: 4,
        },
        {
          id: 'garage_entry',
          name: 'Garage Entry',
          state: 'off',
          lightsOnCount: 0,
          totalLightCount: 1,
        },
      ],
    });
  } finally {
    await server.close();
  }
});

test('live Home Assistant facade turns off configured light groups when no all-lights entity is configured', async () => {
  const serviceCalls: Array<{ path: string; body: unknown }> = [];
  const server = await startHomeAssistantServer(async (req, res) => {
    if (req.url !== '/api/services/light/turn_off') {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Not found' }));
      return;
    }

    serviceCalls.push({
      path: req.url,
      body: await readJSONBody(req),
    });

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify([]));
  });

  try {
    const facade = createHomeAssistantFacade({
      ...liveConfig(server.baseURL),
      homeAssistant: {
        ...liveConfig(server.baseURL).homeAssistant,
        allLightsEntityId: undefined,
        lightGroups: [
          { id: 'foyer', name: 'Foyer', entityId: 'light.foyer_lights' },
          { id: 'playroom', name: 'Playroom', entityId: 'light.playroom' },
        ],
      },
    });

    await facade.turnOffAllLights();

    assert.deepEqual(serviceCalls, [
      {
        path: '/api/services/light/turn_off',
        body: { entity_id: ['light.foyer_lights', 'light.playroom'] },
      },
    ]);
  } finally {
    await server.close();
  }
});

test('live Home Assistant facade turns on configured light targets', async () => {
  const serviceCalls: Array<{ path: string; body: unknown }> = [];
  const server = await startHomeAssistantServer(async (req, res) => {
    if (req.url !== '/api/services/light/turn_on') {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Not found' }));
      return;
    }

    serviceCalls.push({
      path: req.url,
      body: await readJSONBody(req),
    });

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify([]));
  });

  try {
    const facade = createHomeAssistantFacade({
      ...liveConfig(server.baseURL),
      homeAssistant: {
        ...liveConfig(server.baseURL).homeAssistant,
        allLightsEntityId: undefined,
        lightEntities: [
          { id: 'kitchen_cans', name: 'Kitchen Cans', entityId: 'light.kitchen_cans' },
        ],
      },
    });

    await facade.turnOnLightGroup('kitchen_cans');

    assert.deepEqual(serviceCalls, [
      {
        path: '/api/services/light/turn_on',
        body: { entity_id: 'light.kitchen_cans' },
      },
    ]);
  } finally {
    await server.close();
  }
});

test('live Home Assistant facade turns off configured light targets', async () => {
  const serviceCalls: Array<{ path: string; body: unknown }> = [];
  const server = await startHomeAssistantServer(async (req, res) => {
    if (req.url !== '/api/services/light/turn_off') {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Not found' }));
      return;
    }

    serviceCalls.push({
      path: req.url,
      body: await readJSONBody(req),
    });

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify([]));
  });

  try {
    const facade = createHomeAssistantFacade({
      ...liveConfig(server.baseURL),
      homeAssistant: {
        ...liveConfig(server.baseURL).homeAssistant,
        allLightsEntityId: undefined,
        lightEntities: [
          { id: 'kitchen_cans', name: 'Kitchen Cans', entityId: 'light.kitchen_cans' },
        ],
      },
    });

    await facade.turnOffLightGroup('kitchen_cans');

    assert.deepEqual(serviceCalls, [
      {
        path: '/api/services/light/turn_off',
        body: { entity_id: 'light.kitchen_cans' },
      },
    ]);
  } finally {
    await server.close();
  }
});

test('live Home Assistant facade returns per-person device tracker presence', async () => {
  const states = new Map<string, unknown>([
    [
      '/api/states/device_tracker.josh_iphone',
      {
        entity_id: 'device_tracker.josh_iphone',
        state: 'not_home',
        last_updated: '2026-06-20T18:00:00.000Z',
      },
    ],
    [
      '/api/states/device_tracker.mallorys_iphone',
      {
        entity_id: 'device_tracker.mallorys_iphone',
        state: 'home',
        last_updated: '2026-06-20T18:01:00.000Z',
      },
    ],
  ]);
  const server = await startHomeAssistantServer(async (req, res) => {
    const state = req.url ? states.get(req.url) : undefined;

    if (!state) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Not found' }));
      return;
    }

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(state));
  });

  try {
    const facade = createHomeAssistantFacade({
      ...liveConfig(server.baseURL),
      homeAssistant: {
        ...liveConfig(server.baseURL).homeAssistant,
        activity: {
          isEnabled: true,
          trackedPhoneEntityPatterns: [],
          trackedPhoneEntities: [
            { entityId: 'sensor.josh_iphone_battery_level', person: 'Josh', deviceName: "Joshs iPhone" },
            { entityId: 'device_tracker.josh_iphone', person: 'Josh', deviceName: "Joshs iPhone" },
            { entityId: 'device_tracker.josh_watch', person: 'Josh', deviceName: 'Josh Watch' },
            { entityId: 'device_tracker.mallorys_iphone', person: 'Mallory', deviceName: "Mallorys iPhone" },
          ],
        },
      },
    });

    const presence = await facade.getPresenceStatuses();

    assert.deepEqual(presence, [
      {
        person: 'Josh',
        state: 'away',
        entityId: 'device_tracker.josh_iphone',
        deviceName: "Joshs iPhone",
        lastUpdatedAt: '2026-06-20T18:00:00.000Z',
        isStale: false,
      },
      {
        person: 'Mallory',
        state: 'home',
        entityId: 'device_tracker.mallorys_iphone',
        deviceName: "Mallorys iPhone",
        lastUpdatedAt: '2026-06-20T18:01:00.000Z',
        isStale: false,
      },
    ]);
  } finally {
    await server.close();
  }
});

test('live camera facade builds its MJPEG response from uncached latest snapshots', async () => {
  const requestedURLs: string[] = [];
  const server = await startHomeAssistantServer((req, res) => {
    requestedURLs.push(req.url ?? '');
    res.writeHead(200, { 'Content-Type': 'image/jpeg' });
    res.end(Buffer.from([0xff, 0xd8, requestedURLs.length, 0xff, 0xd9]));
  });

  try {
    const facade = new LiveCameraFacade(liveConfig(server.baseURL));
    const response = await facade.openStream();
    const reader = response.body!.getReader();

    await reader.read();
    await reader.read();
    await reader.cancel();

    assert.equal(requestedURLs.length, 2);
    for (const requestedURL of requestedURLs) {
      const url = new URL(requestedURL, server.baseURL);
      assert.equal(url.pathname, '/api/camera_proxy/camera.kids_room');
      assert.ok(url.searchParams.has('ts'));
    }
  } finally {
    await server.close();
  }
});

function liveConfig(baseURL: string): AppConfig {
  return {
    port: 0,
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
      baseURL,
      token: 'test-home-assistant-token',
      garageCoverEntityId: 'cover.meross_garage_door',
      thermostatClimateEntityId: 'climate.main_thermostat',
      allLightsEntityId: 'light.all_lights',
      lightGroups: [],
      lightEntities: [],
      camera: {
        id: 'kids_room',
        displayName: 'Kids Room',
        entityId: 'camera.kids_room',
        speakerVolumeEntityId: 'number.kids_room_speaker_volume',
        accessToken: 'test-camera-access-token',
      },
      mockTotalLightCount: 12,
      activity: {
        isEnabled: false,
        trackedPhoneEntities: [],
        trackedPhoneEntityPatterns: [],
      },
    },
  };
}

async function startHomeAssistantServer(
  handler: RequestListener,
): Promise<{ baseURL: string; close: () => Promise<void> }> {
  const server: Server = createServer((req, res) => {
    if (req.headers.authorization !== 'Bearer test-home-assistant-token') {
      res.writeHead(401, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Unauthorized' }));
      return;
    }

    void handler(req, res);
  });

  await new Promise<void>((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      resolve();
    });
  });

  const address = server.address() as AddressInfo;

  return {
    baseURL: `http://127.0.0.1:${address.port}`,
    close: () =>
      new Promise<void>((resolve, reject) => {
        server.close((error) => {
          if (error) {
            reject(error);
            return;
          }

          resolve();
        });
      }),
  };
}

async function readJSONBody(req: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];

  for await (const chunk of req) {
    chunks.push(Buffer.from(chunk));
  }

  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}
