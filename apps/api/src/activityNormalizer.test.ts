import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  normalizePhoneStateChangedEvent,
  shouldIncludePhoneStateChangedEvent,
} from './activityNormalizer.js';
import type { HomeAssistantStateChangedEvent } from './homeAssistantActivityClient.js';

test('normalizePhoneStateChangedEvent creates a home-arrival Activity event', () => {
  const event = normalizePhoneStateChangedEvent(sampleStateChangedEvent());

  assert.equal(event.type, 'phone_state_changed');
  assert.equal(event.entityId, 'device_tracker.josh_iphone');
  assert.equal(event.category, 'phone');
  assert.equal(event.severity, 'normal');
  assert.equal(event.source, 'home_assistant');
  assert.equal(event.occurredAt, '2026-06-15T17:00:00.000Z');
  assert.equal(event.title, 'Josh arrived home');
  assert.equal(event.message, 'Away -> Home');
  assert.deepEqual(event.display, {
    title: 'Josh arrived home',
    body: 'Away -> Home',
    severity: 'info',
  });
  assert.equal(event.push, undefined);
});

test('normalizePhoneStateChangedEvent stores safe Home Assistant metadata only', () => {
  const event = normalizePhoneStateChangedEvent(sampleStateChangedEvent());

  assert.deepEqual(event.metadata, {
    homeAssistantEventType: 'state_changed',
    person: 'Josh',
    activityKind: 'arrived_home',
    deviceName: "Joshs iPhone",
    friendlyName: "Joshs iPhone",
    oldState: 'not_home',
    newState: 'home',
    ingestionSource: 'websocket',
    oldAttributes: {
      friendly_name: "Joshs iPhone",
    },
    newAttributes: {
      friendly_name: "Joshs iPhone",
    },
    homeAssistantContextId: 'event-context-id',
  });
  assert.equal(JSON.stringify(event.metadata).includes('should not be copied'), false);
});

test('normalizePhoneStateChangedEvent names home departures clearly', () => {
  const event = normalizePhoneStateChangedEvent(sampleStateChangedEvent({
    oldState: 'home',
    newState: 'not_home',
  }));

  assert.equal(event.title, 'Josh left home');
  assert.equal(event.message, 'Home -> Away');
  assert.equal(event.metadata?.activityKind, 'left_home');
});

test('normalizePhoneStateChangedEvent falls back to simple copy when states are missing', () => {
  const event = normalizePhoneStateChangedEvent({
    entityId: 'device_tracker.mallorys_iphone',
    person: 'Mallory',
    deviceName: "Mallorys iPhone",
    occurredAt: '2026-06-15T17:05:00.000Z',
    rawEvent: {
      event_type: 'state_changed',
      time_fired: '2026-06-15T17:05:00.000Z',
      data: {
        entity_id: 'device_tracker.mallorys_iphone',
      },
    },
  });

  assert.equal(event.title, "Mallory's location changed");
  assert.equal(event.message, 'State changed');
  assert.equal(event.push, undefined);
});

test('shouldIncludePhoneStateChangedEvent keeps only real home presence changes', () => {
  assert.equal(shouldIncludePhoneStateChangedEvent(sampleStateChangedEvent()), true);
  assert.equal(
    shouldIncludePhoneStateChangedEvent(sampleStateChangedEvent({ entityId: 'sensor.josh_iphone_battery_level' })),
    false,
  );
  assert.equal(
    shouldIncludePhoneStateChangedEvent(sampleStateChangedEvent({ oldState: 'home', newState: 'home' })),
    false,
  );
  assert.equal(
    shouldIncludePhoneStateChangedEvent(sampleStateChangedEvent({ oldState: 'unknown', newState: 'home' })),
    false,
  );
  assert.equal(
    shouldIncludePhoneStateChangedEvent(sampleStateChangedEvent({ oldState: 'not_home', newState: 'Work' })),
    false,
  );
  assert.equal(
    shouldIncludePhoneStateChangedEvent(sampleStateChangedEvent({ isInitialBackfillState: true })),
    false,
  );
});

function sampleStateChangedEvent(
  overrides: Partial<HomeAssistantStateChangedEvent> = {},
): HomeAssistantStateChangedEvent {
  const entityId = overrides.entityId ?? 'device_tracker.josh_iphone';
  const oldState = overrides.oldState ?? 'not_home';
  const newState = overrides.newState ?? 'home';

  return {
    entityId,
    person: 'Josh',
    deviceName: "Joshs iPhone",
    oldState,
    newState,
    occurredAt: '2026-06-15T17:00:00.000Z',
    friendlyName: "Joshs iPhone",
    ingestionSource: 'websocket',
    ...overrides,
    rawEvent: {
      event_type: 'state_changed',
      time_fired: '2026-06-15T17:00:00.000Z',
      context: {
        id: 'event-context-id',
      },
      data: {
        entity_id: entityId,
        old_state: {
          entity_id: entityId,
          state: oldState,
          attributes: {
            friendly_name: "Joshs iPhone",
            private_detail: 'should not be copied',
          },
          context: {
            id: 'old-context-id',
          },
        },
        new_state: {
          entity_id: entityId,
          state: newState,
          attributes: {
            friendly_name: "Joshs iPhone",
            private_detail: 'should not be copied',
          },
          context: {
            id: 'new-context-id',
          },
        },
      },
    },
  };
}
