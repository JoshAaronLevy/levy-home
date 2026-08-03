import { isPlainRecord } from '../../validation/shared.js';

import {
  ShoppingListReaddContractValidationError,
  shoppingListReaddLimits,
  validateShoppingListReaddMatchPlan,
  type ShoppingListReaddCandidateSnapshot,
  type ShoppingListReaddMatchOperation,
  type ShoppingListReaddMatchPlan,
} from './shoppingListReaddContracts.js';

const ignoredMatchTokens = new Set([
  'a', 'an', 'the', 'add', 'buy', 'get', 'need', 'please', 'put', 'some', 'of', 'for', 'with', 'to',
]);

const writtenQuantities = new Map<string, number>([
  ['one', 1], ['two', 2], ['three', 3], ['four', 4], ['five', 5], ['six', 6], ['seven', 7], ['eight', 8], ['nine', 9],
  ['ten', 10], ['eleven', 11], ['twelve', 12], ['thirteen', 13], ['fourteen', 14], ['fifteen', 15], ['sixteen', 16],
  ['seventeen', 17], ['eighteen', 18], ['nineteen', 19], ['twenty', 20], ['thirty', 30], ['forty', 40], ['fifty', 50],
  ['sixty', 60], ['seventy', 70], ['eighty', 80], ['ninety', 90], ['zero', 0],
]);

const writtenTens = new Set(['twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety']);

export type ShoppingListReaddMatchContext = {
  phrases: ShoppingListReaddRequestedPhrase[];
  candidates: ShoppingListReaddCandidateProfile[];
  duplicateNormalizedNames: ReadonlyMap<string, readonly number[]>;
};

export type ShoppingListReaddRequestedPhrase = {
  requestIndex: number;
  text: string;
  normalizedText: string;
  matchingText: string;
  matchingTokens: string[];
  quantity: ShoppingListReaddPhraseQuantity;
};

export type ShoppingListReaddPhraseQuantity =
  | { state: 'absent' }
  | { state: 'explicit'; value: number }
  | { state: 'invalid'; code: 'zero' | 'negative' | 'decimal' | 'oversized' | 'ambiguous' };

export type ShoppingListReaddCandidateProfile = {
  item: ShoppingListReaddCandidateSnapshot;
  normalizedName: string;
  normalizedNameVariants: string[];
  aliases: string[];
  aliasTokens: string[];
};

/**
 * Builds deterministic, API-owned matching context before any Codex turn.
 * Aliases originate only from the approved candidate name, brand, and notes.
 */
export function buildShoppingListReaddMatchContext(
  requestText: string,
  candidateSnapshot: readonly ShoppingListReaddCandidateSnapshot[],
): ShoppingListReaddMatchContext {
  if (candidateSnapshot.length > shoppingListReaddLimits.maxCandidateItems) {
    throw new ShoppingListReaddContractValidationError('Candidate snapshot exceeds the allowed item count.');
  }

  const candidates = candidateSnapshot.map(candidateProfile);
  const duplicateNormalizedNames = duplicateCandidateNames(candidates);
  const phrases = parseShoppingListReaddRequestedPhrases(requestText, candidates);
  return { phrases, candidates, duplicateNormalizedNames };
}

/** Splits a bounded natural-language re-add request into ordered item phrases. */
export function parseShoppingListReaddRequestedPhrases(
  requestText: string,
  candidates: readonly ShoppingListReaddCandidateProfile[] = [],
): ShoppingListReaddRequestedPhrase[] {
  const request = requiredRequestText(requestText);
  const withoutIntent = request.replace(/^(?:please\s+)?(?:add|buy|get|need|put)\s+/i, '').trim();
  if (!withoutIntent) {
    throw new ShoppingListReaddContractValidationError('Request must include at least one item phrase.');
  }

  const normalizedWholeRequest = normalizeShoppingListReaddText(withoutIntent);
  const rawPhrases = candidates.some((candidate) => candidate.normalizedName === normalizedWholeRequest)
    ? [withoutIntent]
    : withoutIntent.split(/\s*(?:,|;|\+|\band\b|\bplus\b)\s*/i).filter(Boolean);

  if (rawPhrases.length < 1 || rawPhrases.length > shoppingListReaddLimits.maxRequestedPhrases) {
    throw new ShoppingListReaddContractValidationError('Request has an unsupported number of item phrases.');
  }

  return rawPhrases.map((rawPhrase, requestIndex) => phraseFromText(rawPhrase, requestIndex));
}

/** Normalizes case, punctuation, accents, and whitespace without losing words. */
export function normalizeShoppingListReaddText(value: string): string {
  return value
    .normalize('NFKD')
    .replace(/\p{Diacritic}/gu, '')
    .toLocaleLowerCase('en-US')
    .replace(/&/g, ' and ')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

/** Applies the Stage 4 server-side plausibility and quantity safeguards. */
export function validateShoppingListReaddMatchPlanForRequest(
  input: unknown,
  context: ShoppingListReaddMatchContext,
): ShoppingListReaddMatchPlan {
  const deduplicated = normalizeDuplicateTargetOperations(input, context.phrases);
  const candidates = context.candidates.map(({ item }) => item);
  const plan = validateShoppingListReaddMatchPlan(deduplicated, candidates, context.phrases.length);
  const coveredIndexes = new Set<number>();

  const operations = plan.operations.map((operation) => {
    const phrase = requiredPhrase(context.phrases, operation.requestIndex);
    validateReturnedPhrase(operation.requestedText, phrase);
    validateOperationQuantity(operation, phrase);
    const candidate = requiredCandidate(context.candidates, operation.itemId);
    const matchKind = plausibleMatchKind(phrase, candidate, context);
    if (!matchKind) {
      throw new ShoppingListReaddContractValidationError('Matcher selected an implausible candidate.');
    }
    coveredIndexes.add(operation.requestIndex);
    return { ...operation, matchKind };
  });

  const unmatched = plan.unmatched.map((entry) => {
    const phrase = requiredPhrase(context.phrases, entry.requestIndex);
    validateReturnedPhrase(entry.requestedText, phrase);
    coveredIndexes.add(entry.requestIndex);
    return entry;
  });

  if (coveredIndexes.size !== context.phrases.length) {
    throw new ShoppingListReaddContractValidationError('Matcher must resolve every requested phrase once.');
  }

  return { operations, unmatched };
}

/** A compact, safe model representation of the deterministic matching context. */
export function shoppingListReaddPromptContext(context: ShoppingListReaddMatchContext): {
  phrases: Array<{
    requestIndex: number;
    text: string;
    normalizedText: string;
    explicitQuantity?: number;
    quantityState: string;
  }>;
  items: Array<{
    id: number;
    version: number;
    name: string;
    brand?: string;
    notes?: string;
    purchased: boolean;
    quantity: number;
    normalizedName: string;
    aliases: string[];
  }>;
  duplicateNormalizedNames: Array<{ normalizedName: string; itemIds: number[] }>;
} {
  return {
    phrases: context.phrases.map((phrase) => ({
      requestIndex: phrase.requestIndex,
      text: phrase.text,
      normalizedText: phrase.normalizedText,
      ...(phrase.quantity.state === 'explicit' ? { explicitQuantity: phrase.quantity.value } : {}),
      quantityState: phrase.quantity.state,
    })),
    items: context.candidates.map((candidate) => ({
      id: candidate.item.itemId,
      version: candidate.item.itemVersion,
      name: candidate.item.name,
      ...(candidate.item.brand ? { brand: candidate.item.brand } : {}),
      ...(candidate.item.notes ? { notes: candidate.item.notes } : {}),
      purchased: candidate.item.purchased,
      quantity: candidate.item.quantity,
      normalizedName: candidate.normalizedName,
      aliases: candidate.aliases,
    })),
    duplicateNormalizedNames: [...context.duplicateNormalizedNames.entries()].map(([normalizedName, itemIds]) => ({
      normalizedName,
      itemIds: [...itemIds],
    })),
  };
}

function candidateProfile(item: ShoppingListReaddCandidateSnapshot): ShoppingListReaddCandidateProfile {
  const normalizedName = normalizeShoppingListReaddText(item.name);
  if (!normalizedName) {
    throw new ShoppingListReaddContractValidationError('Candidate name must be nonempty.');
  }

  const normalizedBrand = item.brand ? normalizeShoppingListReaddText(item.brand) : '';
  const normalizedNotes = item.notes ? normalizeShoppingListReaddText(item.notes) : '';
  const aliases = uniqueStrings([
    normalizedName,
    normalizedBrand ? `${normalizedBrand} ${normalizedName}` : '',
    normalizedBrand ? `${normalizedName} ${normalizedBrand}` : '',
    normalizedNotes ? `${normalizedName} ${normalizedNotes}` : '',
  ]);

  return {
    item,
    normalizedName,
    normalizedNameVariants: phraseVariants(normalizedName),
    aliases,
    aliasTokens: uniqueStrings(aliases.flatMap(matchTokens)),
  };
}

function duplicateCandidateNames(candidates: readonly ShoppingListReaddCandidateProfile[]): ReadonlyMap<string, readonly number[]> {
  const idsByName = new Map<string, number[]>();
  for (const candidate of candidates) {
    const ids = idsByName.get(candidate.normalizedName) ?? [];
    ids.push(candidate.item.itemId);
    idsByName.set(candidate.normalizedName, ids);
  }
  return new Map([...idsByName.entries()].filter(([, ids]) => ids.length > 1));
}

function phraseFromText(rawPhrase: string, requestIndex: number): ShoppingListReaddRequestedPhrase {
  const text = rawPhrase.trim();
  const normalizedText = normalizeShoppingListReaddText(text);
  if (!normalizedText || text.length > shoppingListReaddLimits.maxRequestTextLength) {
    throw new ShoppingListReaddContractValidationError('Requested phrase must be nonempty and bounded.');
  }

  const quantity = parsePhraseQuantity(text);
  const matchingText = quantity.state === 'explicit'
    ? removeLeadingQuantity(normalizedText)
    : normalizedText;
  return {
    requestIndex,
    text,
    normalizedText,
    matchingText,
    matchingTokens: matchTokens(matchingText),
    quantity,
  };
}

function parsePhraseQuantity(text: string): ShoppingListReaddPhraseQuantity {
  const trimmed = text.trim().toLocaleLowerCase('en-US');
  if (/^(?:minus|negative)\s+\d+\b|^-\s*\d+\b/.test(trimmed)) return { state: 'invalid', code: 'negative' };
  if (/^\d+\.\d+\b/.test(trimmed)) return { state: 'invalid', code: 'decimal' };

  const numeric = /^(\d+)\b/.exec(trimmed);
  if (numeric) return numericQuantity(Number(numeric[1]));

  const normalized = normalizeShoppingListReaddText(trimmed);
  const words = normalized.split(' ');
  if (words[0] === 'half' || words[0] === 'couple') return { state: 'invalid', code: 'ambiguous' };
  const first = writtenQuantities.get(words[0] ?? '');
  if (first === undefined) {
    if (/^(?:minus|negative)\b/.test(normalized)) return { state: 'invalid', code: 'negative' };
    return { state: 'absent' };
  }
  if (first === 0) return { state: 'invalid', code: 'zero' };

  const second = writtenQuantities.get(words[1] ?? '');
  if (writtenTens.has(words[0] ?? '') && second !== undefined && second > 0 && second < 10) {
    return numericQuantity(first + second);
  }
  if (words[1] === 'point') return { state: 'invalid', code: 'decimal' };
  if (words[1] === 'hundred' || words[1] === 'thousand') return { state: 'invalid', code: 'oversized' };
  if (words[1] === 'or' || words[1] === 'and' || words[1] === 'dozen' || words[1] === 'half') {
    return { state: 'invalid', code: 'ambiguous' };
  }
  return numericQuantity(first);
}

function numericQuantity(value: number): ShoppingListReaddPhraseQuantity {
  if (value === 0) return { state: 'invalid', code: 'zero' };
  if (value < 0) return { state: 'invalid', code: 'negative' };
  if (value > shoppingListReaddLimits.maxQuantity) return { state: 'invalid', code: 'oversized' };
  return { state: 'explicit', value };
}

function removeLeadingQuantity(normalizedText: string): string {
  const words = normalizedText.split(' ');
  const first = words[0] ?? '';
  if (/^\d+$/.test(first)) return words.slice(1).join(' ');
  if (writtenTens.has(first) && writtenQuantities.has(words[1] ?? '')) return words.slice(2).join(' ');
  return words.slice(1).join(' ');
}

function plausibleMatchKind(
  phrase: ShoppingListReaddRequestedPhrase,
  candidate: ShoppingListReaddCandidateProfile,
  context: ShoppingListReaddMatchContext,
): ShoppingListReaddMatchOperation['matchKind'] | null {
  if (phrase.quantity.state === 'invalid' || phrase.matchingTokens.length === 0) return null;

  const exactCandidates = context.candidates.filter((entry) => entry.normalizedName === phrase.matchingText);
  if (exactCandidates.length > 0) {
    return exactCandidates.length === 1 && exactCandidates[0]?.item.itemId === candidate.item.itemId ? 'exact' : null;
  }

  const normalizedCandidates = context.candidates.filter((entry) => entry.normalizedNameVariants.includes(phrase.matchingText));
  if (normalizedCandidates.length > 0) {
    return normalizedCandidates.length === 1 && normalizedCandidates[0]?.item.itemId === candidate.item.itemId ? 'normalized' : null;
  }

  const overlap = phrase.matchingTokens.filter((token) => candidate.aliasTokens.includes(token));
  if (overlap.length === 0) return null;

  // A shared meaningful token is intentionally permissive for the first MVP:
  // it allows "coffee" -> "Iced Coffee" but cannot turn "bananas" into milk.
  return 'semantic';
}

function phraseVariants(normalizedText: string): string[] {
  const tokens = normalizedText.split(' ');
  return uniqueStrings([
    normalizedText,
    tokens.map(singularToken).join(' '),
  ]);
}

function singularToken(token: string): string {
  if (token.length <= 2) return token;
  if (token.endsWith('ies') && token.length > 3) return `${token.slice(0, -3)}y`;
  if (token.endsWith('sses') || token.endsWith('shes') || token.endsWith('ches') || token.endsWith('xes') || token.endsWith('zes')) return token.slice(0, -2);
  if (token.endsWith('s') && !token.endsWith('ss')) return token.slice(0, -1);
  return token;
}

function matchTokens(normalizedText: string): string[] {
  return uniqueStrings(normalizedText.split(' ').map(singularToken).filter((token) => token && !ignoredMatchTokens.has(token)));
}

function normalizeDuplicateTargetOperations(input: unknown, phrases: readonly ShoppingListReaddRequestedPhrase[]): unknown {
  if (!isPlainRecord(input) || !Array.isArray(input.operations) || !Array.isArray(input.unmatched)) return input;

  const selectedByItemId = new Map<number, Record<string, unknown>>();
  const duplicateIndexes = new Set<number>();
  for (const rawOperation of input.operations) {
    if (!isPlainRecord(rawOperation) || typeof rawOperation.itemId !== 'number' || !Number.isInteger(rawOperation.itemId)) continue;
    const earlier = selectedByItemId.get(rawOperation.itemId);
    if (!earlier) {
      selectedByItemId.set(rawOperation.itemId, rawOperation);
      continue;
    }

    const earlierQuantity = earlier.quantity;
    const laterQuantity = rawOperation.quantity;
    if (earlierQuantity === undefined && laterQuantity !== undefined) {
      selectedByItemId.set(rawOperation.itemId, rawOperation);
      if (typeof earlier.requestIndex === 'number') duplicateIndexes.add(earlier.requestIndex);
    } else if (typeof rawOperation.requestIndex === 'number') {
      duplicateIndexes.add(rawOperation.requestIndex);
    }
  }

  if (duplicateIndexes.size === 0) return input;
  const operations = [...selectedByItemId.values()];
  const unmatched = input.unmatched.filter((entry) => !isPlainRecord(entry) || !duplicateIndexes.has(entry.requestIndex as number));
  for (const requestIndex of duplicateIndexes) {
    const phrase = phrases[requestIndex];
    if (phrase) unmatched.push({ requestIndex, requestedText: phrase.text });
  }
  return { operations, unmatched };
}

function requiredRequestText(value: string): string {
  const normalized = typeof value === 'string' ? value.trim() : '';
  if (!normalized || normalized.length > shoppingListReaddLimits.maxRequestTextLength) {
    throw new ShoppingListReaddContractValidationError('Request text must be nonempty and bounded.');
  }
  return normalized;
}

function requiredPhrase(
  phrases: readonly ShoppingListReaddRequestedPhrase[],
  requestIndex: number,
): ShoppingListReaddRequestedPhrase {
  const phrase = phrases[requestIndex];
  if (!phrase) throw new ShoppingListReaddContractValidationError('Unknown requested phrase.');
  return phrase;
}

function requiredCandidate(
  candidates: readonly ShoppingListReaddCandidateProfile[],
  itemId: number,
): ShoppingListReaddCandidateProfile {
  const candidate = candidates.find((entry) => entry.item.itemId === itemId);
  if (!candidate) throw new ShoppingListReaddContractValidationError('Unknown candidate item.');
  return candidate;
}

function validateReturnedPhrase(returnedText: string, phrase: ShoppingListReaddRequestedPhrase): void {
  if (returnedText !== phrase.text) {
    throw new ShoppingListReaddContractValidationError('Matcher returned altered requested text.');
  }
}

function validateOperationQuantity(operation: ShoppingListReaddMatchOperation, phrase: ShoppingListReaddRequestedPhrase): void {
  if (phrase.quantity.state === 'invalid') {
    throw new ShoppingListReaddContractValidationError('Matcher selected a phrase with an invalid quantity instruction.');
  }
  if (phrase.quantity.state === 'absent' && operation.quantity !== undefined) {
    throw new ShoppingListReaddContractValidationError('Matcher inferred a quantity that was not requested.');
  }
  if (phrase.quantity.state === 'explicit' && operation.quantity !== phrase.quantity.value) {
    throw new ShoppingListReaddContractValidationError('Matcher changed an explicitly requested quantity.');
  }
}

function uniqueStrings(values: readonly string[]): string[] {
  return [...new Set(values.filter(Boolean))];
}
