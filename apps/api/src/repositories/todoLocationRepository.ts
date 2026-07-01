import type { CreateToDoLocationRequest, ToDoLocation } from '../contracts.js';
import { getDatabaseClient, type DatabaseQuery } from '../db/client.js';
import {
  jsonb,
  optionalBoolean,
  optionalISOString,
  optionalInteger,
  optionalString,
  parseJSONBValue,
  requiredInteger,
  requiredString,
} from '../db/rowReaders.js';

export type ToDoLocationStore = {
  fetchLocations: () => Promise<ToDoLocation[]>;
  createLocation: (request: CreateToDoLocationRequest) => Promise<ToDoLocation>;
};

type ToDoLocationRow = Record<string, unknown> & {
  id: unknown;
  name: unknown;
  address: unknown;
  mapkitTitle: unknown;
  mapkitSubtitle: unknown;
  latitude: unknown;
  longitude: unknown;
  createdBy: unknown;
  createdDate: unknown;
  lastUsedDate: unknown;
  useCount: unknown;
  isActive: unknown;
  favoritedBy: unknown;
};

export function createPostgresToDoLocationStore(database?: DatabaseQuery): ToDoLocationStore {
  const query = () => database ?? getDatabaseClient();

  return {
    async fetchLocations() {
      return fetchToDoLocations(query());
    },
    async createLocation(request) {
      return createToDoLocation(query(), request);
    },
  };
}

export async function fetchToDoLocations(database: DatabaseQuery): Promise<ToDoLocation[]> {
  const rows = await database<ToDoLocationRow>`
    SELECT
      id,
      name,
      address,
      mapkit_title AS "mapkitTitle",
      mapkit_subtitle AS "mapkitSubtitle",
      latitude,
      longitude,
      created_by AS "createdBy",
      created_date AS "createdDate",
      last_used_date AS "lastUsedDate",
      use_count AS "useCount",
      is_active AS "isActive",
      favorited_by AS "favoritedBy"
    FROM todo_locations
    WHERE is_active = true
    ORDER BY
      COALESCE(last_used_date, created_date) DESC,
      use_count DESC,
      lower(name) ASC
  `;

  return rows.map(toDoLocationFromRow);
}

export async function createToDoLocation(
  database: DatabaseQuery,
  request: CreateToDoLocationRequest,
): Promise<ToDoLocation> {
  const [row] = await database<ToDoLocationRow>`
    INSERT INTO todo_locations (
      name,
      address,
      mapkit_title,
      mapkit_subtitle,
      latitude,
      longitude,
      created_by,
      favorited_by
    )
    VALUES (
      ${request.name},
      ${request.address ?? null},
      ${request.mapkitTitle ?? null},
      ${request.mapkitSubtitle ?? null},
      ${request.latitude ?? null},
      ${request.longitude ?? null},
      ${request.createdBy ?? null},
      ${jsonb(request.favoritedBy ?? [])}::jsonb
    )
    RETURNING
      id,
      name,
      address,
      mapkit_title AS "mapkitTitle",
      mapkit_subtitle AS "mapkitSubtitle",
      latitude,
      longitude,
      created_by AS "createdBy",
      created_date AS "createdDate",
      last_used_date AS "lastUsedDate",
      use_count AS "useCount",
      is_active AS "isActive",
      favorited_by AS "favoritedBy"
  `;

  if (!row) {
    throw new Error('Expected todo_locations create to return a row.');
  }

  return toDoLocationFromRow(row);
}

function toDoLocationFromRow(row: ToDoLocationRow): ToDoLocation {
  const address = optionalString(row.address);
  const mapkitTitle = optionalString(row.mapkitTitle);
  const mapkitSubtitle = optionalString(row.mapkitSubtitle);
  const latitude = optionalNumber(row.latitude);
  const longitude = optionalNumber(row.longitude);
  const createdBy = optionalInteger(row.createdBy);
  const lastUsedDate = optionalISOString(row.lastUsedDate);

  return {
    id: requiredInteger(row.id, 'todo_locations.id'),
    name: requiredString(row.name, 'todo_locations.name'),
    ...(address ? { address } : {}),
    ...(mapkitTitle ? { mapkitTitle } : {}),
    ...(mapkitSubtitle ? { mapkitSubtitle } : {}),
    ...(latitude !== undefined ? { latitude } : {}),
    ...(longitude !== undefined ? { longitude } : {}),
    ...(createdBy !== undefined ? { createdBy } : {}),
    createdDate: requiredISOString(row.createdDate, 'todo_locations.created_date'),
    ...(lastUsedDate ? { lastUsedDate } : {}),
    useCount: optionalInteger(row.useCount) ?? 0,
    isActive: optionalBoolean(row.isActive) ?? true,
    favoritedBy: integerArrayFromJSON(row.favoritedBy),
  };
}

function optionalNumber(value: unknown): number | undefined {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === 'string' && value.trim().length > 0) {
    const parsed = Number(value);

    return Number.isFinite(parsed) ? parsed : undefined;
  }

  return undefined;
}

function requiredISOString(value: unknown, fieldName: string): string {
  const timestamp = optionalISOString(value);

  if (!timestamp) {
    throw new Error(`Expected ${fieldName} to be a timestamp.`);
  }

  return timestamp;
}

function integerArrayFromJSON(value: unknown): number[] {
  const parsedValue = parseJSONBValue(value);

  if (!Array.isArray(parsedValue)) {
    return [];
  }

  return parsedValue
    .map(optionalInteger)
    .filter((value): value is number => value !== undefined);
}
