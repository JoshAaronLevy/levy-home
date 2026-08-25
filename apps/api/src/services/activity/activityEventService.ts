import crypto from 'node:crypto';

import {
  normalizePhoneStateChangedEvent,
  shouldIncludePhoneStateChangedEvent,
} from '../../integrations/homeAssistant/activityNormalizer.js';
import { fetchHomeAssistantActivityWindow } from '../../integrations/homeAssistant/activityBackfill.js';
import type { AppConfig } from '../../config.js';
import {
  getEventDisplayMetadata,
  type HomeAssistantEventPayload,
  type LevyHomeEvent,
} from '../../contracts.js';
import { logger, safeErrorMessage } from '../../observability/logger.js';
import type { NotificationService } from '../notifications/notificationService.js';
import {
  eventTimestamp,
  type ActivityWindow,
} from './activityWindow.js';

export type ActivityEventService = {
  createStoredEvent: (payload: HomeAssistantEventPayload) => Promise<LevyHomeEvent>;
};

export function createActivityEventService(options: {
  notificationService: Pick<NotificationService, 'sendEventPush'>;
}): ActivityEventService {
  return {
    createStoredEvent(payload) {
      return createStoredEvent(payload, options);
    },
  };
}

export async function createStoredEvent(
  payload: HomeAssistantEventPayload,
  options: { notificationService: Pick<NotificationService, 'sendEventPush'> },
): Promise<LevyHomeEvent> {
  const display = eventDisplayMetadataForPayload(payload);
  const isActivityOnlyPhoneEvent = payload.type === 'phone_state_changed' || payload.category === 'phone';
  const push = isActivityOnlyPhoneEvent
    ? undefined
    : await options.notificationService.sendEventPush(payload);

  return {
    id: crypto.randomUUID(),
    type: payload.type,
    entityId: payload.entityId,
    category: payload.category,
    severity: payload.severity,
    source: payload.source,
    occurredAt: payload.occurredAt ?? new Date().toISOString(),
    title: payload.title ?? display.title,
    message: payload.message ?? display.body,
    metadata: payload.metadata,
    receivedAt: new Date().toISOString(),
    display,
    ...(push ? { push } : {}),
  };
}

function eventDisplayMetadataForPayload(payload: HomeAssistantEventPayload) {
  const display = getEventDisplayMetadata(payload.type);

  if (!usesPayloadDisplayMetadata(payload.type)) {
    return display;
  }

  return {
    ...display,
    title: payload.title ?? display.title,
    body: payload.message ?? display.body,
  };
}

function usesPayloadDisplayMetadata(type: HomeAssistantEventPayload['type']): boolean {
  return type === 'partner_left_home'
    || type === 'partner_arrived_home'
    || type === 'washer_transfer_reminder'
    || type === 'study_lights_on'
    || type === 'thermostat_setpoint_high';
}

export async function fetchNormalizedHomeAssistantHistoryEvents(
  config: AppConfig,
  window: Required<ActivityWindow>,
): Promise<LevyHomeEvent[]> {
  try {
    return (await fetchHomeAssistantActivityWindow(config, window))
      .filter(shouldIncludePhoneStateChangedEvent)
      .map((event) => normalizePhoneStateChangedEvent(event));
  } catch (error) {
    logger.warn('Home Assistant activity history unavailable for /api/events.', {
      error: safeErrorMessage(error),
    });
    return [];
  }
}

export function mergeActivityEvents(events: LevyHomeEvent[], limit: number): LevyHomeEvent[] {
  const eventsByKey = new Map<string, LevyHomeEvent>();

  for (const event of events) {
    const key = activityEventKey(event);
    const existing = eventsByKey.get(key);

    if (!existing || event.receivedAt < existing.receivedAt) {
      eventsByKey.set(key, event);
    }
  }

  return Array.from(eventsByKey.values())
    .sort((a, b) => eventTimestamp(b) - eventTimestamp(a))
    .slice(0, limit);
}

function activityEventKey(event: LevyHomeEvent): string {
  return [
    event.type,
    event.entityId,
    event.occurredAt,
    event.display.title,
    event.display.body,
  ].join('|');
}
