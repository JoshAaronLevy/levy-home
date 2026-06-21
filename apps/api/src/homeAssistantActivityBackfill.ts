import crypto from 'node:crypto';

import {
  isHomePresenceEntityId,
  shouldIncludePhoneStateChangedEvent,
} from './activityNormalizer.js';
import type { AppConfig } from './config.js';
import {
  type HomeAssistantEntityState,
  type HomeAssistantStateChangedEvent,
  matchTrackedPhoneEntity,
  shouldStartHomeAssistantActivityListener,
} from './homeAssistantActivityClient.js';

const DEFAULT_BACKFILL_LOOKBACK_HOURS = 24;
const HOME_ASSISTANT_ACTIVITY_REQUEST_TIMEOUT_MS = 8_000;

export type HomeAssistantActivityBackfillOptions = {
  fetchImpl?: typeof fetch;
  logger?: Pick<Console, 'info' | 'warn'>;
  lookbackHours?: number;
  now?: () => Date;
  onStateChanged?: (event: HomeAssistantStateChangedEvent) => void;
};

export type HomeAssistantActivityWindowOptions = {
  endTime: Date;
  fetchImpl?: typeof fetch;
  logger?: Pick<Console, 'info' | 'warn'>;
  startTime: Date;
};

export async function backfillHomeAssistantActivity(
  config: AppConfig,
  options: HomeAssistantActivityBackfillOptions = {},
): Promise<number> {
  const now = options.now?.() ?? new Date();
  const lookbackHours = normalizedLookbackHours(options.lookbackHours);
  const startTime = new Date(now.getTime() - lookbackHours * 60 * 60 * 1_000);
  const events = await fetchHomeAssistantActivityWindow(config, {
    endTime: now,
    fetchImpl: options.fetchImpl,
    logger: options.logger,
    startTime,
  });

  for (const event of events) {
    options.onStateChanged?.(event);
  }

  return events.length;
}

export async function fetchHomeAssistantActivityWindow(
  config: AppConfig,
  options: HomeAssistantActivityWindowOptions,
): Promise<HomeAssistantStateChangedEvent[]> {
  const logger = options.logger ?? console;

  if (!shouldAttemptHomeAssistantActivityBackfill(config)) {
    return [];
  }

  if (!config.homeAssistant.baseURL || !config.homeAssistant.token) {
    logger.warn('Home Assistant activity backfill is enabled but live REST credentials are incomplete.');
    return [];
  }

  const fetchImpl = options.fetchImpl ?? fetch;
  const baseURL = new URL(config.homeAssistant.baseURL);
  const entityIds = await resolveBackfillEntityIds(config, baseURL, config.homeAssistant.token, fetchImpl);

  if (entityIds.length === 0) {
    logger.warn('Home Assistant activity backfill found no tracked phone entities to request.');
    return [];
  }

  const history = await requestHomeAssistant<HomeAssistantEntityState[][]>(
    baseURL,
    config.homeAssistant.token,
    fetchImpl,
    `/api/history/period/${options.startTime.toISOString()}`,
    {
      end_time: options.endTime.toISOString(),
      filter_entity_id: entityIds.join(','),
    },
  );

  if (!Array.isArray(history)) {
    throw new Error('Home Assistant activity backfill returned an unexpected history response.');
  }

  const events = history
    .flatMap((timeline) => timelineToStateChangedEvents(config, Array.isArray(timeline) ? timeline : []))
    .filter(shouldIncludePhoneStateChangedEvent)
    .sort((a, b) => eventTimestamp(a) - eventTimestamp(b));

  return events;
}

function shouldAttemptHomeAssistantActivityBackfill(config: AppConfig): boolean {
  return (
    shouldStartHomeAssistantActivityListener(config) &&
    (config.homeAssistant.activity.trackedPhoneEntities.length > 0 ||
      config.homeAssistant.activity.trackedPhoneEntityPatterns.length > 0)
  );
}

async function resolveBackfillEntityIds(
  config: AppConfig,
  baseURL: URL,
  token: string,
  fetchImpl: typeof fetch,
): Promise<string[]> {
  const entityIds = new Set(config.homeAssistant.activity.trackedPhoneEntities.map((entity) => entity.entityId));
  for (const entityId of Array.from(entityIds)) {
    if (!isHomePresenceEntityId(entityId)) {
      entityIds.delete(entityId);
    }
  }

  if (config.homeAssistant.activity.trackedPhoneEntityPatterns.length > 0) {
    const states = await requestHomeAssistant<HomeAssistantEntityState[]>(baseURL, token, fetchImpl, '/api/states');

    if (!Array.isArray(states)) {
      throw new Error('Home Assistant activity backfill returned an unexpected states response.');
    }

    for (const state of states) {
      if (
        state.entity_id &&
        isHomePresenceEntityId(state.entity_id) &&
        matchTrackedPhoneEntity(state.entity_id, [], config.homeAssistant.activity.trackedPhoneEntityPatterns)
      ) {
        entityIds.add(state.entity_id);
      }
    }
  }

  return Array.from(entityIds).sort((a, b) => a.localeCompare(b));
}

function timelineToStateChangedEvents(
  config: AppConfig,
  timeline: HomeAssistantEntityState[],
): HomeAssistantStateChangedEvent[] {
  const events: HomeAssistantStateChangedEvent[] = [];
  const states = timeline
    .filter(hasEntityId)
    .sort((a, b) => stateTimestamp(a) - stateTimestamp(b));

  let previousState: HomeAssistantEntityState | undefined;

  for (const state of states) {
    const entityId = state.entity_id;
    const match = matchTrackedPhoneEntity(
      entityId,
      config.homeAssistant.activity.trackedPhoneEntities,
      config.homeAssistant.activity.trackedPhoneEntityPatterns,
    );

    if (!match) {
      continue;
    }

    const occurredAt = state.last_changed ?? state.last_updated;

    events.push({
      id: historyEventId(entityId, previousState, state),
      entityId,
      person: match.person,
      ...(match.deviceName ? { deviceName: match.deviceName } : {}),
      ...(previousState?.state !== undefined ? { oldState: previousState.state } : {}),
      ...(state.state !== undefined ? { newState: state.state } : {}),
      ...(occurredAt ? { occurredAt } : {}),
      ...(state.attributes?.friendly_name ? { friendlyName: state.attributes.friendly_name } : {}),
      ingestionSource: 'history',
      isInitialBackfillState: previousState === undefined,
      rawEvent: {
        event_type: 'state_changed',
        ...(occurredAt ? { time_fired: occurredAt } : {}),
        ...(state.context ? { context: state.context } : {}),
        data: {
          entity_id: entityId,
          old_state: previousState ?? null,
          new_state: state,
        },
      },
    });

    previousState = state;
  }

  return events;
}

function hasEntityId(state: HomeAssistantEntityState): state is HomeAssistantEntityState & { entity_id: string } {
  return typeof state.entity_id === 'string' && state.entity_id.length > 0;
}

function historyEventId(
  entityId: string,
  previousState: HomeAssistantEntityState | undefined,
  state: HomeAssistantEntityState,
): string {
  const occurredAt = state.last_changed ?? state.last_updated ?? '';
  const hash = crypto
    .createHash('sha256')
    .update(JSON.stringify({
      entityId,
      occurredAt,
      oldState: previousState?.state,
      newState: state.state,
      contextId: state.context?.id,
    }))
    .digest('hex')
    .slice(0, 24);

  return `ha-history-${hash}`;
}

async function requestHomeAssistant<T>(
  baseURL: URL,
  token: string,
  fetchImpl: typeof fetch,
  path: string,
  query: Record<string, string> = {},
): Promise<T> {
  const url = new URL(path, baseURL);

  for (const [key, value] of Object.entries(query)) {
    url.searchParams.set(key, value);
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => {
    controller.abort();
  }, HOME_ASSISTANT_ACTIVITY_REQUEST_TIMEOUT_MS);

  if (typeof timeout === 'object' && 'unref' in timeout) {
    timeout.unref();
  }

  let response: Response;

  try {
    response = await fetchImpl(url, {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/json',
      },
      signal: controller.signal,
    });
  } catch (error) {
    if (isAbortError(error)) {
      throw new Error('Home Assistant activity backfill request timed out.');
    }

    throw error;
  } finally {
    clearTimeout(timeout);
  }

  if (!response.ok) {
    throw new Error(`Home Assistant activity backfill request failed with status ${response.status}.`);
  }

  return (await response.json()) as T;
}

function isAbortError(error: unknown): boolean {
  return error instanceof Error && error.name === 'AbortError';
}

function normalizedLookbackHours(value: number | undefined): number {
  if (!value || !Number.isFinite(value)) {
    return DEFAULT_BACKFILL_LOOKBACK_HOURS;
  }

  return Math.min(Math.max(value, 1), 168);
}

function stateTimestamp(state: HomeAssistantEntityState): number {
  const timestamp = Date.parse(state.last_changed ?? state.last_updated ?? '');

  return Number.isFinite(timestamp) ? timestamp : Number.NEGATIVE_INFINITY;
}

function eventTimestamp(event: HomeAssistantStateChangedEvent): number {
  const timestamp = Date.parse(event.occurredAt ?? '');

  return Number.isFinite(timestamp) ? timestamp : Number.NEGATIVE_INFINITY;
}
