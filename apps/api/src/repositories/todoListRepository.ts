import type {
  CreateToDoItemRequest,
  ToDoCategory,
  ToDoItem,
  ToDoListData,
  ToDoRecurring,
  ToDoStatus,
  UpdateToDoItemRequest,
} from '../contracts.js';
import { getDatabaseClient, type DatabaseQuery } from '../db/client.js';
import {
  jsonb,
  optionalISOString,
  optionalInteger,
  optionalString,
  parseJSONBValue,
  requiredInteger,
  requiredString,
} from '../db/rowReaders.js';
import { fetchToDoLocations } from './todoLocationRepository.js';

export type ToDoListStore = {
  fetchToDoList: () => Promise<ToDoListData>;
  fetchItem: (id: number) => Promise<ToDoItem | null>;
  createItem: (request: CreateToDoItemRequest) => Promise<ToDoItem>;
  updateItem: (id: number, request: UpdateToDoItemRequest) => Promise<ToDoItem | null>;
  deleteItem: (id: number) => Promise<ToDoItem | null>;
};

type ToDoItemRow = Record<string, unknown> & {
  id: unknown;
  name: unknown;
  locationIds: unknown;
  locationDisplayText: unknown;
  date: unknown;
  recurring: unknown;
  alerts: unknown;
  createdBy: unknown;
  createdDate: unknown;
  status: unknown;
};

type ToDoCategoryRow = Record<string, unknown> & {
  id: unknown;
  name: unknown;
  updatedAt: unknown;
};

export function createPostgresToDoListStore(database?: DatabaseQuery): ToDoListStore {
  const query = () => database ?? getDatabaseClient();

  return {
    async fetchToDoList() {
      return fetchToDoListData(query());
    },
    async fetchItem(id) {
      return fetchToDoItem(query(), id);
    },
    async createItem(request) {
      return createToDoItem(query(), request);
    },
    async updateItem(id, request) {
      return updateToDoItem(query(), id, request);
    },
    async deleteItem(id) {
      return deleteToDoItem(query(), id);
    },
  };
}

export async function fetchToDoListData(database: DatabaseQuery): Promise<ToDoListData> {
  const [itemRows, categoryRows, locations] = await Promise.all([
    database<ToDoItemRow>`
      SELECT
        item.id,
        item.name,
        item.location_ids AS "locationIds",
        COALESCE(
          (
            SELECT string_agg(location.name, ', ' ORDER BY location.name)
            FROM todo_locations location
            WHERE location.id IN (
              SELECT value::integer
              FROM jsonb_array_elements_text(COALESCE(item.location_ids, '[]'::jsonb))
            )
          ),
          'No location'
        ) AS "locationDisplayText",
        item.date,
        item.recurring,
        COALESCE(item.alerts, '[]'::jsonb) AS alerts,
        item.created_by AS "createdBy",
        item.created_date AS "createdDate",
        item.status
      FROM todo_list item
      ORDER BY
        item.date ASC NULLS LAST,
        item.created_date DESC NULLS LAST,
        lower(item.name) ASC,
        item.id ASC
    `,
    fetchToDoCategories(database),
    fetchToDoLocations(database),
  ]);

  return {
    items: itemRows.map(toDoItemFromRow),
    categories: categoryRows,
    locations,
  };
}

export async function fetchToDoItem(database: DatabaseQuery, id: number): Promise<ToDoItem | null> {
  const [row] = await database<ToDoItemRow>`
    SELECT
      item.id,
      item.name,
      item.location_ids AS "locationIds",
      COALESCE(
        (
          SELECT string_agg(location.name, ', ' ORDER BY location.name)
          FROM todo_locations location
          WHERE location.id IN (
            SELECT value::integer
            FROM jsonb_array_elements_text(COALESCE(item.location_ids, '[]'::jsonb))
          )
        ),
        'No location'
      ) AS "locationDisplayText",
      item.date,
      item.recurring,
      COALESCE(item.alerts, '[]'::jsonb) AS alerts,
      item.created_by AS "createdBy",
      item.created_date AS "createdDate",
      item.status
    FROM todo_list item
    WHERE item.id = ${id}
    LIMIT 1
  `;

  return row ? toDoItemFromRow(row) : null;
}

export async function createToDoItem(database: DatabaseQuery, request: CreateToDoItemRequest): Promise<ToDoItem> {
  const [row] = await database<ToDoItemRow>`
    INSERT INTO todo_list (
      name,
      location_ids,
      date,
      recurring,
      alerts,
      created_by,
      created_date,
      status
    )
    VALUES (
      ${request.name},
      ${jsonb(request.locationIds ?? [])}::jsonb,
      ${request.date ?? null},
      ${request.recurring ?? null},
      ${jsonb(request.alerts ?? [])}::jsonb,
      ${request.createdBy ?? null},
      now(),
      ${request.status ?? 'open'}
    )
    RETURNING
      id,
      name,
      location_ids AS "locationIds",
      COALESCE(
        (
          SELECT string_agg(location.name, ', ' ORDER BY location.name)
          FROM todo_locations location
          WHERE location.id IN (
            SELECT value::integer
            FROM jsonb_array_elements_text(COALESCE(todo_list.location_ids, '[]'::jsonb))
          )
        ),
        'No location'
      ) AS "locationDisplayText",
      date,
      recurring,
      COALESCE(alerts, '[]'::jsonb) AS alerts,
      created_by AS "createdBy",
      created_date AS "createdDate",
      status
  `;

  return requireToDoItemRow(row, 'create');
}

export async function updateToDoItem(
  database: DatabaseQuery,
  id: number,
  request: UpdateToDoItemRequest,
): Promise<ToDoItem | null> {
  if (!hasToDoItemUpdate(request)) {
    return fetchToDoItem(database, id);
  }

  const hasName = request.name !== undefined;
  const hasLocationIds = request.locationIds !== undefined;
  const hasDate = request.date !== undefined;
  const hasRecurring = request.recurring !== undefined;
  const hasAlerts = request.alerts !== undefined;
  const hasCreatedBy = request.createdBy !== undefined;
  const hasStatus = request.status !== undefined;

  const [row] = await database<ToDoItemRow>`
    UPDATE todo_list AS item
    SET
      name = CASE WHEN ${hasName} THEN ${request.name ?? null} ELSE item.name END,
      location_ids = CASE
        WHEN ${hasLocationIds} THEN ${jsonb(request.locationIds ?? [])}::jsonb
        ELSE item.location_ids
      END,
      date = CASE WHEN ${hasDate} THEN ${request.date ?? null} ELSE item.date END,
      recurring = CASE WHEN ${hasRecurring} THEN ${request.recurring ?? null} ELSE item.recurring END,
      alerts = CASE WHEN ${hasAlerts} THEN ${jsonb(request.alerts ?? [])}::jsonb ELSE item.alerts END,
      created_by = CASE WHEN ${hasCreatedBy} THEN ${request.createdBy ?? null} ELSE item.created_by END,
      status = CASE WHEN ${hasStatus} THEN ${request.status ?? null} ELSE item.status END
    WHERE item.id = ${id}
    RETURNING
      id,
      name,
      location_ids AS "locationIds",
      COALESCE(
        (
          SELECT string_agg(location.name, ', ' ORDER BY location.name)
          FROM todo_locations location
          WHERE location.id IN (
            SELECT value::integer
            FROM jsonb_array_elements_text(COALESCE(item.location_ids, '[]'::jsonb))
          )
        ),
        'No location'
      ) AS "locationDisplayText",
      date,
      recurring,
      COALESCE(alerts, '[]'::jsonb) AS alerts,
      created_by AS "createdBy",
      created_date AS "createdDate",
      status
  `;

  return row ? toDoItemFromRow(row) : null;
}

export async function deleteToDoItem(database: DatabaseQuery, id: number): Promise<ToDoItem | null> {
  const [row] = await database<ToDoItemRow>`
    DELETE FROM todo_list AS item
    WHERE item.id = ${id}
    RETURNING
      id,
      name,
      location_ids AS "locationIds",
      COALESCE(
        (
          SELECT string_agg(location.name, ', ' ORDER BY location.name)
          FROM todo_locations location
          WHERE location.id IN (
            SELECT value::integer
            FROM jsonb_array_elements_text(COALESCE(item.location_ids, '[]'::jsonb))
          )
        ),
        'No location'
      ) AS "locationDisplayText",
      date,
      recurring,
      COALESCE(alerts, '[]'::jsonb) AS alerts,
      created_by AS "createdBy",
      created_date AS "createdDate",
      status
  `;

  return row ? toDoItemFromRow(row) : null;
}

async function fetchToDoCategories(database: DatabaseQuery): Promise<ToDoCategory[]> {
  const rows = await database<ToDoCategoryRow>`
    SELECT
      id,
      name,
      updated_at AS "updatedAt"
    FROM todo_categories
    ORDER BY lower(COALESCE(name, '')) ASC, id ASC
  `;

  return rows.map(toDoCategoryFromRow);
}

function toDoItemFromRow(row: ToDoItemRow): ToDoItem {
  const date = optionalISOString(row.date);
  const recurring = optionalToDoRecurring(row.recurring);
  const alerts = alertsArrayFromJSON(row.alerts);
  const createdBy = optionalInteger(row.createdBy);
  const createdDate = optionalISOString(row.createdDate);

  return {
    id: requiredInteger(row.id, 'todo_list.id'),
    name: requiredString(row.name, 'todo_list.name'),
    status: requiredToDoStatus(row.status),
    locationIds: integerArrayFromJSON(row.locationIds),
    locationDisplayText: optionalString(row.locationDisplayText) ?? 'No location',
    ...(date ? { date } : {}),
    ...(recurring ? { recurring } : {}),
    alerts,
    ...(createdBy !== undefined ? { createdBy } : {}),
    ...(createdDate ? { createdDate } : {}),
  };
}

function toDoCategoryFromRow(row: ToDoCategoryRow): ToDoCategory {
  const id = requiredInteger(row.id, 'todo_categories.id');
  const name = optionalString(row.name);
  const updatedAt = optionalISOString(row.updatedAt);

  return {
    id,
    ...(name ? { name } : {}),
    ...(updatedAt ? { updatedAt } : {}),
  };
}

function requireToDoItemRow(row: ToDoItemRow | undefined, operation: string): ToDoItem {
  if (!row) {
    throw new Error(`Expected todo_list ${operation} to return a row.`);
  }

  return toDoItemFromRow(row);
}

function hasToDoItemUpdate(request: UpdateToDoItemRequest): boolean {
  return (
    request.name !== undefined ||
    request.status !== undefined ||
    request.locationIds !== undefined ||
    request.date !== undefined ||
    request.recurring !== undefined ||
    request.alerts !== undefined ||
    request.createdBy !== undefined
  );
}

function requiredToDoStatus(value: unknown): ToDoStatus {
  if (value === 'open' || value === 'completed' || value === 'canceled') {
    return value;
  }

  throw new Error('Expected todo_list.status to be a known status.');
}

function optionalToDoRecurring(value: unknown): ToDoRecurring | undefined {
  return value === 'daily' || value === 'weekly' || value === 'monthly' || value === 'quarterly'
    ? value
    : undefined;
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

function alertsArrayFromJSON(value: unknown): unknown[] {
  const parsedValue = parseJSONBValue(value);
  return Array.isArray(parsedValue) ? parsedValue : [];
}
