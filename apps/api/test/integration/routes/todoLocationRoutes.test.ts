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

test('GET and POST /api/todo/locations use the configured to-do location store', async () => {
  let capturedCreate: unknown;

  await routes.restart(
    createApp({
      config: testConfig,
      toDoLocationStore: {
        async fetchLocations() {
          return [
            {
              id: 2,
              name: 'Denver Pediatrics',
              address: '123 Wellness Way, Denver, CO',
              mapkitTitle: 'Denver Pediatrics',
              mapkitSubtitle: '123 Wellness Way',
              latitude: 39.7392,
              longitude: -104.9903,
              createdBy: 1,
              createdDate: '2026-06-28T15:30:00.000Z',
              lastUsedDate: '2026-06-29T12:00:00.000Z',
              useCount: 3,
              isActive: true,
              favoritedBy: [1, 2],
            },
          ];
        },
        async createLocation(request) {
          capturedCreate = request;

          return {
            id: 3,
            name: request.name,
            ...(request.address ? { address: request.address } : {}),
            ...(request.mapkitTitle ? { mapkitTitle: request.mapkitTitle } : {}),
            ...(request.mapkitSubtitle ? { mapkitSubtitle: request.mapkitSubtitle } : {}),
            ...(request.latitude !== undefined && request.latitude !== null ? { latitude: request.latitude } : {}),
            ...(request.longitude !== undefined && request.longitude !== null ? { longitude: request.longitude } : {}),
            ...(request.createdBy !== undefined && request.createdBy !== null ? { createdBy: request.createdBy } : {}),
            createdDate: '2026-06-28T16:00:00.000Z',
            useCount: 0,
            isActive: true,
            favoritedBy: request.favoritedBy ?? [],
          };
        },
      },
    }),
  );

  const locations = await routes.getJSON('/api/todo/locations');
  const created = await routes.postJSON('/api/todo/locations', {
    name: 'Maple Vet Clinic',
    address: '456 Maple St, Denver, CO',
    mapkitTitle: 'Maple Vet Clinic',
    mapkitSubtitle: '456 Maple St',
    latitude: 39.75,
    longitude: -104.98,
    createdBy: 2,
    favoritedBy: [1, 2, 1],
  });

  assert.equal(locations.ok, true);
  assert.equal(typeof locations.generatedAt, 'string');
  assert.deepEqual(locations.locations[0].favoritedBy, [1, 2]);
  assert.deepEqual(capturedCreate, {
    name: 'Maple Vet Clinic',
    address: '456 Maple St, Denver, CO',
    mapkitTitle: 'Maple Vet Clinic',
    mapkitSubtitle: '456 Maple St',
    latitude: 39.75,
    longitude: -104.98,
    createdBy: 2,
    favoritedBy: [1, 2],
  });
  assert.equal(created.ok, true);
  assert.equal(created.location.name, 'Maple Vet Clinic');
  assert.deepEqual(created.location.favoritedBy, [1, 2]);
});
