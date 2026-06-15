import crypto from 'node:crypto';

import type { EventDisplayMetadata, LevyHomeEvent } from './contracts.js';
import type { HomeAssistantStateChangedEvent } from './homeAssistantActivityClient.js';

type NormalizedPhoneActivityMetadata = {
  homeAssistantEventType: 'state_changed';
  person: string;
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
  if (event.deviceName) {
    return `${event.deviceName} changed`;
  }

  if (event.friendlyName) {
    return `${event.friendlyName} changed`;
  }

  return `${event.person}'s iPhone changed`;
}

function phoneActivityBody(oldState: string | undefined, newState: string | undefined): string {
  if (oldState !== undefined && newState !== undefined) {
    return `${oldState} -> ${newState}`;
  }

  if (newState !== undefined) {
    return `New state: ${newState}`;
  }

  return 'State changed';
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
