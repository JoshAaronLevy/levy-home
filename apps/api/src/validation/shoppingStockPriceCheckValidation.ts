import type { StartShoppingStockPriceCheckRequest } from '../contracts.js';
import { HTTPError } from '../http/errors.js';
import { hasOwn, isPlainRecord } from './shared.js';

const allowedStartKeys = new Set(['actor', 'mutationId']);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/**
 * The server owns the shopping snapshot, stores, prompt, and website scope.
 * This intentionally accepts no item details, retailer URLs, or AI input.
 */
export function validateStartShoppingStockPriceCheckBody(input: unknown): StartShoppingStockPriceCheckRequest {
  if (!isPlainRecord(input)) {
    throw invalidStockPriceCheck('Expected a JSON object stock and price check payload.');
  }

  const unsupportedKey = Object.keys(input).find((key) => !allowedStartKeys.has(key));
  if (unsupportedKey) {
    throw invalidStockPriceCheck(`Unsupported stock and price check field: ${unsupportedKey}`);
  }

  if (!hasOwn(input, 'actor') || (input.actor !== 'Josh' && input.actor !== 'Mallory')) {
    throw invalidStockPriceCheck('actor must be Josh or Mallory.');
  }

  if (!hasOwn(input, 'mutationId') || typeof input.mutationId !== 'string' || !uuidPattern.test(input.mutationId.trim())) {
    throw invalidStockPriceCheck('mutationId must be a UUID.');
  }

  return {
    actor: input.actor,
    mutationId: input.mutationId.trim().toLowerCase(),
  };
}

export function readShoppingStockPriceCheckId(value: unknown): string {
  if (typeof value !== 'string' || !uuidPattern.test(value.trim())) {
    throw invalidStockPriceCheck('jobId must be a UUID.');
  }

  return value.trim().toLowerCase();
}

function invalidStockPriceCheck(message: string): HTTPError {
  return new HTTPError(400, message, 'invalid_shopping_stock_price_check');
}
