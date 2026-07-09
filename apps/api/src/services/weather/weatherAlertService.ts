import type { AppConfig } from '../../config.js';
import type { EventPushStatus } from '../../contracts.js';
import { safeErrorMessage, type Logger } from '../../observability/logger.js';
import type { NotificationService } from '../notifications/notificationService.js';

export type WeatherAlertKind =
  | 'precipitation'
  | 'light rain'
  | 'rain'
  | 'showers'
  | 'snow'
  | 'thunderstorms'
  | 'severe thunderstorms';

export type WeatherAlertForecastPoint = {
  date: Date;
  precipitationChance: number;
  precipitationAmount?: number;
  kind?: WeatherAlertKind;
};

export type WeatherAlertEvent = {
  start: Date;
  end?: Date;
  kind: WeatherAlertKind;
  maximumChance: number;
};

export type WeatherAlertForecastProvider = {
  fetchForecast: () => Promise<WeatherAlertForecastPoint[]>;
};

export type WeatherAlertService = {
  checkNow: () => Promise<EventPushStatus[]>;
  start: () => void;
  stop: () => void;
};

type OpenMeteoHourlyResponse = {
  hourly?: {
    time?: unknown[];
    precipitation_probability?: unknown[];
    precipitation?: unknown[];
    weather_code?: unknown[];
  };
};

const precipitationKindRank: Record<WeatherAlertKind, number> = {
  precipitation: 0,
  'light rain': 1,
  rain: 2,
  showers: 3,
  snow: 4,
  thunderstorms: 5,
  'severe thunderstorms': 6,
};

export function createWeatherAlertService(options: {
  config: AppConfig['weatherAlerts'];
  notificationService: Pick<NotificationService, 'sendWeatherAlertPush'>;
  logger: Logger;
  forecastProvider?: WeatherAlertForecastProvider;
  now?: () => Date;
}): WeatherAlertService {
  const now = options.now ?? (() => new Date());
  const forecastProvider = options.forecastProvider ?? createOpenMeteoWeatherAlertForecastProvider(options.config);
  const sentEventKeys = new Set<string>();
  let interval: ReturnType<typeof setInterval> | undefined;

  const checkNow = async (): Promise<EventPushStatus[]> => {
    if (!options.config.isEnabled) {
      return [];
    }

    const currentDate = now();

    try {
      const forecast = await forecastProvider.fetchForecast();
      const events = weatherAlertEventsFromForecast(forecast, options.config.eventSeparationMinutes);
      const dueAlerts = dueWeatherAlerts(events, currentDate, options.config);
      const statuses: EventPushStatus[] = [];

      pruneSentEventKeys(sentEventKeys, events, currentDate);

      for (const alert of dueAlerts) {
        if (sentEventKeys.has(alert.key)) {
          continue;
        }

        const status = await options.notificationService.sendWeatherAlertPush({
          title: 'Weather alert',
          body: alert.body,
          kind: alert.event.kind,
          startsAt: alert.event.start.toISOString(),
          ...(alert.event.end ? { endsAt: alert.event.end.toISOString() } : {}),
          chance: alert.event.maximumChance,
        });

        sentEventKeys.add(alert.key);
        statuses.push(status);
        options.logger.info('Weather alert push processed.', {
          startsAt: alert.event.start.toISOString(),
          kind: alert.event.kind,
          attempted: status.attempted,
          skipped: status.skipped,
          sentNotificationCount: status.sentNotificationCount,
          reason: status.reason,
        });
      }

      return statuses;
    } catch (error) {
      options.logger.warn('Weather alert check failed.', { error: safeErrorMessage(error) });
      return [];
    }
  };

  return {
    checkNow,
    start() {
      if (!options.config.isEnabled) {
        options.logger.info('Weather alerts are disabled.', { envVar: 'WEATHER_ALERTS_ENABLED' });
        return;
      }

      if (interval) {
        return;
      }

      options.logger.info('Weather alerts enabled.', {
        pollIntervalMinutes: options.config.pollIntervalMinutes,
        leadTimeMinutes: options.config.leadTimeMinutes,
      });
      void checkNow();
      interval = setInterval(() => {
        void checkNow();
      }, options.config.pollIntervalMinutes * 60 * 1000);
      interval.unref();
    },
    stop() {
      if (!interval) {
        return;
      }

      clearInterval(interval);
      interval = undefined;
    },
  };
}

export function createOpenMeteoWeatherAlertForecastProvider(
  config: AppConfig['weatherAlerts'],
  fetcher: typeof fetch = fetch,
): WeatherAlertForecastProvider {
  return {
    async fetchForecast() {
      const url = openMeteoForecastURL(config);
      const response = await fetcher(url);

      if (!response.ok) {
        throw new Error(`Open-Meteo weather alert request failed with HTTP ${response.status}.`);
      }

      return forecastPointsFromOpenMeteoResponse(await response.json());
    },
  };
}

export function weatherAlertEventsFromForecast(
  points: WeatherAlertForecastPoint[],
  eventSeparationMinutes: number,
): WeatherAlertEvent[] {
  const events: WeatherAlertEvent[] = [];
  const separationMs = eventSeparationMinutes * 60 * 1000;
  let start: WeatherAlertForecastPoint | undefined;
  let end: WeatherAlertForecastPoint | undefined;
  let kind: WeatherAlertKind | undefined;
  let maximumChance = 0;

  for (const point of points.slice().sort((first, second) => first.date.getTime() - second.date.getTime())) {
    const pointKind = precipitationKindForPoint(point);

    if (isPrecipitationExpected(point)) {
      if (start && end && point.date.getTime() - end.date.getTime() >= separationMs) {
        events.push(finalizeWeatherAlertEvent(start, end, kind, maximumChance));
        start = point;
        end = undefined;
        kind = pointKind ?? 'precipitation';
        maximumChance = point.precipitationChance;
        continue;
      }

      if (!start) {
        start = point;
        kind = pointKind ?? 'precipitation';
        maximumChance = point.precipitationChance;
      } else {
        kind = preferredWeatherAlertKind(kind, pointKind);
        maximumChance = Math.max(maximumChance, point.precipitationChance);
      }

      end = undefined;
      continue;
    }

    if (start && !end) {
      end = point;
    }
  }

  if (start) {
    events.push(finalizeWeatherAlertEvent(start, end, kind, maximumChance));
  }

  return events;
}

export function weatherAlertBody(
  event: WeatherAlertEvent,
  now: Date,
  timeZone: string,
): string {
  const minutesUntilStart = Math.round((event.start.getTime() - now.getTime()) / 60_000);
  const leadText = Math.abs(minutesUntilStart - 60) <= 10 ? 'in one hour' : 'in about one hour';
  const startText = formatLocalTime(event.start, timeZone);
  const endText = event.end && event.end > event.start
    ? ` until ${formatLocalTime(event.end, timeZone)}`
    : '';

  return `${chanceText(event.maximumChance)} ${event.kind} ${leadText}, around ${startText}${endText}.`;
}

function dueWeatherAlerts(
  events: WeatherAlertEvent[],
  now: Date,
  config: AppConfig['weatherAlerts'],
): Array<{ event: WeatherAlertEvent; key: string; body: string }> {
  const leadMs = config.leadTimeMinutes * 60 * 1000;
  const cadenceMs = config.pollIntervalMinutes * 60 * 1000;
  const minimumStartTime = now.getTime() + Math.max(0, leadMs - cadenceMs);
  const maximumStartTime = now.getTime() + leadMs + cadenceMs;

  return events
    .filter((event) => {
      const startTime = event.start.getTime();
      return startTime >= minimumStartTime && startTime <= maximumStartTime;
    })
    .map((event) => ({
      event,
      key: weatherAlertEventKey(event),
      body: weatherAlertBody(event, now, config.timeZone),
    }));
}

function forecastPointsFromOpenMeteoResponse(value: unknown): WeatherAlertForecastPoint[] {
  const response = value as OpenMeteoHourlyResponse;
  const hourly = response.hourly;

  if (!hourly || !Array.isArray(hourly.time)) {
    return [];
  }

  return hourly.time.flatMap((time, index) => {
    const date = parseOpenMeteoDate(time);

    if (!date) {
      return [];
    }

    const weatherCode = numberAt(hourly.weather_code, index);
    const precipitationAmount = numberAt(hourly.precipitation, index) ?? 0;

    return [{
      date,
      precipitationChance: percentChance(numberAt(hourly.precipitation_probability, index)),
      precipitationAmount,
      kind: weatherAlertKindForOpenMeteoCode(weatherCode, precipitationAmount),
    }];
  });
}

function openMeteoForecastURL(config: AppConfig['weatherAlerts']): URL {
  const url = new URL(config.forecastBaseURL);

  url.searchParams.set('latitude', String(config.latitude));
  url.searchParams.set('longitude', String(config.longitude));
  url.searchParams.set('hourly', 'precipitation_probability,precipitation,weather_code');
  url.searchParams.set('precipitation_unit', 'inch');
  url.searchParams.set('timezone', 'UTC');
  url.searchParams.set('forecast_days', '2');

  return url;
}

function finalizeWeatherAlertEvent(
  start: WeatherAlertForecastPoint,
  end: WeatherAlertForecastPoint | undefined,
  kind: WeatherAlertKind | undefined,
  maximumChance: number,
): WeatherAlertEvent {
  return {
    start: start.date,
    ...(end ? { end: end.date } : {}),
    kind: kind ?? 'precipitation',
    maximumChance: Math.max(maximumChance, start.precipitationChance),
  };
}

function precipitationKindForPoint(point: WeatherAlertForecastPoint): WeatherAlertKind | undefined {
  if (point.kind) {
    return point.kind;
  }

  if (point.precipitationChance >= 0.35 || (point.precipitationAmount ?? 0) > 0) {
    return 'precipitation';
  }

  return undefined;
}

function isPrecipitationExpected(point: WeatherAlertForecastPoint): boolean {
  return Boolean(point.kind) || point.precipitationChance >= 0.2 || (point.precipitationAmount ?? 0) > 0;
}

function preferredWeatherAlertKind(
  current: WeatherAlertKind | undefined,
  next: WeatherAlertKind | undefined,
): WeatherAlertKind | undefined {
  if (!current) {
    return next;
  }

  if (!next) {
    return current;
  }

  return precipitationKindRank[next] > precipitationKindRank[current] ? next : current;
}

function weatherAlertKindForOpenMeteoCode(
  code: number | undefined,
  precipitationAmount: number,
): WeatherAlertKind | undefined {
  switch (code) {
    case 51:
    case 53:
    case 55:
    case 56:
    case 57:
    case 61:
      return 'light rain';
    case 63:
    case 65:
    case 66:
    case 67:
      return 'rain';
    case 71:
    case 73:
    case 75:
    case 77:
    case 85:
    case 86:
      return 'snow';
    case 80:
    case 81:
    case 82:
      return 'showers';
    case 95:
      return 'thunderstorms';
    case 96:
    case 99:
      return 'severe thunderstorms';
    default:
      return precipitationAmount > 0 ? 'precipitation' : undefined;
  }
}

function chanceText(chance: number): string {
  if (chance >= 0.7) {
    return 'High chance of';
  }

  if (chance >= 0.4) {
    return 'Chance of';
  }

  return 'Slight chance of';
}

function weatherAlertEventKey(event: WeatherAlertEvent): string {
  return `${event.start.toISOString().slice(0, 16)}:${event.kind}`;
}

function pruneSentEventKeys(
  sentEventKeys: Set<string>,
  events: WeatherAlertEvent[],
  now: Date,
): void {
  const freshEventKeys = new Set(
    events
      .filter((event) => event.start.getTime() >= now.getTime() - 24 * 60 * 60 * 1000)
      .map(weatherAlertEventKey),
  );

  for (const key of sentEventKeys) {
    if (!freshEventKeys.has(key)) {
      sentEventKeys.delete(key);
    }
  }
}

function parseOpenMeteoDate(value: unknown): Date | undefined {
  if (typeof value !== 'string' || value.trim().length === 0) {
    return undefined;
  }

  const dateText = /(?:Z|[+-]\d{2}:\d{2})$/.test(value) ? value : `${value}Z`;
  const date = new Date(dateText);

  return Number.isNaN(date.getTime()) ? undefined : date;
}

function percentChance(value: number | undefined): number {
  if (value === undefined) {
    return 0;
  }

  return Math.min(Math.max(value / 100, 0), 1);
}

function numberAt(values: unknown[] | undefined, index: number): number | undefined {
  const value = values?.[index];

  return typeof value === 'number' && Number.isFinite(value) ? value : undefined;
}

function formatLocalTime(date: Date, timeZone: string): string {
  const parts = new Intl.DateTimeFormat('en-US', {
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
    timeZone,
  }).formatToParts(date);
  const hour = parts.find((part) => part.type === 'hour')?.value;
  const minute = parts.find((part) => part.type === 'minute')?.value;
  const dayPeriod = parts.find((part) => part.type === 'dayPeriod')?.value;

  if (!hour || !minute || !dayPeriod) {
    return new Intl.DateTimeFormat('en-US', {
      hour: 'numeric',
      minute: '2-digit',
      hour12: true,
      timeZone,
    }).format(date);
  }

  return minute === '00' ? `${hour} ${dayPeriod}` : `${hour}:${minute} ${dayPeriod}`;
}
