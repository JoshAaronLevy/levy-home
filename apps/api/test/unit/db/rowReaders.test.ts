import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  jsonb,
  optionalBoolean,
  optionalISOString,
  optionalInteger,
  optionalString,
  parseJSONBValue,
  requiredInteger,
  requiredString,
} from '../../../src/db/rowReaders.js';

test('row reader string helpers return valid strings and reject missing required values', () => {
  assert.equal(requiredString('Denver Pediatrics', 'todo_locations.name'), 'Denver Pediatrics');
  assert.equal(optionalString('Target'), 'Target');
  assert.equal(optionalString(''), undefined);
  assert.throws(
    () => requiredString('', 'shopping_list.name'),
    /Expected shopping_list\.name to be a non-empty string\./,
  );
});

test('row reader integer helpers parse integer numbers and strings', () => {
  assert.equal(requiredInteger(42, 'shopping_list.id'), 42);
  assert.equal(requiredInteger('42', 'shopping_list.id'), 42);
  assert.equal(optionalInteger(''), undefined);
  assert.equal(optionalInteger('4.2'), undefined);
  assert.throws(
    () => requiredInteger('not-an-id', 'users.id'),
    /Expected users\.id to be an integer\./,
  );
});

test('row reader boolean helpers parse postgres boolean values', () => {
  assert.equal(optionalBoolean(true), true);
  assert.equal(optionalBoolean(false), false);
  assert.equal(optionalBoolean('true'), true);
  assert.equal(optionalBoolean('t'), true);
  assert.equal(optionalBoolean('false'), false);
  assert.equal(optionalBoolean('f'), false);
  assert.equal(optionalBoolean('yes'), undefined);
});

test('row reader timestamp helpers normalize dates and parseable strings', () => {
  assert.equal(optionalISOString(new Date('2026-06-28T15:30:00.000Z')), '2026-06-28T15:30:00.000Z');
  assert.equal(optionalISOString('2026-06-28T15:30:00Z'), '2026-06-28T15:30:00.000Z');
  assert.equal(optionalISOString('not-a-date'), 'not-a-date');
  assert.equal(optionalISOString(''), undefined);
});

test('row reader JSONB helpers preserve legacy string parsing behavior', () => {
  assert.equal(jsonb({ favoritedBy: [1, 2] }), '{"favoritedBy":[1,2]}');
  assert.deepEqual(parseJSONBValue('[1,2,3]'), [1, 2, 3]);
  assert.equal(parseJSONBValue('not-json'), 'not-json');
  assert.deepEqual(parseJSONBValue({ storeId: 1 }), { storeId: 1 });
});
