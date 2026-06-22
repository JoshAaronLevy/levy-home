import type {
  ShoppingCategory,
  ShoppingListData,
  ShoppingListItem,
  ShoppingStore,
} from './contracts.js';
import { getDatabaseClient, type DatabaseQuery } from './dbClient.js';

export type ShoppingListStore = {
  fetchShoppingList: () => Promise<ShoppingListData>;
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
  return {
    async fetchShoppingList() {
      return fetchShoppingListData(database ?? getDatabaseClient());
    },
  };
}

export async function fetchShoppingListData(database: DatabaseQuery): Promise<ShoppingListData> {
  const [itemRows, storeRows, categoryRows] = await Promise.all([
    database<ShoppingListRow>`
      SELECT
        id,
        name,
        brand,
        quantity,
        notes,
        purchased,
        created_at AS "createdAt",
        updated_at AS "updatedAt",
        store_ids AS "storeIds",
        category_id AS "categoryId"
      FROM shopping_list
      ORDER BY purchased ASC NULLS FIRST, lower(name) ASC
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

function shoppingListItemFromRow(row: ShoppingListRow): ShoppingListItem {
  const brand = optionalString(row.brand);
  const notes = optionalString(row.notes);
  const createdAt = optionalISOString(row.createdAt);
  const updatedAt = optionalISOString(row.updatedAt);

  return {
    id: requiredInteger(row.id, 'shopping_list.id'),
    name: requiredString(row.name, 'shopping_list.name'),
    ...(brand ? { brand } : {}),
    quantity: optionalInteger(row.quantity) ?? 1,
    ...(notes ? { notes } : {}),
    purchased: optionalBoolean(row.purchased) ?? false,
    ...(createdAt ? { createdAt } : {}),
    ...(updatedAt ? { updatedAt } : {}),
    storeIds: optionalIntegerArray(row.storeIds),
    categoryId: optionalIntegerFromJSON(row.categoryId),
  };
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
