import assert from 'node:assert/strict';
import { test } from 'node:test';

import { normalizePhoneStateChangedEvent } from './activityNormalizer.js';
import type { HomeAssistantStateChangedEvent } from './homeAssistantActivityClient.js';

test('normalizePhoneStateChangedEvent creates a generic Activity-first phone event', () => {
  const event = normalizePhoneStateChangedEvent(sampleStateChangedEvent());

  assert.equal(event.type, 'phone_state_changed');
  assert.equal(event.entityId, 'sensor.josh_iphone_battery_level');
  assert.equal(event.category, 'phone');
  assert.equal(event.severity, 'normal');
  assert.equal(event.source, 'home_assistant');
  assert.equal(event.occurredAt, '2026-06-15T17:00:00.000Z');
  assert.equal(event.title, "Joshs iPhone changed");
  assert.equal(event.message, '82 -> 81');
  assert.deepEqual(event.display, {
    title: "Joshs iPhone changed",
    body: '82 -> 81',
    severity: 'info',
  });
  assert.equal(event.push, undefined);
});

test('normalizePhoneStateChangedEvent stores safe Home Assistant metadata only', () => {
  const event = normalizePhoneStateChangedEvent(sampleStateChangedEvent());

  assert.deepEqual(event.metadata, {
    homeAssistantEventType: 'state_changed',
    person: 'Josh',
    deviceName: "Joshs iPhone",
    friendlyName: "Joshs iPhone Battery Level",
    oldState: '82',
    newState: '81',
    ingestionSource: 'websocket',
    oldAttributes: {
      friendly_name: "Joshs iPhone Battery Level",
      unit_of_measurement: '%',
    },
    newAttributes: {
      friendly_name: "Joshs iPhone Battery Level",
      unit_of_measurement: '%',
      device_class: 'battery',
    },
    homeAssistantContextId: 'event-context-id',
  });
  assert.equal(JSON.stringify(event.metadata).includes('should not be copied'), false);
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

  assert.equal(event.title, "Mallorys iPhone changed");
  assert.equal(event.message, 'State changed');
  assert.equal(event.push, undefined);
});

function sampleStateChangedEvent(): HomeAssistantStateChangedEvent {
  return {
    entityId: 'sensor.josh_iphone_battery_level',
    person: 'Josh',
    deviceName: "Joshs iPhone",
    oldState: '82',
    newState: '81',
    occurredAt: '2026-06-15T17:00:00.000Z',
    friendlyName: "Joshs iPhone Battery Level",
    ingestionSource: 'websocket',
    rawEvent: {
      event_type: 'state_changed',
      time_fired: '2026-06-15T17:00:00.000Z',
      context: {
        id: 'event-context-id',
      },
      data: {
        entity_id: 'sensor.josh_iphone_battery_level',
        old_state: {
          entity_id: 'sensor.josh_iphone_battery_level',
          state: '82',
          attributes: {
            friendly_name: "Joshs iPhone Battery Level",
            unit_of_measurement: '%',
            private_detail: 'should not be copied',
          },
          context: {
            id: 'old-context-id',
          },
        },
        new_state: {
          entity_id: 'sensor.josh_iphone_battery_level',
          state: '81',
          attributes: {
            friendly_name: "Joshs iPhone Battery Level",
            unit_of_measurement: '%',
            device_class: 'battery',
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
