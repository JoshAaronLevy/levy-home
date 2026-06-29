import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { CreateToDoLocationRequest } from './contracts.js';
import type { DatabaseQuery } from './dbClient.js';
import { createToDoLocation, fetchToDoLocations } from './todoLocationStore.js';

test('fetchToDoLocations maps todo_locations rows into API contracts', async () => {
  const database: DatabaseQuery = async <Row extends Record<string, unknown> = Record<string, unknown>>(
    strings: TemplateStringsArray,
  ): Promise<Row[]> => {
    const query = strings.join('');

    if (!query.includes('FROM todo_locations')) {
      throw new Error(`Unexpected query: ${query}`);
    }

    return [
      {
        id: 2,
        name: 'Denver Pediatrics',
        address: '123 Wellness Way, Denver, CO',
        mapkitTitle: 'Denver Pediatrics',
        mapkitSubtitle: '123 Wellness Way',
        latitude: '39.7392',
        longitude: -104.9903,
        createdBy: '1',
        createdDate: new Date('2026-06-28T15:30:00.000Z'),
        lastUsedDate: '2026-06-29T12:00:00Z',
        useCount: '3',
        isActive: true,
        favoritedBy: JSON.stringify([1, '2', 'bad']),
      },
    ] as unknown as Row[];
  };

  const locations = await fetchToDoLocations(database);

  assert.deepEqual(locations, [
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
  ]);
});

test('createToDoLocation inserts a saved location with favorite user ids', async () => {
  let capturedValues: unknown[] = [];
  const request: CreateToDoLocationRequest = {
    name: 'Maple Vet Clinic',
    address: '456 Maple St, Denver, CO',
    mapkitTitle: 'Maple Vet Clinic',
    mapkitSubtitle: '456 Maple St',
    latitude: 39.75,
    longitude: -104.98,
    createdBy: 2,
    favoritedBy: [1, 2],
  };
  const database: DatabaseQuery = async <Row extends Record<string, unknown> = Record<string, unknown>>(
    strings: TemplateStringsArray,
    ...values: unknown[]
  ): Promise<Row[]> => {
    const query = strings.join('');
    capturedValues = values;

    if (!query.includes('INSERT INTO todo_locations')) {
      throw new Error(`Unexpected query: ${query}`);
    }

    return [
      {
        id: 3,
        name: request.name,
        address: request.address,
        mapkitTitle: request.mapkitTitle,
        mapkitSubtitle: request.mapkitSubtitle,
        latitude: request.latitude,
        longitude: request.longitude,
        createdBy: request.createdBy,
        createdDate: '2026-06-28T15:30:00.000Z',
        lastUsedDate: null,
        useCount: 0,
        isActive: true,
        favoritedBy: request.favoritedBy,
      },
    ] as unknown as Row[];
  };

  const location = await createToDoLocation(database, request);

  assert.deepEqual(capturedValues, [
    'Maple Vet Clinic',
    '456 Maple St, Denver, CO',
    'Maple Vet Clinic',
    '456 Maple St',
    39.75,
    -104.98,
    2,
    '[1,2]',
  ]);
  assert.deepEqual(location, {
    id: 3,
    name: 'Maple Vet Clinic',
    address: '456 Maple St, Denver, CO',
    mapkitTitle: 'Maple Vet Clinic',
    mapkitSubtitle: '456 Maple St',
    latitude: 39.75,
    longitude: -104.98,
    createdBy: 2,
    createdDate: '2026-06-28T15:30:00.000Z',
    useCount: 0,
    isActive: true,
    favoritedBy: [1, 2],
  });
});
