import type { LevyHomeEvent } from './contracts.js';

export type RecentActivityStore = {
  add(event: LevyHomeEvent): void;
  count(): number;
  list(limit?: number): LevyHomeEvent[];
};

export function createRecentActivityStore(capacity = 100): RecentActivityStore {
  const events: LevyHomeEvent[] = [];
  const maxEvents = clampInteger(capacity, 1, 1_000, 100);

  return {
    add(event) {
      events.unshift(event);

      if (events.length > maxEvents) {
        events.length = maxEvents;
      }
    },
    count() {
      return events.length;
    },
    list(limit = maxEvents) {
      return events.slice(0, clampRecentActivityLimit(limit, maxEvents));
    },
  };
}

export function clampRecentActivityLimit(value: unknown, fallback = 50): number {
  return clampInteger(value, 1, 100, fallback);
}

function clampInteger(value: unknown, min: number, max: number, fallback: number): number {
  const numericValue = typeof value === 'number' ? value : Number(value);

  if (!Number.isFinite(numericValue)) {
    return fallback;
  }

  return Math.min(Math.max(Math.trunc(numericValue), min), max);
}
