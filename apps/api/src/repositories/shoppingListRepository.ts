import type {
  CreateShoppingListItemRequest,
  ShoppingCategory,
  ShoppingItemStoreListing,
  ShoppingListData,
  ShoppingListItem,
  ShoppingStore,
  UpdateShoppingListItemRequest,
} from '../contracts.js';
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
  created: unknown;
  updated: unknown;
  version: unknown;
  categoryId: unknown;
  image: unknown;
  storeListings: unknown;
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
        COALESCE(to_jsonb(item) ->> 'created', to_jsonb(item) ->> 'created_at') AS "created",
        COALESCE(to_jsonb(item) ->> 'updated', to_jsonb(item) ->> 'updated_at') AS "updated",
        to_jsonb(item) ->> 'version' AS "version",
        item.category_id AS "categoryId",
        to_jsonb(item) ->> 'image' AS "image",
        to_jsonb(item) -> 'store_listings' AS "storeListings"
      FROM shopping_list item
      ORDER BY item.purchased ASC NULLS FIRST, lower(item.name) ASC
    `,
    database<ShoppingStoreRow>`
      SELECT
        id,
        name,
        logo
      FROM shopping_locations
      ORDER BY lower(name) ASC
    `,
    database<ShoppingCategoryRow>`
      SELECT
        id,
        name
      FROM shopping_categories
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
      COALESCE(to_jsonb(item) ->> 'created', to_jsonb(item) ->> 'created_at') AS "created",
      COALESCE(to_jsonb(item) ->> 'updated', to_jsonb(item) ->> 'updated_at') AS "updated",
      to_jsonb(item) ->> 'version' AS "version",
      item.category_id AS "categoryId",
      to_jsonb(item) ->> 'image' AS "image",
      to_jsonb(item) -> 'store_listings' AS "storeListings"
    FROM shopping_list item
    WHERE item.id = ${id}
    LIMIT 1
  `;

  return row ? shoppingListItemFromRow(row) : null;
}

export async function fetchNeededShoppingListItems(
  database: DatabaseQuery,
): Promise<ShoppingListItem[]> {
  const rows = await database<ShoppingListRow>`
    SELECT
      item.id,
      item.name,
      item.brand,
      item.quantity,
      item.notes,
      item.purchased,
      COALESCE(to_jsonb(item) ->> 'created', to_jsonb(item) ->> 'created_at') AS "created",
      COALESCE(to_jsonb(item) ->> 'updated', to_jsonb(item) ->> 'updated_at') AS "updated",
      to_jsonb(item) ->> 'version' AS "version",
      item.category_id AS "categoryId",
      to_jsonb(item) ->> 'image' AS "image",
      to_jsonb(item) -> 'store_listings' AS "storeListings"
    FROM shopping_list item
    WHERE item.purchased = false
    ORDER BY item.id ASC
    FOR SHARE
  `;

  return rows.map(shoppingListItemFromRow);
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
      COALESCE(to_jsonb(item) ->> 'created', to_jsonb(item) ->> 'created_at') AS "created",
      COALESCE(to_jsonb(item) ->> 'updated', to_jsonb(item) ->> 'updated_at') AS "updated",
      to_jsonb(item) ->> 'version' AS "version",
      item.category_id AS "categoryId",
      to_jsonb(item) ->> 'image' AS "image",
      to_jsonb(item) -> 'store_listings' AS "storeListings"
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
      category_id,
      image,
      store_listings
    )
    VALUES (
      ${request.name},
      ${request.brand ?? null},
      ${request.quantity ?? 1},
      ${request.notes ?? null},
      ${request.purchased ?? false},
      ${jsonb(request.categoryId ?? null)}::jsonb,
      ${request.image ?? null},
      ${jsonb(request.storeListings ?? [])}::jsonb
    )
    RETURNING
      id,
      name,
      brand,
      quantity,
      notes,
      purchased,
      COALESCE(to_jsonb(shopping_list) ->> 'created', to_jsonb(shopping_list) ->> 'created_at') AS "created",
      COALESCE(to_jsonb(shopping_list) ->> 'updated', to_jsonb(shopping_list) ->> 'updated_at') AS "updated",
      version AS "version",
      category_id AS "categoryId",
      image,
      store_listings AS "storeListings"
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
  const hasCategoryId = request.categoryId !== undefined;
  const hasImage = request.image !== undefined;
  const hasStoreListings = request.storeListings !== undefined;

  const [row] = await database<ShoppingListRow>`
    UPDATE shopping_list AS item
    SET
      name = CASE WHEN ${hasName} THEN ${request.name ?? null} ELSE item.name END,
      brand = CASE WHEN ${hasBrand} THEN ${request.brand ?? null} ELSE item.brand END,
      quantity = CASE WHEN ${hasQuantity} THEN ${request.quantity ?? null} ELSE item.quantity END,
      notes = CASE WHEN ${hasNotes} THEN ${request.notes ?? null} ELSE item.notes END,
      purchased = CASE WHEN ${hasPurchased} THEN ${request.purchased ?? null} ELSE item.purchased END,
      category_id = CASE WHEN ${hasCategoryId} THEN ${jsonb(request.categoryId ?? null)}::jsonb ELSE item.category_id END,
      image = CASE WHEN ${hasImage} THEN ${request.image ?? null} ELSE item.image END,
      store_listings = CASE
        WHEN ${hasStoreListings} THEN ${jsonb(request.storeListings ?? [])}::jsonb
        ELSE item.store_listings
      END
    WHERE item.id = ${id}
    RETURNING
      id,
      name,
      brand,
      quantity,
      notes,
      purchased,
      COALESCE(to_jsonb(item) ->> 'created', to_jsonb(item) ->> 'created_at') AS "created",
      COALESCE(to_jsonb(item) ->> 'updated', to_jsonb(item) ->> 'updated_at') AS "updated",
      version AS "version",
      category_id AS "categoryId",
      image,
      store_listings AS "storeListings"
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
      COALESCE(to_jsonb(item) ->> 'created', to_jsonb(item) ->> 'created_at') AS "created",
      COALESCE(to_jsonb(item) ->> 'updated', to_jsonb(item) ->> 'updated_at') AS "updated",
      version AS "version",
      category_id AS "categoryId",
      image,
      store_listings AS "storeListings"
  `;

  return row ? shoppingListItemFromRow(row) : null;
}

function shoppingListItemFromRow(row: ShoppingListRow): ShoppingListItem {
  const brand = optionalString(row.brand);
  const notes = optionalString(row.notes);
  const created = optionalISOString(row.created);
  const updated = optionalISOString(row.updated);
  const version = optionalInteger(row.version);
  const image = optionalString(row.image);

  return {
    id: requiredInteger(row.id, 'shopping_list.id'),
    name: requiredString(row.name, 'shopping_list.name'),
    ...(brand ? { brand } : {}),
    quantity: optionalInteger(row.quantity) ?? 1,
    ...(notes ? { notes } : {}),
    purchased: optionalBoolean(row.purchased) ?? false,
    ...(created ? { created } : {}),
    ...(updated ? { updated } : {}),
    ...(version !== undefined ? { version } : {}),
    categoryId: optionalIntegerFromJSON(row.categoryId),
    ...(image ? { image } : {}),
    storeListings: optionalRecordArray(row.storeListings),
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
    request.categoryId !== undefined ||
    request.image !== undefined ||
    request.storeListings !== undefined
  );
}

function shoppingStoreFromRow(row: ShoppingStoreRow): ShoppingStore {
  const logo = optionalString(row.logo);

  return {
    id: requiredInteger(row.id, 'shopping_locations.id'),
    name: requiredString(row.name, 'shopping_locations.name'),
    ...(logo ? { logo } : {}),
  };
}

function shoppingCategoryFromRow(row: ShoppingCategoryRow): ShoppingCategory {
  return {
    id: requiredInteger(row.id, 'shopping_categories.id'),
    name: requiredString(row.name, 'shopping_categories.name'),
  };
}

function optionalRecordArray(value: unknown): ShoppingItemStoreListing[] {
  const parsedValue = parseJSONBValue(value);

  if (!Array.isArray(parsedValue)) {
    return [];
  }

  return parsedValue.filter(isRecord);
}

function optionalIntegerFromJSON(value: unknown): number | null {
  const parsedValue = parseJSONBValue(value);

  if (Array.isArray(parsedValue)) {
    return optionalInteger(parsedValue[0]) ?? null;
  }

  return optionalInteger(parsedValue) ?? null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}
