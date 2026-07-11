import type {
  ClaimShoppingTripDisplayRequest,
  CompleteShoppingTripPersistenceRequest,
  ShoppingTripResident,
  StartShoppingTripPersistenceRequest,
} from '../contracts.js';
import { HTTPError } from '../http/errors.js';
import { hasOwn, isPlainRecord } from './shared.js';

const startTripKeys = new Set(['actor', 'mutationId', 'originatingPushDeviceId']);
const endTripKeys = new Set(['tripId', 'actor', 'mutationId', 'summaryRecipient']);
const claimDisplayKeys = new Set(['actor', 'pushDeviceId']);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type StartShoppingTripRequest = Omit<StartShoppingTripPersistenceRequest, 'mutationId'> & {
  mutationId?: string;
};

export type CompleteShoppingTripRequest = Omit<CompleteShoppingTripPersistenceRequest, 'mutationId'> & {
  mutationId?: string;
};

export function validateStartShoppingTripBody(input: unknown): StartShoppingTripRequest {
  const record = requireTripRecord(input, startTripKeys);

  return {
    startedBy: readResident(record.actor, 'actor'),
    ...(hasOwn(record, 'originatingPushDeviceId')
      ? { originatingPushDeviceId: readNonemptyString(record.originatingPushDeviceId, 'originatingPushDeviceId') }
      : {}),
    ...(hasOwn(record, 'mutationId') ? { mutationId: validateShoppingTripMutationId(record.mutationId) } : {}),
  };
}

export function validateClaimShoppingTripDisplayBody(
  tripId: string,
  input: unknown,
): ClaimShoppingTripDisplayRequest {
  const record = requireTripRecord(input, claimDisplayKeys);

  return {
    tripId: readShoppingTripId(tripId),
    resident: readResident(record.actor, 'actor'),
    pushDeviceId: readNonemptyString(record.pushDeviceId, 'pushDeviceId'),
  };
}

export function validateCompleteShoppingTripBody(input: unknown): CompleteShoppingTripRequest {
  const record = requireTripRecord(input, endTripKeys);
  const summaryRecipient = hasOwn(record, 'summaryRecipient')
    ? readNullableResident(record.summaryRecipient, 'summaryRecipient')
    : undefined;

  return {
    tripId: readShoppingTripId(record.tripId),
    endedBy: readResident(record.actor, 'actor'),
    ...(hasOwn(record, 'mutationId') ? { mutationId: validateShoppingTripMutationId(record.mutationId) } : {}),
    ...(summaryRecipient !== undefined ? { summaryRecipient } : {}),
  };
}

export function validateShoppingTripMutationId(value: unknown): string {
  if (typeof value !== 'string' || !uuidPattern.test(value.trim())) {
    throw invalidShoppingTrip('mutationId must be a UUID.');
  }

  return value.trim().toLowerCase();
}

function requireTripRecord(input: unknown, allowedKeys: Set<string>): Record<string, unknown> {
  if (!isPlainRecord(input)) {
    throw invalidShoppingTrip('Expected a JSON object shopping trip payload.');
  }

  const unsupportedKey = Object.keys(input).find((key) => !allowedKeys.has(key));

  if (unsupportedKey) {
    throw invalidShoppingTrip(`Unsupported shopping trip field: ${unsupportedKey}`);
  }

  return input;
}

function readShoppingTripId(value: unknown): string {
  if (typeof value !== 'string' || !uuidPattern.test(value.trim())) {
    throw invalidShoppingTrip('tripId must be a UUID.');
  }

  return value.trim().toLowerCase();
}

function readNonemptyString(value: unknown, fieldName: string): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw invalidShoppingTrip(`${fieldName} is required.`);
  }

  return value.trim();
}

function readResident(value: unknown, fieldName: string): ShoppingTripResident {
  if (value === 'Josh' || value === 'Mallory') {
    return value;
  }

  throw invalidShoppingTrip(`${fieldName} must be Josh or Mallory.`);
}

function readNullableResident(value: unknown, fieldName: string): ShoppingTripResident | null {
  if (value === null) {
    return null;
  }

  return readResident(value, fieldName);
}

function invalidShoppingTrip(message: string): HTTPError {
  return new HTTPError(400, message, 'invalid_shopping_trip');
}
