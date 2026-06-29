import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { DatabaseQuery } from './dbClient.js';
import { fetchUsersData } from './userStore.js';

test('fetchUsersData maps the users table into API contracts', async () => {
  const database: DatabaseQuery = async <Row extends Record<string, unknown> = Record<string, unknown>>(
    strings: TemplateStringsArray,
  ): Promise<Row[]> => {
    const query = strings.join('');

    if (!query.includes('FROM users')) {
      throw new Error(`Unexpected query: ${query}`);
    }

    return [
      {
        id: 1,
        firstName: 'Josh',
        lastName: 'Levy',
        email: 'josh@example.com',
        mobileDevice: null,
        lastLogin: new Date('2026-06-28T15:30:00.000Z'),
      },
      {
        id: '2',
        firstName: 'Mallory',
        lastName: 'Levy',
        email: 'mallory@example.com',
        mobileDevice: 'Mallory iPhone',
        lastLogin: null,
      },
    ] as unknown as Row[];
  };

  const users = await fetchUsersData(database);

  assert.deepEqual(users, [
    {
      id: 1,
      firstName: 'Josh',
      lastName: 'Levy',
      email: 'josh@example.com',
      lastLogin: '2026-06-28T15:30:00.000Z',
    },
    {
      id: 2,
      firstName: 'Mallory',
      lastName: 'Levy',
      email: 'mallory@example.com',
      mobileDevice: 'Mallory iPhone',
    },
  ]);
});
