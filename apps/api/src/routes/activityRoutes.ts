import { Router, type Request } from 'express';
import crypto from 'node:crypto';

import {
  normalizePhoneStateChangedEvent,
  shouldIncludePhoneStateChangedEvent,
} from '../activityNormalizer.js';
import {
  clampRecentActivityLimit,
  type RecentActivityStore,
} from '../activityStore.js';
import { fetchHomeAssistantActivityWindow } from '../homeAssistantActivityBackfill.js';
import type { PushSender } from '../apnsService.js';
import type { AppConfig } from '../config.js';
import {
  buildEventDedupeKey,
  getEventDisplayMetadata,
  type HomeAssistantEventPayload,
  type LevyHomeEvent,
} from '../contracts.js';
import { asyncHandler } from '../http/asyncHandler.js';
import { HTTPError } from '../http/errors.js';
import { requireHaWebhookSecret } from '../http/middleware/requireHaWebhookSecret.js';
import { validateHomeAssistantEventPayload } from '../validation.js';
import {
  notificationCategoryForEvent,
  pushStatusFromSummary,
  sendPushToRegisteredDevices,
  type PushSendOptions,
} from './pushDelivery.js';
import type {
  NotificationPreferenceState,
  RegisteredDeviceState,
} from './routeState.js';

export type ActivityRouteDependencies = Pick<RegisteredDeviceState, 'registeredDevicesById'> &
  NotificationPreferenceState & {
    activityStore: RecentActivityStore;
    config: AppConfig;
    pushSender: PushSender;
  };

type ActivityWindow = {
  startTime?: Date;
  endTime?: Date;
};

export function createActivityRoutes(deps: ActivityRouteDependencies): Router {
  const router = Router();

  router.post(
    '/api/ha/events',
    requireHaWebhookSecret(deps.config),
    asyncHandler(async (req, res) => {
      const validation = validateHomeAssistantEventPayload(req.body);

      if (!validation.ok) {
        res.status(400).json({ error: validation.error, code: validation.code });
        return;
      }

      const event = await createStoredEvent(validation.value, {
        devices: Array.from(deps.registeredDevicesById.values()),
        preferencesByDeviceKey: deps.preferencesByDeviceKey,
        pushSender: deps.pushSender,
      });
      deps.activityStore.add(event);

      res.status(201).json({
        ok: true,
        event,
        dedupeKey: buildEventDedupeKey(event),
        storedEventCount: deps.activityStore.count(),
      });
    }),
  );

  router.get('/api/events', asyncHandler(async (req, res) => {
    const limit = clampRecentActivityLimit(req.query.limit);
    const window = parseActivityWindow(req.query);
    const storedEvents = deps.activityStore
      .list(500)
      .filter((event) => isEventInWindow(event, window))
      .slice(0, limit);
    const historyEvents = window?.startTime && window.endTime
      ? await fetchNormalizedHomeAssistantHistoryEvents(deps.config, {
          startTime: window.startTime,
          endTime: window.endTime,
        })
      : [];
    const events = mergeActivityEvents([...storedEvents, ...historyEvents], limit);

    res.json({
      ok: true,
      events,
    });
  }));

  return router;
}

function parseActivityWindow(query: Request['query']): ActivityWindow | undefined {
  const hasStartOrEnd = typeof query.start === 'string' || typeof query.end === 'string';

  if (hasStartOrEnd) {
    if (typeof query.start !== 'string' || typeof query.end !== 'string') {
      throw new HTTPError(400, '`start` and `end` query parameters must be provided together.', 'invalid_activity_window');
    }

    const startTime = parseTimestamp(query.start);
    const endTime = parseTimestamp(query.end);

    if (!startTime || !endTime || startTime >= endTime) {
      throw new HTTPError(400, '`start` and `end` must be valid ISO timestamps with start before end.', 'invalid_activity_window');
    }

    if (endTime.getTime() - startTime.getTime() > 7 * 24 * 60 * 60 * 1_000) {
      throw new HTTPError(400, 'Activity windows cannot be longer than 7 days.', 'activity_window_too_large');
    }

    return { startTime, endTime };
  }

  const sinceTime = typeof query.since === 'string' ? parseTimestamp(query.since) : undefined;

  return sinceTime ? { startTime: sinceTime } : undefined;
}

function parseTimestamp(value: string): Date | undefined {
  const timestamp = Date.parse(value);

  if (!Number.isFinite(timestamp)) {
    return undefined;
  }

  return new Date(timestamp);
}

function isEventInWindow(event: LevyHomeEvent, window: ActivityWindow | undefined): boolean {
  if (!window) {
    return true;
  }

  const timestamp = eventTimestamp(event);

  if (window.startTime && timestamp < window.startTime.getTime()) {
    return false;
  }

  if (window.endTime && timestamp >= window.endTime.getTime()) {
    return false;
  }

  return true;
}

async function fetchNormalizedHomeAssistantHistoryEvents(
  config: AppConfig,
  window: Required<ActivityWindow>,
): Promise<LevyHomeEvent[]> {
  try {
    return (await fetchHomeAssistantActivityWindow(config, window))
      .filter(shouldIncludePhoneStateChangedEvent)
      .map((event) => normalizePhoneStateChangedEvent(event));
  } catch (error) {
    console.warn(`Home Assistant activity history unavailable for /api/events: ${safeErrorMessage(error)}`);
    return [];
  }
}

function eventTimestamp(event: LevyHomeEvent): number {
  const timestamp = Date.parse(event.occurredAt ?? '');

  return Number.isFinite(timestamp) ? timestamp : Number.NEGATIVE_INFINITY;
}

function mergeActivityEvents(events: LevyHomeEvent[], limit: number): LevyHomeEvent[] {
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

async function createStoredEvent(
  payload: HomeAssistantEventPayload,
  pushOptions: Pick<PushSendOptions, 'devices' | 'preferencesByDeviceKey' | 'pushSender'>,
): Promise<LevyHomeEvent> {
  const display = getEventDisplayMetadata(payload.type);
  const preferenceCategory = notificationCategoryForEvent(payload);
  const push = preferenceCategory
    ? pushStatusFromSummary(
        await sendPushToRegisteredDevices({
          ...pushOptions,
          payload: {
            title: payload.title ?? display.title,
            body: payload.message ?? display.body,
          },
          preferenceCategory,
        }),
        preferenceCategory,
      )
    : {
        attempted: false,
        skipped: true,
        reason: 'No APNs notification preference category is configured for this event type.',
      };
  const isActivityOnlyPhoneEvent = payload.type === 'phone_state_changed' || payload.category === 'phone';

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
    ...(isActivityOnlyPhoneEvent ? {} : { push }),
  };
}

function safeErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : 'Unknown error.';
}
