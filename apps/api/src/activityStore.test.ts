import assert from 'node:assert/strict';
import { test } from 'node:test';

import { clampRecentActivityLimit, createRecentActivityStore } from './activityStore.js';
import type { LevyHomeEvent } from './contracts.js';

test('recent activity store returns newest events first and caps stored events', () => {
  const store = createRecentActivityStore(2);

  store.add(testEvent('oldest', '2026-06-15T15:00:00.000Z'));
  store.add(testEvent('newest', '2026-06-15T17:00:00.000Z'));
  store.add(testEvent('middle', '2026-06-15T16:00:00.000Z'));

  assert.equal(store.count(), 2);
  assert.deepEqual(store.list().map((event) => event.id), ['newest', 'middle']);
});

test('recent activity store returns a defensive limited copy', () => {
  const store = createRecentActivityStore();

  store.add(testEvent('first', '2026-06-15T16:00:00.000Z'));
  store.add(testEvent('second', '2026-06-15T17:00:00.000Z'));

  const events = store.list(1);
  events.length = 0;

  assert.deepEqual(store.list().map((event) => event.id), ['second', 'first']);
});

test('clampRecentActivityLimit clamps API limits to the public event range', () => {
  assert.equal(clampRecentActivityLimit(undefined), 50);
  assert.equal(clampRecentActivityLimit('0'), 1);
  assert.equal(clampRecentActivityLimit('2.9'), 2);
  assert.equal(clampRecentActivityLimit('250'), 250);
  assert.equal(clampRecentActivityLimit('750'), 500);
  assert.equal(clampRecentActivityLimit('not-a-number'), 50);
});

function testEvent(id: string, occurredAt = '2026-06-15T17:00:00.000Z'): LevyHomeEvent {
  return {
    id,
    type: 'phone_state_changed',
    category: 'phone',
    severity: 'normal',
    entityId: `sensor.${id}`,
    source: 'home_assistant',
    occurredAt,
    receivedAt: '2026-06-15T17:00:00.000Z',
    display: {
      title: 'Phone changed',
      body: 'State changed',
      severity: 'info',
    },
  };
}
