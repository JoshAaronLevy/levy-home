import { Router } from 'express';
import {
  clampRecentActivityLimit,
  type RecentActivityStore,
} from '../activityStore.js';
import type { AppConfig } from '../config.js';
import { buildEventDedupeKey } from '../contracts.js';
import { asyncHandler } from '../http/asyncHandler.js';
import { requireHaWebhookSecret } from '../http/middleware/requireHaWebhookSecret.js';
import type { ActivityEventService } from '../services/activity/activityEventService.js';
import type { DoorbellImageService } from '../services/doorbell/doorbellImageService.js';
import {
  fetchNormalizedHomeAssistantHistoryEvents,
  mergeActivityEvents,
} from '../services/activity/activityEventService.js';
import {
  isEventInWindow,
  parseActivityWindow,
} from '../services/activity/activityWindow.js';
import { validateHomeAssistantEventPayload } from '../validation/activityValidation.js';

export type ActivityRouteDependencies = {
  activityEventService: ActivityEventService;
  activityStore: RecentActivityStore;
  config: AppConfig;
  doorbellImageService: DoorbellImageService;
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

      const eventPayload = await addDoorbellImageURL(validation.value, req, deps.doorbellImageService);
      const event = await deps.activityEventService.createStoredEvent(eventPayload);
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

async function addDoorbellImageURL(
  payload: import('../contracts.js').HomeAssistantEventPayload,
  request: import('express').Request,
  imageService: DoorbellImageService,
): Promise<import('../contracts.js').HomeAssistantEventPayload> {
  const imageEntityId = payload.metadata?.imageEntityId;
  if (payload.category !== 'doorbell' || typeof imageEntityId !== 'string') return payload;
  const imageURL = await imageService.capture(imageEntityId, request);
  return imageURL ? { ...payload, metadata: { ...payload.metadata, imageURL } } : payload;
}
