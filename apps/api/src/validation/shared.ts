import { HTTPError } from '../http/errors.js';

export type ValidationResult<T> = { ok: true; value: T } | { ok: false; error: string; code?: string };

export function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function hasOwn(input: Record<string, unknown>, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(input, key);
}

export function readRequiredString(value: unknown, fieldName: string): ValidationResult<string> {
  if (typeof value !== 'string' || value.trim().length === 0) {
    return { ok: false, error: `${fieldName} is required and must be a non-empty string.` };
  }

  return { ok: true, value: value.trim() };
}

export function readOptionalString(value: unknown, fieldName: string): ValidationResult<string | undefined> {
  if (value === undefined) {
    return { ok: true, value: undefined };
  }

  if (typeof value !== 'string') {
    return { ok: false, error: `${fieldName} must be a string when provided.` };
  }

  const trimmed = value.trim();
  return { ok: true, value: trimmed.length > 0 ? trimmed : undefined };
}

export function readOptionalStringOrThrow(value: unknown, fieldName: string): string | undefined {
  const result = readOptionalString(value, fieldName);

  if (!result.ok) {
    throw new HTTPError(400, result.error, `invalid_${fieldName}`);
  }

  return result.value;
}
