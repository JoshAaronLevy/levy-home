import type { CreateToDoLocationRequest } from '../contracts/todo.js';
import { HTTPError } from '../http/errors.js';
import { isPlainRecord } from './shared.js';

const allowedCreateToDoLocationBodyKeys = new Set([
  'name',
  'address',
  'mapkitTitle',
  'mapkitSubtitle',
  'latitude',
  'longitude',
  'createdBy',
  'favoritedBy',
]);

export function validateCreateToDoLocationBody(input: unknown): CreateToDoLocationRequest {
  if (!isPlainRecord(input)) {
    throw invalidToDoLocation('Expected a JSON object to-do location payload.');
  }

  rejectUnsupportedToDoLocationFields(input);

  const address = readOptionalNullableToDoLocationString(input.address, 'address');
  const mapkitTitle = readOptionalNullableToDoLocationString(input.mapkitTitle, 'mapkitTitle');
  const mapkitSubtitle = readOptionalNullableToDoLocationString(input.mapkitSubtitle, 'mapkitSubtitle');
  const latitude = readOptionalNullableToDoLocationNumber(input.latitude, 'latitude');
  const longitude = readOptionalNullableToDoLocationNumber(input.longitude, 'longitude');
  const createdBy = readOptionalNullableToDoLocationInteger(input.createdBy, 'createdBy');
  const favoritedBy = readOptionalToDoLocationUserIdArray(input.favoritedBy, 'favoritedBy');

  return {
    name: readRequiredToDoLocationName(input.name),
    ...(address !== undefined ? { address } : {}),
    ...(mapkitTitle !== undefined ? { mapkitTitle } : {}),
    ...(mapkitSubtitle !== undefined ? { mapkitSubtitle } : {}),
    ...(latitude !== undefined ? { latitude } : {}),
    ...(longitude !== undefined ? { longitude } : {}),
    ...(createdBy !== undefined ? { createdBy } : {}),
    favoritedBy: favoritedBy ?? [],
  };
}

function rejectUnsupportedToDoLocationFields(input: Record<string, unknown>): void {
  const unsupportedKey = Object.keys(input).find((key) => !allowedCreateToDoLocationBodyKeys.has(key));

  if (unsupportedKey) {
    throw invalidToDoLocation(`Unsupported to-do location field: ${unsupportedKey}`);
  }
}

function readRequiredToDoLocationName(value: unknown): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw invalidToDoLocation('name is required and must be a non-empty string.');
  }

  return value.trim();
}

function readOptionalNullableToDoLocationString(
  value: unknown,
  fieldName: string,
): string | null | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (value === null) {
    return null;
  }

  if (typeof value !== 'string') {
    throw invalidToDoLocation(`${fieldName} must be a string or null when provided.`);
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function readOptionalNullableToDoLocationNumber(
  value: unknown,
  fieldName: string,
): number | null | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (value === null) {
    return null;
  }

  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw invalidToDoLocation(`${fieldName} must be a finite number or null when provided.`);
  }

  return value;
}

function readOptionalNullableToDoLocationInteger(
  value: unknown,
  fieldName: string,
): number | null | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (value === null) {
    return null;
  }

  if (typeof value !== 'number' || !Number.isInteger(value) || value < 1) {
    throw invalidToDoLocation(`${fieldName} must be a positive integer or null when provided.`);
  }

  return value;
}

function readOptionalToDoLocationUserIdArray(value: unknown, fieldName: string): number[] | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (!Array.isArray(value)) {
    throw invalidToDoLocation(`${fieldName} must be an array of user ids when provided.`);
  }

  const userIds = value.map((userId, index) => {
    if (typeof userId !== 'number' || !Number.isInteger(userId) || userId < 1) {
      throw invalidToDoLocation(`${fieldName}[${index}] must be a positive integer.`);
    }

    return userId;
  });

  return Array.from(new Set(userIds));
}

function invalidToDoLocation(message: string): HTTPError {
  return new HTTPError(400, message, 'invalid_todo_location');
}
