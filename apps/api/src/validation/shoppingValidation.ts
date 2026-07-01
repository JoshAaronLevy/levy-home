import type {
  CreateShoppingListItemRequest,
  ShoppingItemStoreListing,
  UpdateShoppingListItemRequest,
} from '../contracts/shopping.js';
import { HTTPError } from '../http/errors.js';
import { hasOwn, isPlainRecord } from './shared.js';

const allowedCreateShoppingItemBodyKeys = new Set([
  'name',
  'brand',
  'quantity',
  'notes',
  'purchased',
  'categoryId',
  'image',
  'storeListings',
  'mutationId',
]);
const allowedUpdateShoppingItemBodyKeys = allowedCreateShoppingItemBodyKeys;

export function validateCreateShoppingListItemBody(input: unknown): CreateShoppingListItemRequest {
  if (!isPlainRecord(input)) {
    throw invalidShoppingItem('Expected a JSON object shopping item payload.');
  }

  rejectUnsupportedShoppingItemFields(input, allowedCreateShoppingItemBodyKeys);

  const brand = readOptionalNullableShoppingItemString(input.brand, 'brand');
  const quantity = readOptionalShoppingItemInteger(input.quantity, 'quantity', { min: 1 });
  const notes = readOptionalNullableShoppingItemString(input.notes, 'notes');
  const purchased = readOptionalShoppingItemBoolean(input.purchased, 'purchased');
  const categoryId = readOptionalShoppingCategoryId(input.categoryId);
  const image = readOptionalNullableShoppingItemString(input.image, 'image');
  const storeListings = readOptionalShoppingStoreListings(input.storeListings);
  const mutationId = readOptionalShoppingMutationId(input.mutationId);

  return {
    name: readRequiredShoppingItemName(input.name),
    ...(brand !== undefined ? { brand } : {}),
    quantity: quantity ?? 1,
    ...(notes !== undefined ? { notes } : {}),
    purchased: purchased ?? false,
    categoryId: categoryId ?? null,
    ...(image !== undefined ? { image } : {}),
    storeListings: storeListings ?? [],
    ...(mutationId ? { mutationId } : {}),
  };
}

export function validateUpdateShoppingListItemBody(input: unknown): UpdateShoppingListItemRequest {
  if (!isPlainRecord(input)) {
    throw invalidShoppingItem('Expected a JSON object shopping item payload.');
  }

  rejectUnsupportedShoppingItemFields(input, allowedUpdateShoppingItemBodyKeys);

  const request: UpdateShoppingListItemRequest = {};

  if (hasOwn(input, 'name')) {
    request.name = readRequiredShoppingItemName(input.name);
  }

  if (hasOwn(input, 'brand')) {
    request.brand = readOptionalNullableShoppingItemString(input.brand, 'brand') ?? null;
  }

  if (hasOwn(input, 'quantity')) {
    request.quantity = readRequiredShoppingItemInteger(input.quantity, 'quantity', { min: 1 });
  }

  if (hasOwn(input, 'notes')) {
    request.notes = readOptionalNullableShoppingItemString(input.notes, 'notes') ?? null;
  }

  if (hasOwn(input, 'purchased')) {
    request.purchased = readRequiredShoppingItemBoolean(input.purchased, 'purchased');
  }

  if (hasOwn(input, 'categoryId')) {
    request.categoryId = readRequiredShoppingCategoryId(input.categoryId);
  }

  if (hasOwn(input, 'image')) {
    request.image = readOptionalNullableShoppingItemString(input.image, 'image') ?? null;
  }

  if (hasOwn(input, 'storeListings')) {
    request.storeListings = readRequiredShoppingStoreListings(input.storeListings);
  }

  const mutationId = readOptionalShoppingMutationId(input.mutationId);

  if (mutationId) {
    request.mutationId = mutationId;
  }

  if (!hasMutableShoppingItemField(request)) {
    throw invalidShoppingItem('At least one shopping item field must be provided.');
  }

  return request;
}

export function validateShoppingListItemLookupQuery(input: Record<string, unknown>): string {
  return readRequiredShoppingItemName(input.name);
}

export function validateShoppingProductSearchQuery(input: Record<string, unknown>): string {
  return readRequiredShoppingItemName(input.term);
}

function rejectUnsupportedShoppingItemFields(input: Record<string, unknown>, allowedKeys: Set<string>): void {
  const unsupportedKey = Object.keys(input).find((key) => !allowedKeys.has(key));

  if (unsupportedKey) {
    throw invalidShoppingItem(`Unsupported shopping item field: ${unsupportedKey}`);
  }
}

function readRequiredShoppingItemName(value: unknown): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw invalidShoppingItem('name is required and must be a non-empty string.');
  }

  return value.trim();
}

function readOptionalNullableShoppingItemString(value: unknown, fieldName: string): string | null | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (value === null) {
    return null;
  }

  if (typeof value !== 'string') {
    throw invalidShoppingItem(`${fieldName} must be a string or null when provided.`);
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function readOptionalShoppingItemInteger(
  value: unknown,
  fieldName: string,
  options: { min?: number } = {},
): number | undefined {
  if (value === undefined) {
    return undefined;
  }

  return readRequiredShoppingItemInteger(value, fieldName, options);
}

function readRequiredShoppingItemInteger(
  value: unknown,
  fieldName: string,
  options: { min?: number } = {},
): number {
  if (typeof value !== 'number' || !Number.isInteger(value)) {
    throw invalidShoppingItem(`${fieldName} must be an integer.`);
  }

  if (options.min !== undefined && value < options.min) {
    throw invalidShoppingItem(`${fieldName} must be at least ${options.min}.`);
  }

  return value;
}

function readOptionalShoppingItemBoolean(value: unknown, fieldName: string): boolean | undefined {
  if (value === undefined) {
    return undefined;
  }

  return readRequiredShoppingItemBoolean(value, fieldName);
}

function readRequiredShoppingItemBoolean(value: unknown, fieldName: string): boolean {
  if (typeof value !== 'boolean') {
    throw invalidShoppingItem(`${fieldName} must be a boolean.`);
  }

  return value;
}

function readOptionalShoppingStoreListings(value: unknown): ShoppingItemStoreListing[] | undefined {
  if (value === undefined) {
    return undefined;
  }

  return readRequiredShoppingStoreListings(value);
}

function readRequiredShoppingStoreListings(value: unknown): ShoppingItemStoreListing[] {
  if (!Array.isArray(value)) {
    throw invalidShoppingItem('storeListings must be an array of objects.');
  }

  return value.map((listing, index) => readRequiredShoppingStoreListing(listing, index));
}

function readRequiredShoppingStoreListing(value: unknown, index: number): ShoppingItemStoreListing {
  if (!isPlainRecord(value)) {
    throw invalidShoppingItem(`storeListings[${index}] must be a JSON object.`);
  }

  const listing: ShoppingItemStoreListing = { ...value };

  if (hasOwn(value, 'storeId')) {
    listing.storeId = readRequiredShoppingItemInteger(value.storeId, `storeListings[${index}].storeId`, { min: 1 });
  }

  if (hasOwn(value, 'storeName')) {
    const storeName = readOptionalNullableShoppingItemString(value.storeName, `storeListings[${index}].storeName`);

    if (storeName) {
      listing.storeName = storeName;
    } else {
      delete listing.storeName;
    }
  }

  if (hasOwn(value, 'source')) {
    const source = readOptionalNullableShoppingItemString(value.source, `storeListings[${index}].source`);

    if (source) {
      listing.source = source;
    } else {
      delete listing.source;
    }
  }

  if (hasOwn(value, 'krogerLocationId')) {
    const krogerLocationId = readOptionalNullableShoppingItemString(
      value.krogerLocationId,
      `storeListings[${index}].krogerLocationId`,
    );

    if (krogerLocationId) {
      listing.krogerLocationId = krogerLocationId;
    } else {
      delete listing.krogerLocationId;
    }
  }

  return listing;
}

function readOptionalShoppingCategoryId(value: unknown): number | null | undefined {
  if (value === undefined) {
    return undefined;
  }

  return readRequiredShoppingCategoryId(value);
}

function readRequiredShoppingCategoryId(value: unknown): number | null {
  if (value === null) {
    return null;
  }

  return readRequiredShoppingItemInteger(value, 'categoryId', { min: 1 });
}

function readOptionalShoppingMutationId(value: unknown): string | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== 'string') {
    throw invalidShoppingItem('mutationId must be a string when provided.');
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function hasMutableShoppingItemField(request: UpdateShoppingListItemRequest): boolean {
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

function invalidShoppingItem(message: string): HTTPError {
  return new HTTPError(400, message, 'invalid_shopping_item');
}
