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
  assert.equal(response.overview.thermostatStatus.hvacAction, 'idle');
  assert.equal(response.overview.thermostatStatus.isStale, false);
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
