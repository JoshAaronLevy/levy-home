import type {
  APNsEnvironment,
  CreateShoppingListItemRequest,
  DevicePreferenceLocator,
  DevicePlatform,
  HomeAssistantEventCategory,
  HomeAssistantEventPayload,
  HomeAssistantEventSeverity,
  NotificationPreferencesUpdateRequest,
  NotificationPreferenceUpdate,
  PushProvider,
  QuickActionId,
  RegisterDeviceRequest,
  TestPushPayload,
  UpdateShoppingListItemRequest,
} from './contracts.js';
import {
  isLevyHomeEventType,
  isNotificationPreferenceCategory,
  LEVY_HOME_EVENT_TYPES,
} from './contracts.js';
import { HTTPError } from './httpError.js';

type ValidationResult<T> = { ok: true; value: T } | { ok: false; error: string; code?: string };

const quickActionIds = new Set<QuickActionId>([
  'open_garage',
  'close_garage',
  'turn_off_all_lights',
  'turn_off_light_group',
]);
const allowedQuickActionBodyKeys = new Set(['actionId', 'groupId']);
const allowedCreateShoppingItemBodyKeys = new Set([
  'name',
  'brand',
  'quantity',
  'notes',
  'purchased',
  'storeIds',
  'categoryId',
  'mutationId',
]);
const allowedUpdateShoppingItemBodyKeys = allowedCreateShoppingItemBodyKeys;
const devicePlatforms = new Set<DevicePlatform>(['ios', 'android', 'unknown']);
const pushProviders = new Set<PushProvider>(['apns', 'expo']);
const apnsEnvironments = new Set<APNsEnvironment>(['sandbox', 'production']);
const forbiddenHomeAssistantKeys = new Set([
  'domain',
  'service',
  'serviceData',
  'service_data',
  'entityId',
  'entity_id',
  'target',
]);

export type QuickActionBody = {
  actionId: QuickActionId;
  groupId?: string;
};

export function validateCreateShoppingListItemBody(input: unknown): CreateShoppingListItemRequest {
  if (!isPlainRecord(input)) {
    throw invalidShoppingItem('Expected a JSON object shopping item payload.');
  }

  rejectUnsupportedShoppingItemFields(input, allowedCreateShoppingItemBodyKeys);

  const brand = readOptionalNullableShoppingItemString(input.brand, 'brand');
  const quantity = readOptionalShoppingItemInteger(input.quantity, 'quantity', { min: 1 });
  const notes = readOptionalNullableShoppingItemString(input.notes, 'notes');
  const purchased = readOptionalShoppingItemBoolean(input.purchased, 'purchased');
  const storeIds = readOptionalShoppingStoreIds(input.storeIds);
  const categoryId = readOptionalShoppingCategoryId(input.categoryId);
  const mutationId = readOptionalShoppingMutationId(input.mutationId);

  return {
    name: readRequiredShoppingItemName(input.name),
    ...(brand !== undefined ? { brand } : {}),
    quantity: quantity ?? 1,
    ...(notes !== undefined ? { notes } : {}),
    purchased: purchased ?? false,
    storeIds: storeIds ?? [],
    categoryId: categoryId ?? null,
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

  if (hasOwn(input, 'storeIds')) {
    request.storeIds = readRequiredShoppingStoreIds(input.storeIds);
  }

  if (hasOwn(input, 'categoryId')) {
    request.categoryId = readRequiredShoppingCategoryId(input.categoryId);
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

export function validateTestPushBody(input: unknown): TestPushPayload {
  if (input === undefined || input === null) {
    return defaultTestPushPayload();
  }

  if (!isPlainRecord(input)) {
    throw new HTTPError(400, 'Expected a JSON object test-push payload.', 'invalid_test_push_payload');
  }

  const title = readOptionalStringOrThrow(input.title, 'title') ?? 'Levy Home test';
  const body =
    readOptionalStringOrThrow(input.body, 'body') ?? 'This is a test notification from Levy Home.';

  return { title, body };
}

export function validateHomeAssistantEventPayload(input: unknown): ValidationResult<HomeAssistantEventPayload> {
  if (!isPlainRecord(input)) {
    return { ok: false, error: 'Expected a JSON object event payload.' };
  }

  if (!isLevyHomeEventType(input.type)) {
    return {
      ok: false,
      error: `Invalid event type. Expected one of: ${LEVY_HOME_EVENT_TYPES.join(', ')}.`,
    };
  }

  const entityId = readRequiredString(input.entityId, 'entityId');
  if (!entityId.ok) {
    return entityId;
  }

  const occurredAt = readOptionalString(input.occurredAt, 'occurredAt');
  if (!occurredAt.ok) {
    return occurredAt;
  }

  if (occurredAt.value && Number.isNaN(Date.parse(occurredAt.value))) {
    return { ok: false, error: 'occurredAt must be an ISO date string when provided.' };
  }

  const title = readOptionalString(input.title, 'title');
  if (!title.ok) {
    return title;
  }

  const message = readOptionalString(input.message, 'message');
  if (!message.ok) {
    return message;
  }

  const category = readOptionalCategory(input.category);
  if (!category.ok) {
    return category;
  }

  const severity = readOptionalPayloadSeverity(input.severity);
  if (!severity.ok) {
    return severity;
  }

  const source = readOptionalString(input.source, 'source');
  if (!source.ok) {
    return source;
  }

  if (input.metadata !== undefined && !isPlainRecord(input.metadata)) {
    return { ok: false, error: 'metadata must be a JSON object when provided.' };
  }

  return {
    ok: true,
    value: {
      type: input.type,
      entityId: entityId.value,
      ...(category.value ? { category: category.value } : {}),
      ...(severity.value ? { severity: severity.value } : {}),
      ...(source.value ? { source: source.value } : {}),
      ...(occurredAt.value ? { occurredAt: occurredAt.value } : {}),
      ...(title.value ? { title: title.value } : {}),
      ...(message.value ? { message: message.value } : {}),
      ...(input.metadata ? { metadata: input.metadata } : {}),
    },
  };
}

export function validateQuickActionBody(input: unknown): QuickActionBody {
  if (!isPlainRecord(input)) {
    throw new HTTPError(400, 'Expected a JSON object quick-action payload.', 'invalid_action_payload');
  }

  const keys = Object.keys(input);
  const forbiddenKey = keys.find((key) => forbiddenHomeAssistantKeys.has(key));

  if (forbiddenKey) {
    throw new HTTPError(
      400,
      'Arbitrary Home Assistant service/entity payloads are not supported.',
      'arbitrary_home_assistant_payload_rejected',
    );
  }

  const unsupportedKey = keys.find((key) => !allowedQuickActionBodyKeys.has(key));

  if (unsupportedKey) {
    throw new HTTPError(400, `Unsupported quick-action field: ${unsupportedKey}`, 'unsupported_action_field');
  }

  if (!quickActionIds.has(input.actionId as QuickActionId)) {
    throw new HTTPError(400, 'Unsupported quick action.', 'unsupported_action');
  }

  if (input.groupId !== undefined && typeof input.groupId !== 'string') {
    throw new HTTPError(400, 'groupId must be a string when provided.', 'invalid_group_id');
  }

  const groupId = typeof input.groupId === 'string' && input.groupId.trim() ? input.groupId.trim() : undefined;
  return { actionId: input.actionId as QuickActionId, ...(groupId ? { groupId } : {}) };
}

export function validateRegisterDeviceBody(input: unknown): RegisterDeviceRequest {
  if (!isPlainRecord(input)) {
    throw new HTTPError(400, 'Expected a JSON object device registration payload.', 'invalid_device_registration');
  }

  const token = readDeviceToken(input);
  const provider = readPushProvider(input.provider, input.pushToken !== undefined);
  const platform = readDevicePlatform(input.platform, provider);
  const environment = readAPNsEnvironment(input.environment, provider);
  const appVersion = readOptionalStringOrThrow(input.appVersion, 'appVersion');
  const deviceName = readOptionalStringOrThrow(input.deviceName, 'deviceName');

  return {
    token,
    platform,
    provider,
    ...(environment ? { environment } : {}),
    ...(appVersion ? { appVersion } : {}),
    ...(deviceName ? { deviceName } : {}),
  };
}

export function validateNotificationPreferencesBody(input: unknown): NotificationPreferencesUpdateRequest {
  if (!isPlainRecord(input)) {
    throw new HTTPError(
      400,
      'Expected a JSON object notification-preferences payload.',
      'invalid_notification_preferences_payload',
    );
  }

  if (!Array.isArray(input.preferences)) {
    throw new HTTPError(400, 'preferences must be an array.', 'invalid_notification_preferences');
  }

  const preferences = input.preferences.map((preference, index) => {
    if (!isPlainRecord(preference)) {
      throw new HTTPError(
        400,
        `preferences[${index}] must be a JSON object.`,
        'invalid_notification_preference',
      );
    }

    if (!isNotificationPreferenceCategory(preference.category)) {
      throw new HTTPError(
        400,
        `Unsupported notification preference category at preferences[${index}].`,
        'unsupported_notification_preference',
      );
    }

    if (typeof preference.isEnabled !== 'boolean') {
      throw new HTTPError(
        400,
        `preferences[${index}].isEnabled must be a boolean.`,
        'invalid_notification_preference',
      );
    }

    return {
      category: preference.category,
      isEnabled: preference.isEnabled,
    } satisfies NotificationPreferenceUpdate;
  });

  return {
    preferences,
    locator: readDevicePreferenceLocator(input),
  };
}

export function validateNotificationPreferencesQuery(input: Record<string, unknown>): DevicePreferenceLocator | undefined {
  if (typeof input.deviceId === 'string' && input.deviceId.trim()) {
    return { deviceId: input.deviceId.trim() };
  }

  const tokenValue = typeof input.deviceToken === 'string' ? input.deviceToken : input.token;
  if (typeof tokenValue !== 'string' || tokenValue.trim().length === 0) {
    return undefined;
  }

  const provider = readPushProvider(input.provider, false);
  const environment = readAPNsEnvironment(input.environment, provider);

  return {
    token: tokenValue.trim(),
    provider,
    ...(environment ? { environment } : {}),
  };
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
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

function readOptionalShoppingStoreIds(value: unknown): number[] | undefined {
  if (value === undefined) {
    return undefined;
  }

  return readRequiredShoppingStoreIds(value);
}

function readRequiredShoppingStoreIds(value: unknown): number[] {
  if (!Array.isArray(value)) {
    throw invalidShoppingItem('storeIds must be an array of integers.');
  }

  return value.map((storeId, index) => readRequiredShoppingItemInteger(storeId, `storeIds[${index}]`, { min: 1 }));
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
    request.storeIds !== undefined ||
    request.categoryId !== undefined
  );
}

function hasOwn(input: Record<string, unknown>, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(input, key);
}

function invalidShoppingItem(message: string): HTTPError {
  return new HTTPError(400, message, 'invalid_shopping_item');
}

function readDeviceToken(input: Record<string, unknown>): string {
  const value = input.token ?? input.deviceToken ?? input.pushToken;

  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new HTTPError(400, 'token is required and must be a non-empty string.', 'invalid_device_token');
  }

  return value.trim();
}

function readPushProvider(value: unknown, inferredExpo: boolean): PushProvider {
  if (value === undefined) {
    if (inferredExpo) {
      return 'expo';
    }

    throw new HTTPError(
      400,
      'provider is required for provider-aware device registrations.',
      'missing_push_provider',
    );
  }

  if (typeof value === 'string' && pushProviders.has(value as PushProvider)) {
    return value as PushProvider;
  }

  throw new HTTPError(400, 'provider must be apns or expo.', 'invalid_push_provider');
}

function readDevicePlatform(value: unknown, provider: PushProvider): DevicePlatform {
  if (value === undefined) {
    return provider === 'apns' ? 'ios' : 'unknown';
  }

  if (typeof value === 'string' && devicePlatforms.has(value as DevicePlatform)) {
    const platform = value as DevicePlatform;

    if (provider === 'apns' && platform !== 'ios') {
      throw new HTTPError(400, 'APNs device registrations must use platform ios.', 'invalid_device_platform');
    }

    return platform;
  }

  throw new HTTPError(400, 'platform must be ios, android, or unknown.', 'invalid_device_platform');
}

function readAPNsEnvironment(value: unknown, provider: PushProvider): APNsEnvironment | undefined {
  if (provider === 'expo') {
    if (value === undefined) {
      return undefined;
    }

    if (typeof value === 'string' && apnsEnvironments.has(value as APNsEnvironment)) {
      return value as APNsEnvironment;
    }

    throw new HTTPError(400, 'environment must be sandbox or production when provided.', 'invalid_apns_environment');
  }

  if (typeof value === 'string' && apnsEnvironments.has(value as APNsEnvironment)) {
    return value as APNsEnvironment;
  }

  throw new HTTPError(
    400,
    'APNs device registrations require environment sandbox or production.',
    'missing_apns_environment',
  );
}

function readOptionalStringOrThrow(value: unknown, fieldName: string): string | undefined {
  const result = readOptionalString(value, fieldName);

  if (!result.ok) {
    throw new HTTPError(400, result.error, `invalid_${fieldName}`);
  }

  return result.value;
}

function defaultTestPushPayload(): TestPushPayload {
  return {
    title: 'Levy Home test',
    body: 'This is a test notification from Levy Home.',
  };
}

function readDevicePreferenceLocator(input: Record<string, unknown>): DevicePreferenceLocator {
  if (typeof input.deviceId === 'string' && input.deviceId.trim()) {
    return { deviceId: input.deviceId.trim() };
  }

  const token = readDeviceToken(input);
  const provider = readPushProvider(input.provider, input.pushToken !== undefined);
  const environment = readAPNsEnvironment(input.environment, provider);

  return {
    token,
    provider,
    ...(environment ? { environment } : {}),
  };
}

function readRequiredString(value: unknown, fieldName: string): ValidationResult<string> {
  if (typeof value !== 'string' || value.trim().length === 0) {
    return { ok: false, error: `${fieldName} is required and must be a non-empty string.` };
  }

  return { ok: true, value: value.trim() };
}

function readOptionalString(value: unknown, fieldName: string): ValidationResult<string | undefined> {
  if (value === undefined) {
    return { ok: true, value: undefined };
  }

  if (typeof value !== 'string') {
    return { ok: false, error: `${fieldName} must be a string when provided.` };
  }

  const trimmed = value.trim();
  return { ok: true, value: trimmed.length > 0 ? trimmed : undefined };
}

function readOptionalCategory(value: unknown): ValidationResult<HomeAssistantEventCategory | undefined> {
  if (value === undefined) {
    return { ok: true, value: undefined };
  }

  if (value === 'garage' || value === 'doorbell' || value === 'phone') {
    return { ok: true, value };
  }

  return { ok: false, error: 'category must be garage, doorbell, or phone when provided.' };
}

function readOptionalPayloadSeverity(value: unknown): ValidationResult<HomeAssistantEventSeverity | undefined> {
  if (value === undefined) {
    return { ok: true, value: undefined };
  }

  if (value === 'normal' || value === 'high') {
    return { ok: true, value };
  }

  return { ok: false, error: 'severity must be normal or high when provided.' };
}
