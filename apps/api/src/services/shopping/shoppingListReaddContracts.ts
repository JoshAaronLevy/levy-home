import type { ShoppingListReaddMatchKind } from '../../contracts.js';
import { isPlainRecord } from '../../validation/shared.js';

/**
 * Bounded data passed from the API-owned Shopping snapshot to the matcher.
 * It deliberately excludes images, store listings, categories, timestamps,
 * database metadata, user/device data, and every secret.
 */
export type ShoppingListReaddCandidateSnapshot = {
  itemId: number;
  itemVersion: number;
  name: string;
  brand?: string;
  notes?: string;
  purchased: boolean;
  quantity: number;
};

export type ShoppingListReaddMatchOperation = {
  requestIndex: number;
  requestedText: string;
  itemId: number;
  /** Omitted when the original phrase did not explicitly state a quantity. */
  quantity?: number;
  matchKind: ShoppingListReaddMatchKind;
};

export type ShoppingListReaddMatchPlan = {
  operations: ShoppingListReaddMatchOperation[];
  unmatched: Array<{
    requestIndex: number;
    requestedText: string;
  }>;
};

/** Conservative payload limits for the first offline, existing-items-only MVP. */
export const shoppingListReaddLimits = Object.freeze({
  maxRequestTextLength: 500,
  maxCandidateItems: 200,
  maxCandidateNameLength: 160,
  maxCandidateBrandLength: 120,
  maxCandidateNotesLength: 240,
  maxRequestedPhrases: 20,
  minQuantity: 1,
  maxQuantity: 99,
});

/**
 * Automatic matching policy:
 * 1. Prefer normalized equality, including punctuation and singular/plural
 *    variants. 2. Then use strong token overlap, with brand and notes as
 *    disambiguating cues. 3. Allow a plausible semantic relation only after a
 *    penalty for extra qualifiers (so "eggs" beats "egg cups"). 4. Choose
 *    one candidate or leave the phrase unmatched; never make an unrelated
 *    guess. The server validates every selected snapshot ID before writing.
 *
 * MVP non-goals: new-item creation, browsing or retailer lookup/API, image
 * matching, category selection, quantity increment/decrement, recurring
 * automation, free-form chat, and a confirmation picker.
 */
export const shoppingListReaddMatchingPolicy = Object.freeze([
  'Prefer normalized equality, including punctuation and singular/plural variants.',
  'Then use strong token overlap, with brand and notes as disambiguating cues.',
  'Allow plausible semantic similarity only after penalizing extra qualifiers.',
  'Choose one candidate or return unmatched; never make an unrelated guess.',
  'The server validates every selected snapshot ID before any Shopping mutation.',
]);

const matchKinds = new Set<ShoppingListReaddMatchKind>(['exact', 'normalized', 'semantic']);

/** The matcher boundary is untrusted input even when it is backed by Codex. */
export function validateShoppingListReaddMatchPlan(
  input: unknown,
  candidates: readonly ShoppingListReaddCandidateSnapshot[],
  requestedPhraseCount: number,
): ShoppingListReaddMatchPlan {
  if (!isPlainRecord(input) || !Array.isArray(input.operations) || !Array.isArray(input.unmatched)) {
    throw new ShoppingListReaddContractValidationError('Expected operations and unmatched arrays.');
  }

  if (requestedPhraseCount < 1 || requestedPhraseCount > shoppingListReaddLimits.maxRequestedPhrases) {
    throw new ShoppingListReaddContractValidationError('Requested phrase count is outside the allowed range.');
  }

  if (candidates.length > shoppingListReaddLimits.maxCandidateItems) {
    throw new ShoppingListReaddContractValidationError('Candidate snapshot exceeds the allowed item count.');
  }

  const candidateIds = new Set(candidates.map((candidate) => candidate.itemId));
  const seenRequestIndexes = new Set<number>();
  const seenItemIds = new Set<number>();
  const operations = input.operations.map((value) => {
    if (!isPlainRecord(value) || Object.keys(value).some((key) => !['requestIndex', 'requestedText', 'itemId', 'quantity', 'matchKind'].includes(key))) {
      throw new ShoppingListReaddContractValidationError('Operation contains unsupported fields.');
    }

    const requestIndex = readRequestIndex(value.requestIndex, requestedPhraseCount, seenRequestIndexes);
    const requestedText = readRequestedText(value.requestedText);
    const itemId = readCandidateId(value.itemId, candidateIds, seenItemIds);
    const quantity = value.quantity === undefined ? undefined : readQuantity(value.quantity);
    const matchKind = readMatchKind(value.matchKind);
    return { requestIndex, requestedText, itemId, ...(quantity === undefined ? {} : { quantity }), matchKind };
  });

  const unmatched = input.unmatched.map((value) => {
    if (!isPlainRecord(value) || Object.keys(value).some((key) => !['requestIndex', 'requestedText'].includes(key))) {
      throw new ShoppingListReaddContractValidationError('Unmatched phrase contains unsupported fields.');
    }

    return {
      requestIndex: readRequestIndex(value.requestIndex, requestedPhraseCount, seenRequestIndexes),
      requestedText: readRequestedText(value.requestedText),
    };
  });

  return { operations, unmatched };
}

function readRequestIndex(value: unknown, requestedPhraseCount: number, seen: Set<number>): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 0 || value >= requestedPhraseCount || seen.has(value)) {
    throw new ShoppingListReaddContractValidationError('requestIndex must identify one unique requested phrase.');
  }
  seen.add(value);
  return value;
}

function readRequestedText(value: unknown): string {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > shoppingListReaddLimits.maxRequestTextLength) {
    throw new ShoppingListReaddContractValidationError('requestedText must be nonempty and bounded.');
  }
  return value.trim();
}

function readCandidateId(value: unknown, candidateIds: Set<number>, seen: Set<number>): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || !candidateIds.has(value) || seen.has(value)) {
    throw new ShoppingListReaddContractValidationError('itemId must identify one unique candidate snapshot item.');
  }
  seen.add(value);
  return value;
}

function readQuantity(value: unknown): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < shoppingListReaddLimits.minQuantity || value > shoppingListReaddLimits.maxQuantity) {
    throw new ShoppingListReaddContractValidationError('quantity must be a bounded positive integer.');
  }
  return value;
}

function readMatchKind(value: unknown): ShoppingListReaddMatchKind {
  if (typeof value !== 'string' || !matchKinds.has(value as ShoppingListReaddMatchKind)) {
    throw new ShoppingListReaddContractValidationError('matchKind must be exact, normalized, or semantic.');
  }
  return value as ShoppingListReaddMatchKind;
}

export class ShoppingListReaddContractValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ShoppingListReaddContractValidationError';
  }
}
