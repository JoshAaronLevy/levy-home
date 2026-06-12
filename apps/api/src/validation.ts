import type {
  HomeAssistantEventCategory,
  HomeAssistantEventPayload,
  HomeAssistantEventSeverity,
  QuickActionId,
} from './contracts.js';
import { isLevyHomeEventType, LEVY_HOME_EVENT_TYPES } from './contracts.js';
import { HTTPError } from './httpError.js';

type ValidationResult<T> = { ok: true; value: T } | { ok: false; error: string; code?: string };

const quickActionIds = new Set<QuickActionId>(['close_garage', 'turn_off_all_lights', 'turn_off_light_group']);
const allowedQuickActionBodyKeys = new Set(['actionId', 'groupId']);
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

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
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

  if (value === 'garage' || value === 'doorbell') {
    return { ok: true, value };
  }

  return { ok: false, error: 'category must be garage or doorbell when provided.' };
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
