import assert from 'node:assert/strict';
import { afterEach, beforeEach, test } from 'node:test';

import { createApp } from '../../../src/app.js';
import { createRouteTestHarness } from '../../support/routeTestHarness.js';
import { testConfig } from '../../support/testConfig.js';

const routes = createRouteTestHarness();

beforeEach(async () => {
  await routes.start(createApp({ config: testConfig }));
});

afterEach(async () => {
  await routes.close();
});

test('GET /api/home/overview returns a narrow home overview', async () => {
  const response = await routes.getJSON('/api/home/overview');

  assert.equal(response.ok, true);
  assert.equal(response.overview.garageStatus.state, 'closed');
  assert.equal(response.overview.lightSummary.state, 'off');
  assert.equal(response.overview.lightSummary.groups.length, 2);
  assert.equal(response.overview.thermostatStatus.currentTemperature, 72);
  assert.equal(response.overview.thermostatStatus.targetTemperatureLow, 67);
  assert.equal(response.overview.thermostatStatus.targetTemperatureHigh, 72);
  assert.equal(response.overview.thermostatStatus.minimumTemperature, 45);
  assert.equal(response.overview.thermostatStatus.maximumTemperature, 95);
  assert.equal(response.overview.thermostatStatus.temperatureStep, 1);
  assert.equal(response.overview.thermostatStatus.hvacAction, 'idle');
  assert.equal(response.overview.thermostatStatus.isStale, false);
  assert.equal(response.overview.occupiedMeanTemperature, 73.8);
  assert.deepEqual(response.overview.roomTemperatures.map((reading: {
    id: string;
    name: string;
    temperature: number | null;
    isOccupied: boolean;
    isStale: boolean;
  }) => ({
    id: reading.id,
    name: reading.name,
    temperature: reading.temperature,
    isOccupied: reading.isOccupied,
    isStale: reading.isStale,
  })), [
    { id: 'study', name: 'Study', temperature: 69, isOccupied: true, isStale: false },
    { id: 'kitchen_family', name: 'Kitchen / Family', temperature: 72, isOccupied: true, isStale: false },
    { id: 'nursery', name: 'Nursery', temperature: 70, isOccupied: true, isStale: false },
    { id: 'master_bedroom', name: 'Master Bedroom', temperature: 68, isOccupied: false, isStale: false },
    { id: 'playroom', name: 'Playroom', temperature: 71, isOccupied: false, isStale: false },
  ]);
  assert.deepEqual(response.overview.presence, []);
});

test('GET /api/home/actions returns curated action IDs and light groups', async () => {
  const response = await routes.getJSON('/api/home/actions');

  assert.deepEqual(
    response.actions.map((action: { id: string }) => action.id),
    ['open_garage', 'close_garage', 'turn_off_all_lights', 'turn_on_light_group', 'turn_off_light_group'],
  );
  assert.equal(
    response.actions.find((action: { id: string }) => action.id === 'open_garage')?.requiresConfirmation,
    false,
  );
  assert.equal(
    response.actions.find((action: { id: string }) => action.id === 'close_garage')?.requiresConfirmation,
    true,
  );
  assert.deepEqual(response.lightGroups, [
    { id: 'upstairs_hallway', name: 'Upstairs Hallway' },
    { id: 'playroom', name: 'Playroom' },
  ]);
});

test('POST /api/home/actions performs only curated actions', async () => {
  const response = await routes.postJSON('/api/home/actions', {
    actionId: 'open_garage',
  });

  assert.equal(response.ok, true);
  assert.equal(response.result.actionId, 'open_garage');
  assert.equal(response.result.status, 'success');
  assert.equal(response.result.refreshedHomeOverview.garageStatus.state, 'open');
});

test('POST /api/home/actions performs curated light group actions', async () => {
  const turnOnResponse = await routes.postJSON('/api/home/actions', {
    actionId: 'turn_on_light_group',
    groupId: 'upstairs_hallway',
  });
  const response = await routes.postJSON('/api/home/actions', {
    actionId: 'turn_off_light_group',
    groupId: 'upstairs_hallway',
  });

  assert.equal(turnOnResponse.ok, true);
  assert.equal(turnOnResponse.result.actionId, 'turn_on_light_group');
  assert.equal(turnOnResponse.result.status, 'success');
  assert.equal(response.ok, true);
  assert.equal(response.result.actionId, 'turn_off_light_group');
  assert.equal(response.result.status, 'success');
});

test('POST /api/home/actions sets the thermostat range only when its minimum delta is valid', async () => {
  const response = await routes.postJSON('/api/home/actions', {
    actionId: 'set_thermostat_temperature',
    targetTemperatureLow: 65,
    targetTemperatureHigh: 71,
  });

  assert.equal(response.ok, true);
  assert.equal(response.result.actionId, 'set_thermostat_temperature');
  assert.equal(response.result.refreshedHomeOverview.thermostatStatus.targetTemperatureLow, 65);
  assert.equal(response.result.refreshedHomeOverview.thermostatStatus.targetTemperatureHigh, 71);

  const invalidResponse = await fetch(`${routes.baseURL()}/api/home/actions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      actionId: 'set_thermostat_temperature',
      targetTemperatureLow: 65,
      targetTemperatureHigh: 70,
    }),
  });
  const invalidBody = (await invalidResponse.json()) as { code: string };

  assert.equal(invalidResponse.status, 400);
  assert.equal(invalidBody.code, 'thermostat_minimum_delta_required');
});

test('POST /api/home/actions rejects arbitrary Home Assistant payloads', async () => {
  const response = await fetch(`${routes.baseURL()}/api/home/actions`, {
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
  const openGarage = await routes.postJSON('/api/home/actions/open-garage');
  const closeGarage = await routes.postJSON('/api/home/actions/close-garage');
  const lightsOff = await routes.postJSON('/api/home/actions/lights-off');
  const lightGroup = await routes.postJSON('/api/home/actions/light-groups/playroom/off');
  const lightGroupOn = await routes.postJSON('/api/home/actions/light-groups/playroom/on');

  assert.equal(openGarage.result.actionId, 'open_garage');
  assert.equal(closeGarage.result.actionId, 'close_garage');
  assert.equal(lightsOff.result.actionId, 'turn_off_all_lights');
  assert.equal(lightGroup.result.actionId, 'turn_off_light_group');
  assert.equal(lightGroupOn.result.actionId, 'turn_on_light_group');
});
