import type {
  CreateShoppingListItemRequest,
  ShoppingCategory,
  ShoppingListData,
  ShoppingListItem,
  ShoppingStore,
  UpdateShoppingListItemRequest,
} from './contracts.js';
import { getDatabaseClient, type DatabaseQuery } from './dbClient.js';

export type ShoppingListStore = {
  fetchShoppingList: () => Promise<ShoppingListData>;
  fetchItem: (id: number) => Promise<ShoppingListItem | null>;
  findItemByName: (name: string) => Promise<ShoppingListItem | null>;
  createItem: (request: CreateShoppingListItemRequest) => Promise<ShoppingListItem>;
  updateItem: (id: number, request: UpdateShoppingListItemRequest) => Promise<ShoppingListItem | null>;
  deleteItem: (id: number) => Promise<ShoppingListItem | null>;
};

type ShoppingListRow = Record<string, unknown> & {
  id: unknown;
  name: unknown;
  brand: unknown;
  quantity: unknown;
  notes: unknown;
  purchased: unknown;
  createdAt: unknown;
  updatedAt: unknown;
  version: unknown;
  storeIds: unknown;
  categoryId: unknown;
};

type ShoppingStoreRow = Record<string, unknown> & {
  id: unknown;
  name: unknown;
  logo: unknown;
};

type ShoppingCategoryRow = Record<string, unknown> & {
  id: unknown;
  name: unknown;
};

export function createPostgresShoppingListStore(database?: DatabaseQuery): ShoppingListStore {
  const query = () => database ?? getDatabaseClient();

  return {
    async fetchShoppingList() {
      return fetchShoppingListData(query());
    },
    async fetchItem(id) {
      return fetchShoppingListItem(query(), id);
    },
    async findItemByName(name) {
      return findShoppingListItemByName(query(), name);
    },
    async createItem(request) {
      return createShoppingListItem(query(), request);
    },
    async updateItem(id, request) {
      return updateShoppingListItem(query(), id, request);
    },
    async deleteItem(id) {
      return deleteShoppingListItem(query(), id);
    },
  };
}

export async function fetchShoppingListData(database: DatabaseQuery): Promise<ShoppingListData> {
  const [itemRows, storeRows, categoryRows] = await Promise.all([
    database<ShoppingListRow>`
      SELECT
        item.id,
        item.name,
        item.brand,
        item.quantity,
        item.notes,
        item.purchased,
        item.created_at AS "createdAt",
        item.updated_at AS "updatedAt",
        to_jsonb(item) ->> 'version' AS "version",
        item.store_ids AS "storeIds",
        item.category_id AS "categoryId"
      FROM shopping_list item
      ORDER BY item.purchased ASC NULLS FIRST, lower(item.name) ASC
    `,
    database<ShoppingStoreRow>`
      SELECT
        id,
        name,
        logo
      FROM stores
      ORDER BY lower(name) ASC
    `,
    database<ShoppingCategoryRow>`
      SELECT
        id,
        name
      FROM categories
      ORDER BY lower(name) ASC
    `,
  ]);

  return {
    items: itemRows.map(shoppingListItemFromRow),
    stores: storeRows.map(shoppingStoreFromRow),
    categories: categoryRows.map(shoppingCategoryFromRow),
  };
}

export async function fetchShoppingListItem(
  database: DatabaseQuery,
  id: number,
): Promise<ShoppingListItem | null> {
  const [row] = await database<ShoppingListRow>`
    SELECT
      item.id,
      item.name,
      item.brand,
      item.quantity,
      item.notes,
      item.purchased,
      item.created_at AS "createdAt",
      item.updated_at AS "updatedAt",
      to_jsonb(item) ->> 'version' AS "version",
      item.store_ids AS "storeIds",
      item.category_id AS "categoryId"
    FROM shopping_list item
    WHERE item.id = ${id}
    LIMIT 1
  `;

  return row ? shoppingListItemFromRow(row) : null;
}

export async function findShoppingListItemByName(
  database: DatabaseQuery,
  name: string,
): Promise<ShoppingListItem | null> {
  const normalizedName = name.trim();

  if (normalizedName.length === 0) {
    return null;
  }

  const [row] = await database<ShoppingListRow>`
    SELECT
      item.id,
      item.name,
      item.brand,
      item.quantity,
      item.notes,
      item.purchased,
      item.created_at AS "createdAt",
      item.updated_at AS "updatedAt",
      to_jsonb(item) ->> 'version' AS "version",
      item.store_ids AS "storeIds",
      item.category_id AS "categoryId"
    FROM shopping_list item
    WHERE lower(btrim(item.name)) = lower(btrim(${normalizedName}))
    ORDER BY item.purchased ASC NULLS FIRST, item.updated_at DESC NULLS LAST, item.id ASC
    LIMIT 1
  `;

  return row ? shoppingListItemFromRow(row) : null;
}

export async function createShoppingListItem(
  database: DatabaseQuery,
  request: CreateShoppingListItemRequest,
): Promise<ShoppingListItem> {
  const [row] = await database<ShoppingListRow>`
    INSERT INTO shopping_list (
      name,
      brand,
      quantity,
      notes,
      purchased,
      store_ids,
      category_id
    )
    VALUES (
      ${request.name},
      ${request.brand ?? null},
      ${request.quantity ?? 1},
      ${request.notes ?? null},
      ${request.purchased ?? false},
      ${jsonb(request.storeIds ?? [])}::jsonb,
      ${jsonb(request.categoryId ?? null)}::jsonb
    )
    RETURNING
      id,
      name,
      brand,
      quantity,
      notes,
      purchased,
      created_at AS "createdAt",
      updated_at AS "updatedAt",
      version AS "version",
      store_ids AS "storeIds",
      category_id AS "categoryId"
  `;

  return requireShoppingListItemRow(row, 'create');
}

export async function updateShoppingListItem(
  database: DatabaseQuery,
  id: number,
  request: UpdateShoppingListItemRequest,
): Promise<ShoppingListItem | null> {
  if (!hasShoppingListItemUpdate(request)) {
    return fetchShoppingListItem(database, id);
  }

  const hasName = request.name !== undefined;
  const hasBrand = request.brand !== undefined;
  const hasQuantity = request.quantity !== undefined;
  const hasNotes = request.notes !== undefined;
  const hasPurchased = request.purchased !== undefined;
  const hasStoreIds = request.storeIds !== undefined;
  const hasCategoryId = request.categoryId !== undefined;

  const [row] = await database<ShoppingListRow>`
    UPDATE shopping_list AS item
    SET
      name = CASE WHEN ${hasName} THEN ${request.name ?? null} ELSE item.name END,
      brand = CASE WHEN ${hasBrand} THEN ${request.brand ?? null} ELSE item.brand END,
      quantity = CASE WHEN ${hasQuantity} THEN ${request.quantity ?? null} ELSE item.quantity END,
      notes = CASE WHEN ${hasNotes} THEN ${request.notes ?? null} ELSE item.notes END,
      purchased = CASE WHEN ${hasPurchased} THEN ${request.purchased ?? null} ELSE item.purchased END,
      store_ids = CASE WHEN ${hasStoreIds} THEN ${jsonb(request.storeIds ?? [])}::jsonb ELSE item.store_ids END,
      category_id = CASE WHEN ${hasCategoryId} THEN ${jsonb(request.categoryId ?? null)}::jsonb ELSE item.category_id END
    WHERE item.id = ${id}
    RETURNING
      id,
      name,
      brand,
      quantity,
      notes,
      purchased,
      created_at AS "createdAt",
      updated_at AS "updatedAt",
      version AS "version",
      store_ids AS "storeIds",
      category_id AS "categoryId"
  `;

  return row ? shoppingListItemFromRow(row) : null;
}

export async function deleteShoppingListItem(
  database: DatabaseQuery,
  id: number,
): Promise<ShoppingListItem | null> {
  const [row] = await database<ShoppingListRow>`
    DELETE FROM shopping_list AS item
    WHERE item.id = ${id}
    RETURNING
      id,
      name,
      brand,
      quantity,
      notes,
      purchased,
      created_at AS "createdAt",
      updated_at AS "updatedAt",
      version AS "version",
      store_ids AS "storeIds",
      category_id AS "categoryId"
  `;

  return row ? shoppingListItemFromRow(row) : null;
}

function shoppingListItemFromRow(row: ShoppingListRow): ShoppingListItem {
  const brand = optionalString(row.brand);
  const notes = optionalString(row.notes);
  const createdAt = optionalISOString(row.createdAt);
  const updatedAt = optionalISOString(row.updatedAt);
  const version = optionalInteger(row.version);

  return {
    id: requiredInteger(row.id, 'shopping_list.id'),
    name: requiredString(row.name, 'shopping_list.name'),
    ...(brand ? { brand } : {}),
    quantity: optionalInteger(row.quantity) ?? 1,
    ...(notes ? { notes } : {}),
    purchased: optionalBoolean(row.purchased) ?? false,
    ...(createdAt ? { createdAt } : {}),
    ...(updatedAt ? { updatedAt } : {}),
    ...(version !== undefined ? { version } : {}),
    storeIds: optionalIntegerArray(row.storeIds),
    categoryId: optionalIntegerFromJSON(row.categoryId),
  };
}

function requireShoppingListItemRow(row: ShoppingListRow | undefined, operation: string): ShoppingListItem {
  if (!row) {
    throw new Error(`Expected shopping_list ${operation} to return a row.`);
  }

  return shoppingListItemFromRow(row);
}

function hasShoppingListItemUpdate(request: UpdateShoppingListItemRequest): boolean {
  return (
    request.name !== undefined ||
    request.brand !== undefined ||
    request.quantity !== undefined ||
    request.notes !== undefined ||
    request.purchased !== undefined ||
    request.storeIds !== undefined ||
    request.categoryId !== undefined
  );
}

function jsonb(value: unknown): string {
  return JSON.stringify(value);
}

function shoppingStoreFromRow(row: ShoppingStoreRow): ShoppingStore {
  const logo = optionalString(row.logo);

  return {
    id: requiredInteger(row.id, 'stores.id'),
    name: requiredString(row.name, 'stores.name'),
    ...(logo ? { logo } : {}),
  };
}

function shoppingCategoryFromRow(row: ShoppingCategoryRow): ShoppingCategory {
  return {
    id: requiredInteger(row.id, 'categories.id'),
    name: requiredString(row.name, 'categories.name'),
  };
}

function requiredString(value: unknown, fieldName: string): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`Expected ${fieldName} to be a non-empty string.`);
  }

  return value;
}

function optionalString(value: unknown): string | undefined {
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function requiredInteger(value: unknown, fieldName: string): number {
  const integer = optionalInteger(value);

  if (integer === undefined) {
    throw new Error(`Expected ${fieldName} to be an integer.`);
  }

  return integer;
}

function optionalInteger(value: unknown): number | undefined {
  if (typeof value === 'number' && Number.isInteger(value)) {
    return value;
  }

  if (typeof value === 'string' && value.trim().length > 0) {
    const parsed = Number(value);

    return Number.isInteger(parsed) ? parsed : undefined;
  }

  return undefined;
}

function optionalBoolean(value: unknown): boolean | undefined {
  if (typeof value === 'boolean') {
    return value;
  }

  if (typeof value === 'string') {
    if (value === 'true' || value === 't') {
      return true;
    }

    if (value === 'false' || value === 'f') {
      return false;
    }
  }

  return undefined;
}

function optionalIntegerArray(value: unknown): number[] {
  const parsedValue = parseJSONBValue(value);
  const values = Array.isArray(parsedValue) ? parsedValue : [parsedValue];

  return values
    .map(optionalInteger)
    .filter((id): id is number => id !== undefined);
}

function optionalIntegerFromJSON(value: unknown): number | null {
  const parsedValue = parseJSONBValue(value);

  if (Array.isArray(parsedValue)) {
    return optionalInteger(parsedValue[0]) ?? null;
  }

  return optionalInteger(parsedValue) ?? null;
}

function parseJSONBValue(value: unknown): unknown {
  if (typeof value !== 'string') {
    return value;
  }

  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}

function optionalISOString(value: unknown): string | undefined {
  if (value instanceof Date) {
    return value.toISOString();
  }

  if (typeof value !== 'string' || value.length === 0) {
    return undefined;
  }

  const timestamp = Date.parse(value);

  if (!Number.isFinite(timestamp)) {
    return value;
  }

  return new Date(timestamp).toISOString();
}
