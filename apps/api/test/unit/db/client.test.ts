import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  createDatabaseQuery,
  createDatabaseTransactionRunner,
  type DatabaseSQLClient,
} from '../../../src/db/client.js';

test('createDatabaseQuery parameterizes tagged-template values', async () => {
  const calls: Array<{ text: string; values: unknown[] }> = [];
  const database = createDatabaseQuery({
    async query(text, values = []) {
      calls.push({ text, values });
      return { rows: [{ id: 7 }] };
    },
  });

  const rows = await database`SELECT id FROM example WHERE name = ${'Milk'} AND quantity = ${2}`;

  assert.deepEqual(rows, [{ id: 7 }]);
  assert.deepEqual(calls, [{
    text: 'SELECT id FROM example WHERE name = $1 AND quantity = $2',
    values: ['Milk', 2],
  }]);
});

test('transaction runner commits operations through the same client', async () => {
  const calls: string[] = [];
  const client: DatabaseSQLClient = {
    async query(text) {
      calls.push(text);
      return { rows: text.includes('RETURNING') ? [{ id: 'trip-1' }] : [] };
    },
    release() {
      calls.push('RELEASE');
    },
  };
  const transaction = createDatabaseTransactionRunner(async () => client);

  const result = await transaction(async (database) => {
    const [row] = await database<{ id: string }>`INSERT INTO trips DEFAULT VALUES RETURNING id`;
    return row?.id;
  });

  assert.equal(result, 'trip-1');
  assert.deepEqual(calls, [
    'BEGIN',
    'INSERT INTO trips DEFAULT VALUES RETURNING id',
    'COMMIT',
    'RELEASE',
  ]);
});

test('transaction runner rolls back and releases after an operation fails', async () => {
  const calls: string[] = [];
  const client: DatabaseSQLClient = {
    async query(text) {
      calls.push(text);
      return { rows: [] };
    },
    release() {
      calls.push('RELEASE');
    },
  };
  const transaction = createDatabaseTransactionRunner(async () => client);

  await assert.rejects(
    transaction(async (database) => {
      await database`INSERT INTO trips DEFAULT VALUES`;
      throw new Error('induced failure');
    }),
    /induced failure/,
  );

  assert.deepEqual(calls, [
    'BEGIN',
    'INSERT INTO trips DEFAULT VALUES',
    'ROLLBACK',
    'RELEASE',
  ]);
});
