import crypto from 'node:crypto';

import type { EventDisplayMetadata, LevyHomeEvent } from './contracts.js';
import type { HomeAssistantStateChangedEvent } from './homeAssistantActivityClient.js';

type NormalizedPhoneActivityMetadata = {
  homeAssistantEventType: 'state_changed';
  person: string;
  activityKind?: 'arrived_home' | 'left_home' | 'location_changed';
  deviceName?: string;
  friendlyName?: string;
  oldState?: string;
  newState?: string;
  ingestionSource?: 'websocket' | 'history';
  isInitialBackfillState?: boolean;
  oldAttributes?: Record<string, unknown>;
  newAttributes?: Record<string, unknown>;
  homeAssistantContextId?: string;
};

const IGNORED_PRESENCE_STATES = new Set(['unknown', 'unavailable']);

export function isHomePresenceEntityId(entityId: string): boolean {
  return entityId.startsWith('device_tracker.');
}

export function shouldIncludePhoneStateChangedEvent(event: HomeAssistantStateChangedEvent): boolean {
  if (!isHomePresenceEntityId(event.entityId)) {
    return false;
  }

  if (event.isInitialBackfillState) {
    return false;
  }

  if (event.oldState === undefined || event.newState === undefined) {
    return false;
  }

  if (event.oldState === event.newState) {
    return false;
  }

  if (IGNORED_PRESENCE_STATES.has(event.oldState) || IGNORED_PRESENCE_STATES.has(event.newState)) {
    return false;
  }

  return event.oldState === 'home' || event.newState === 'home';
}

export function normalizePhoneStateChangedEvent(event: HomeAssistantStateChangedEvent): LevyHomeEvent {
  const title = phoneActivityTitle(event);
  const body = phoneActivityBody(event.oldState, event.newState);
  const display: EventDisplayMetadata = {
    title,
    body,
    severity: 'info',
  };

  return {
    id: event.id ?? crypto.randomUUID(),
    type: 'phone_state_changed',
    entityId: event.entityId,
    category: 'phone',
    severity: 'normal',
    source: 'home_assistant',
    occurredAt: event.occurredAt ?? new Date().toISOString(),
    title,
    message: body,
    receivedAt: new Date().toISOString(),
    display,
    metadata: phoneActivityMetadata(event),
  };
}

function phoneActivityTitle(event: HomeAssistantStateChangedEvent): string {
  const activityKind = phoneActivityKind(event);

  if (activityKind === 'arrived_home') {
    return `${event.person} arrived home`;
  }

  if (activityKind === 'left_home') {
    return `${event.person} left home`;
  }

  return `${event.person}'s location changed`;
}

function phoneActivityKind(
  event: HomeAssistantStateChangedEvent,
): NormalizedPhoneActivityMetadata['activityKind'] {
  if (event.oldState !== 'home' && event.newState === 'home') {
    return 'arrived_home';
  }

  if (event.oldState === 'home' && event.newState !== 'home') {
    return 'left_home';
  }

  return 'location_changed';
}

function phoneActivityBody(oldState: string | undefined, newState: string | undefined): string {
  if (oldState !== undefined && newState !== undefined) {
    return `${displayPresenceState(oldState)} -> ${displayPresenceState(newState)}`;
  }

  if (newState !== undefined) {
    return `New state: ${displayPresenceState(newState)}`;
  }

  return 'State changed';
}

function displayPresenceState(state: string): string {
  if (state === 'home') {
    return 'Home';
  }

  if (state === 'not_home') {
    return 'Away';
  }

  return state
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (character) => character.toUpperCase());
}

function phoneActivityMetadata(event: HomeAssistantStateChangedEvent): NormalizedPhoneActivityMetadata {
  const oldAttributes = safeAttributes(event.rawEvent.data?.old_state?.attributes);
  const newAttributes = safeAttributes(event.rawEvent.data?.new_state?.attributes);
  const contextId =
    event.rawEvent.context?.id ??
    event.rawEvent.data?.new_state?.context?.id ??
    event.rawEvent.data?.old_state?.context?.id;

  return {
    homeAssistantEventType: 'state_changed',
    person: event.person,
    activityKind: phoneActivityKind(event),
    ...(event.deviceName ? { deviceName: event.deviceName } : {}),
    ...(event.friendlyName ? { friendlyName: event.friendlyName } : {}),
    ...(event.oldState !== undefined ? { oldState: event.oldState } : {}),
    ...(event.newState !== undefined ? { newState: event.newState } : {}),
    ...(event.ingestionSource ? { ingestionSource: event.ingestionSource } : {}),
    ...(event.isInitialBackfillState !== undefined
      ? { isInitialBackfillState: event.isInitialBackfillState }
      : {}),
    ...(oldAttributes ? { oldAttributes } : {}),
    ...(newAttributes ? { newAttributes } : {}),
    ...(contextId ? { homeAssistantContextId: contextId } : {}),
  };
}

function safeAttributes(attributes: Record<string, unknown> | undefined): Record<string, unknown> | undefined {
  if (!attributes) {
    return undefined;
  }

  return Object.fromEntries(
    Object.entries(attributes)
      .filter(([key]) => key === 'friendly_name' || key === 'device_class' || key === 'unit_of_measurement')
      .map(([key, value]) => [key, safeAttributeValue(value)]),
  );
}

function safeAttributeValue(value: unknown): unknown {
  if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean' || value === null) {
    return value;
  }

  return String(value);
}
