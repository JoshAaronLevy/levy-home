import type { LevyHomeEvent } from '../../contracts.js';
import { HTTPError } from '../../http/errors.js';

export type ActivityWindow = {
  startTime?: Date;
  endTime?: Date;
};

export type ActivityWindowQuery = {
  start?: unknown;
  end?: unknown;
  since?: unknown;
};

export function parseActivityWindow(query: ActivityWindowQuery): ActivityWindow | undefined {
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

export function isEventInWindow(event: LevyHomeEvent, window: ActivityWindow | undefined): boolean {
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

export function eventTimestamp(event: LevyHomeEvent): number {
  const timestamp = Date.parse(event.occurredAt ?? '');

  return Number.isFinite(timestamp) ? timestamp : Number.NEGATIVE_INFINITY;
}

function parseTimestamp(value: string): Date | undefined {
  const timestamp = Date.parse(value);

  if (!Number.isFinite(timestamp)) {
    return undefined;
  }

  return new Date(timestamp);
}
