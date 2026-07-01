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

test('GET /api/users returns users from the configured store', async () => {
  await routes.restart(
    createApp({
      config: testConfig,
      userStore: {
        async fetchUsers() {
          return [
            {
              id: 1,
              firstName: 'Josh',
              lastName: 'Levy',
              email: 'josh@example.com',
            },
            {
              id: 2,
              firstName: 'Mallory',
              lastName: 'Levy',
              email: 'mallory@example.com',
              mobileDevice: 'Mallory iPhone',
              lastLogin: '2026-06-28T15:30:00.000Z',
            },
          ];
        },
      },
    }),
  );

  const response = await routes.getJSON('/api/users');

  assert.equal(response.ok, true);
  assert.equal(typeof response.generatedAt, 'string');
  assert.deepEqual(response.users, [
    {
      id: 1,
      firstName: 'Josh',
      lastName: 'Levy',
      email: 'josh@example.com',
    },
    {
      id: 2,
      firstName: 'Mallory',
      lastName: 'Levy',
      email: 'mallory@example.com',
      mobileDevice: 'Mallory iPhone',
      lastLogin: '2026-06-28T15:30:00.000Z',
    },
  ]);
});
