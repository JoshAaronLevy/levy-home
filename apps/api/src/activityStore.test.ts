import assert from 'node:assert/strict';
import { test } from 'node:test';

import { clampRecentActivityLimit, createRecentActivityStore } from './activityStore.js';
import type { LevyHomeEvent } from './contracts.js';

test('recent activity store returns newest events first and caps stored events', () => {
  const store = createRecentActivityStore(2);

  store.add(testEvent('oldest'));
  store.add(testEvent('middle'));
  store.add(testEvent('newest'));

  assert.equal(store.count(), 2);
  assert.deepEqual(store.list().map((event) => event.id), ['newest', 'middle']);
});

test('recent activity store returns a defensive limited copy', () => {
  const store = createRecentActivityStore();

  store.add(testEvent('first'));
  store.add(testEvent('second'));

  const events = store.list(1);
  events.length = 0;

  assert.deepEqual(store.list().map((event) => event.id), ['second', 'first']);
});

test('clampRecentActivityLimit clamps API limits to the public event range', () => {
  assert.equal(clampRecentActivityLimit(undefined), 50);
  assert.equal(clampRecentActivityLimit('0'), 1);
  assert.equal(clampRecentActivityLimit('2.9'), 2);
  assert.equal(clampRecentActivityLimit('250'), 100);
  assert.equal(clampRecentActivityLimit('not-a-number'), 50);
});

function testEvent(id: string): LevyHomeEvent {
  return {
    id,
    type: 'phone_state_changed',
    category: 'phone',
    severity: 'normal',
    entityId: `sensor.${id}`,
    source: 'home_assistant',
    occurredAt: '2026-06-15T17:00:00.000Z',
    receivedAt: '2026-06-15T17:00:00.000Z',
    display: {
      title: 'Phone changed',
      body: 'State changed',
      severity: 'info',
    },
  };
}
