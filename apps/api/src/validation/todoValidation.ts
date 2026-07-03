import type {
  CreateToDoItemRequest,
  CreateToDoLocationRequest,
  DeleteToDoItemRequest,
  ToDoRecurring,
  ToDoStatus,
  UpdateToDoItemRequest,
} from '../contracts/todo.js';
import { HTTPError } from '../http/errors.js';
import { hasOwn, isPlainRecord } from './shared.js';

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
const allowedCreateToDoItemBodyKeys = new Set([
  'name',
  'status',
  'locationIds',
  'date',
  'recurring',
  'createdBy',
  'actor',
  'mutationId',
]);
const allowedUpdateToDoItemBodyKeys = allowedCreateToDoItemBodyKeys;
const allowedDeleteToDoItemBodyKeys = new Set(['actor', 'mutationId']);

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
  const createdBy = readOptionalNullablePositiveInteger(input.createdBy, 'createdBy', invalidToDoLocation);
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

export function validateCreateToDoItemBody(input: unknown): CreateToDoItemRequest {
  if (!isPlainRecord(input)) {
    throw invalidToDoItem('Expected a JSON object to-do item payload.');
  }

  rejectUnsupportedToDoFields(input, allowedCreateToDoItemBodyKeys, invalidToDoItem);

  const status = readOptionalToDoStatus(input.status);
  const locationIds = readOptionalToDoItemIdArray(input.locationIds, 'locationIds');
  const date = readOptionalNullableToDoDate(input.date);
  const recurring = readOptionalNullableToDoRecurring(input.recurring);
  const createdBy = readOptionalNullablePositiveInteger(input.createdBy, 'createdBy', invalidToDoItem);
  const actor = readOptionalToDoActor(input.actor);
  const mutationId = readOptionalToDoMutationId(input.mutationId);

  return {
    name: readRequiredToDoItemName(input.name),
    status: status ?? 'open',
    locationIds: locationIds ?? [],
    ...(date !== undefined ? { date } : {}),
    ...(recurring !== undefined ? { recurring } : {}),
    ...(createdBy !== undefined ? { createdBy } : {}),
    ...(actor ? { actor } : {}),
    ...(mutationId ? { mutationId } : {}),
  };
}

export function validateUpdateToDoItemBody(input: unknown): UpdateToDoItemRequest {
  if (!isPlainRecord(input)) {
    throw invalidToDoItem('Expected a JSON object to-do item payload.');
  }

  rejectUnsupportedToDoFields(input, allowedUpdateToDoItemBodyKeys, invalidToDoItem);

  const request: UpdateToDoItemRequest = {};

  if (hasOwn(input, 'name')) {
    request.name = readRequiredToDoItemName(input.name);
  }

  if (hasOwn(input, 'status')) {
    request.status = readRequiredToDoStatus(input.status);
  }

  if (hasOwn(input, 'locationIds')) {
    request.locationIds = readRequiredToDoItemIdArray(input.locationIds, 'locationIds');
  }

  if (hasOwn(input, 'date')) {
    request.date = readOptionalNullableToDoDate(input.date) ?? null;
  }

  if (hasOwn(input, 'recurring')) {
    request.recurring = readOptionalNullableToDoRecurring(input.recurring) ?? null;
  }

  if (hasOwn(input, 'createdBy')) {
    request.createdBy = readOptionalNullablePositiveInteger(input.createdBy, 'createdBy', invalidToDoItem) ?? null;
  }

  const actor = readOptionalToDoActor(input.actor);
  const mutationId = readOptionalToDoMutationId(input.mutationId);

  if (actor) {
    request.actor = actor;
  }

  if (mutationId) {
    request.mutationId = mutationId;
  }

  if (!hasMutableToDoItemField(request)) {
    throw invalidToDoItem('At least one to-do item field must be provided.');
  }

  return request;
}

export function validateDeleteToDoItemBody(input: unknown): DeleteToDoItemRequest {
  if (input === undefined || input === null) {
    return {};
  }

  if (!isPlainRecord(input)) {
    throw invalidToDoItem('Expected a JSON object to-do item payload.');
  }

  rejectUnsupportedToDoFields(input, allowedDeleteToDoItemBodyKeys, invalidToDoItem);

  const actor = readOptionalToDoActor(input.actor);
  const mutationId = readOptionalToDoMutationId(input.mutationId);

  return {
    ...(actor ? { actor } : {}),
    ...(mutationId ? { mutationId } : {}),
  };
}

function rejectUnsupportedToDoLocationFields(input: Record<string, unknown>): void {
  rejectUnsupportedToDoFields(input, allowedCreateToDoLocationBodyKeys, invalidToDoLocation);
}

function rejectUnsupportedToDoFields(
  input: Record<string, unknown>,
  allowedKeys: Set<string>,
  makeError: (message: string) => HTTPError,
): void {
  const unsupportedKey = Object.keys(input).find((key) => !allowedKeys.has(key));

  if (unsupportedKey) {
    throw makeError(`Unsupported to-do field: ${unsupportedKey}`);
  }
}

function readRequiredToDoLocationName(value: unknown): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw invalidToDoLocation('name is required and must be a non-empty string.');
  }

  return value.trim();
}

function readRequiredToDoItemName(value: unknown): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw invalidToDoItem('name is required and must be a non-empty string.');
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

function readOptionalNullablePositiveInteger(
  value: unknown,
  fieldName: string,
  makeError: (message: string) => HTTPError,
): number | null | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (value === null) {
    return null;
  }

  if (typeof value !== 'number' || !Number.isInteger(value) || value < 1) {
    throw makeError(`${fieldName} must be a positive integer or null when provided.`);
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

function readOptionalToDoItemIdArray(value: unknown, fieldName: string): number[] | undefined {
  if (value === undefined) {
    return undefined;
  }

  return readRequiredToDoItemIdArray(value, fieldName);
}

function readRequiredToDoItemIdArray(value: unknown, fieldName: string): number[] {
  if (!Array.isArray(value)) {
    throw invalidToDoItem(`${fieldName} must be an array of ids when provided.`);
  }

  const ids = value.map((id, index) => {
    if (typeof id !== 'number' || !Number.isInteger(id) || id < 1) {
      throw invalidToDoItem(`${fieldName}[${index}] must be a positive integer.`);
    }

    return id;
  });

  return Array.from(new Set(ids));
}

function readOptionalToDoStatus(value: unknown): ToDoStatus | undefined {
  if (value === undefined) {
    return undefined;
  }

  return readRequiredToDoStatus(value);
}

function readRequiredToDoStatus(value: unknown): ToDoStatus {
  if (value === 'open' || value === 'completed' || value === 'canceled') {
    return value;
  }

  throw invalidToDoItem('status must be open, completed, or canceled.');
}

function readOptionalNullableToDoRecurring(value: unknown): ToDoRecurring | null | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (value === null) {
    return null;
  }

  if (value === 'daily' || value === 'weekly' || value === 'monthly' || value === 'quarterly') {
    return value;
  }

  throw invalidToDoItem('recurring must be daily, weekly, monthly, quarterly, or null.');
}

function readOptionalNullableToDoDate(value: unknown): string | null | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (value === null) {
    return null;
  }

  if (typeof value !== 'string') {
    throw invalidToDoItem('date must be an ISO timestamp string or null when provided.');
  }

  const trimmed = value.trim();

  if (trimmed.length === 0) {
    return null;
  }

  if (!Number.isFinite(Date.parse(trimmed))) {
    throw invalidToDoItem('date must be an ISO timestamp string or null when provided.');
  }

  return trimmed;
}

function readOptionalToDoActor(value: unknown): string | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== 'string') {
    throw invalidToDoItem('actor must be a string when provided.');
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function readOptionalToDoMutationId(value: unknown): string | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== 'string') {
    throw invalidToDoItem('mutationId must be a string when provided.');
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function hasMutableToDoItemField(request: UpdateToDoItemRequest): boolean {
  return (
    request.name !== undefined ||
    request.status !== undefined ||
    request.locationIds !== undefined ||
    request.date !== undefined ||
    request.recurring !== undefined ||
    request.createdBy !== undefined
  );
}

function invalidToDoLocation(message: string): HTTPError {
  return new HTTPError(400, message, 'invalid_todo_location');
}

function invalidToDoItem(message: string): HTTPError {
  return new HTTPError(400, message, 'invalid_todo_item');
}
