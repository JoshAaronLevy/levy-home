import type {
  ShoppingLiveActivityRegistrationRequest,
  ShoppingLiveActivityTokenType,
  ShoppingTripResident,
} from '../contracts.js';
import { HTTPError } from '../http/errors.js';
import { hasOwn, isPlainRecord } from './shared.js';

const registrationFields = new Set([
  'pushDeviceId',
  'resident',
  'environment',
  'tokenType',
  'token',
  'tripId',
]);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function validateShoppingLiveActivityRegistrationBody(
  input: unknown,
): ShoppingLiveActivityRegistrationRequest {
  if (!isPlainRecord(input)) {
    throw invalidLiveActivityRegistration('Expected a JSON object ActivityKit registration payload.');
  }

  const unsupported = Object.keys(input).find((key) => !registrationFields.has(key));

  if (unsupported) {
    throw invalidLiveActivityRegistration(`Unsupported ActivityKit registration field: ${unsupported}`);
  }

  const tokenType = readTokenType(input.tokenType);
  const tripId = hasOwn(input, 'tripId') ? readUUID(input.tripId, 'tripId') : undefined;

  if (tokenType === 'push_to_start' && tripId !== undefined) {
    throw invalidLiveActivityRegistration('push_to_start registrations must not include tripId.');
  }

  if (tokenType === 'activity_update' && tripId === undefined) {
    throw invalidLiveActivityRegistration('activity_update registrations require tripId.');
  }

  return {
    pushDeviceId: readNonemptyString(input.pushDeviceId, 'pushDeviceId'),
    resident: readResident(input.resident),
    environment: readEnvironment(input.environment),
    tokenType,
    token: readToken(input.token),
    ...(tripId ? { tripId } : {}),
  };
}

function readToken(value: unknown): string {
  const token = readNonemptyString(value, 'token');

  if (!/^[0-9a-f]+$/i.test(token) || token.length < 32 || token.length % 2 !== 0) {
    throw invalidLiveActivityRegistration('token must be a hexadecimal ActivityKit token.');
  }

  return token.toLowerCase();
}

function readNonemptyString(value: unknown, fieldName: string): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw invalidLiveActivityRegistration(`${fieldName} is required and must be a non-empty string.`);
  }

  return value.trim();
}

function readUUID(value: unknown, fieldName: string): string {
  const uuid = readNonemptyString(value, fieldName);

  if (!uuidPattern.test(uuid)) {
    throw invalidLiveActivityRegistration(`${fieldName} must be a UUID.`);
  }

  return uuid.toLowerCase();
}

function readResident(value: unknown): ShoppingTripResident {
  if (value === 'Josh' || value === 'Mallory') {
    return value;
  }

  throw invalidLiveActivityRegistration('resident must be Josh or Mallory.');
}

function readEnvironment(value: unknown): 'sandbox' | 'production' {
  if (value === 'sandbox' || value === 'production') {
    return value;
  }

  throw invalidLiveActivityRegistration('environment must be sandbox or production.');
}

function readTokenType(value: unknown): ShoppingLiveActivityTokenType {
  if (value === 'push_to_start' || value === 'activity_update') {
    return value;
  }

  throw invalidLiveActivityRegistration('tokenType must be push_to_start or activity_update.');
}

function invalidLiveActivityRegistration(message: string): HTTPError {
  return new HTTPError(400, message, 'invalid_shopping_live_activity_registration');
}
