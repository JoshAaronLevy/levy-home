import type { StartShoppingListReaddRequest } from '../contracts.js';
import { shoppingListReaddLimits } from '../services/shopping/shoppingListReaddContracts.js';
import { HTTPError } from '../http/errors.js';
import { hasOwn, isPlainRecord } from './shared.js';

const allowedStartKeys = new Set(['text', 'actor', 'mutationId']);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/**
 * The API owns the complete candidate snapshot and the matcher instructions.
 * Clients may submit only a natural-language request, one household actor,
 * and an idempotency ID.
 */
export function validateStartShoppingListReaddBody(input: unknown): StartShoppingListReaddRequest {
  if (!isPlainRecord(input)) {
    throw invalidShoppingListReadd('Expected a JSON object AI Shopping re-add payload.');
  }

  const unsupportedKey = Object.keys(input).find((key) => !allowedStartKeys.has(key));
  if (unsupportedKey) {
    throw invalidShoppingListReadd(`Unsupported AI Shopping re-add field: ${unsupportedKey}`);
  }

  if (!hasOwn(input, 'text') || typeof input.text !== 'string') {
    throw invalidShoppingListReadd('text must be a nonempty string.');
  }
  const text = input.text.trim();
  if (!text || text.length > shoppingListReaddLimits.maxRequestTextLength) {
    throw invalidShoppingListReadd(`text must be between 1 and ${shoppingListReaddLimits.maxRequestTextLength} characters.`);
  }

  if (!hasOwn(input, 'actor') || (input.actor !== 'Josh' && input.actor !== 'Mallory')) {
    throw invalidShoppingListReadd('actor must be Josh or Mallory.');
  }

  if (!hasOwn(input, 'mutationId') || typeof input.mutationId !== 'string' || !uuidPattern.test(input.mutationId.trim())) {
    throw invalidShoppingListReadd('mutationId must be a UUID.');
  }

  return { text, actor: input.actor, mutationId: input.mutationId.trim().toLowerCase() };
}

export function readShoppingListReaddId(value: unknown): string {
  if (typeof value !== 'string' || !uuidPattern.test(value.trim())) {
    throw invalidShoppingListReadd('runId must be a UUID.');
  }
  return value.trim().toLowerCase();
}

function invalidShoppingListReadd(message: string): HTTPError {
  return new HTTPError(400, message, 'invalid_shopping_list_readd');
}
