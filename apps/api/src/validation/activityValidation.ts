import {
  isLevyHomeEventType,
  LEVY_HOME_EVENT_TYPES,
  type HomeAssistantEventCategory,
  type HomeAssistantEventPayload,
  type HomeAssistantEventSeverity,
} from '../contracts/activity.js';
import {
  isPlainRecord,
  readOptionalString,
  readRequiredString,
  type ValidationResult,
} from './shared.js';

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

function readOptionalCategory(value: unknown): ValidationResult<HomeAssistantEventCategory | undefined> {
  if (value === undefined) {
    return { ok: true, value: undefined };
  }

  if (value === 'garage' || value === 'doorbell' || value === 'phone' || value === 'presence') {
    return { ok: true, value };
  }

  return { ok: false, error: 'category must be garage, doorbell, phone, or presence when provided.' };
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
