import { Codex, type CodexOptions, type Thread, type ThreadOptions } from '@openai/codex-sdk';

import {
  shoppingListReaddLimits,
  shoppingListReaddMatchingPolicy,
  validateShoppingListReaddMatchPlan,
  type ShoppingListReaddCandidateSnapshot,
  type ShoppingListReaddMatchPlan,
} from './shoppingListReaddContracts.js';

const MAX_CODEX_STRUCTURED_OUTPUT_BYTES = 16 * 1024;
export const CODEX_SHOPPING_LIST_READD_MATCHER_API_KEY_ENV = 'CODEX_SHOPPING_LIST_API_KEY';
export const DEFAULT_CODEX_SHOPPING_LIST_READD_TIMEOUT_MS = 15_000;

/**
 * The matcher has no repository or mutation dependency. It receives a bounded
 * API-owned snapshot and returns an untrusted operation plan for a later
 * service to validate and apply.
 */
export type ShoppingListReaddMatcher = {
  match: (
    requestText: string,
    candidateSnapshot: readonly ShoppingListReaddCandidateSnapshot[],
  ) => Promise<ShoppingListReaddMatchPlan>;
  getReadiness: () => ShoppingListReaddMatcherReadiness;
};

export type ShoppingListReaddMatcherReadiness = {
  runtime: ShoppingListReaddReadinessCheck;
  authentication: ShoppingListReaddReadinessCheck;
};

export type ShoppingListReaddReadinessCheck = {
  ready: boolean;
  code?: 'matcher_runtime_unavailable' | 'authentication_unavailable' | 'persistence_unavailable';
};

export type CodexShoppingListReaddClient = Pick<Codex, 'startThread'>;
export type CodexShoppingListReaddClientFactory = (options: CodexOptions) => CodexShoppingListReaddClient;

/**
 * The SDK receives only its own explicitly supplied API key and PATH. `env`
 * deliberately does not inherit the application process environment, so it
 * cannot expose database or deployment secrets to the Codex subprocess.
 */
export const CODEX_SHOPPING_LIST_READD_OPTIONS: Omit<CodexOptions, 'apiKey'> = {
  env: {
    PATH: process.env.PATH ?? '/usr/local/bin:/usr/bin:/bin',
  },
};

/** Offline-only, approval-free thread configuration for list matching. */
export const CODEX_SHOPPING_LIST_READD_THREAD_OPTIONS: ThreadOptions = {
  sandboxMode: 'read-only',
  approvalPolicy: 'never',
  networkAccessEnabled: false,
  webSearchMode: 'disabled',
  webSearchEnabled: false,
  skipGitRepoCheck: true,
  workingDirectory: '/tmp',
};

export const CODEX_SHOPPING_LIST_READD_OUTPUT_SCHEMA = {
  type: 'object',
  properties: {
    operations: {
      type: 'array',
      maxItems: shoppingListReaddLimits.maxRequestedPhrases,
      items: {
        type: 'object',
        properties: {
          requestIndex: { type: 'integer', minimum: 0, maximum: shoppingListReaddLimits.maxRequestedPhrases - 1 },
          requestedText: { type: 'string', minLength: 1, maxLength: shoppingListReaddLimits.maxRequestTextLength },
          itemId: { type: 'integer', minimum: 1 },
          quantity: {
            type: 'integer',
            minimum: shoppingListReaddLimits.minQuantity,
            maximum: shoppingListReaddLimits.maxQuantity,
          },
          matchKind: { type: 'string', enum: ['exact', 'normalized', 'semantic'] },
        },
        required: ['requestIndex', 'requestedText', 'itemId', 'matchKind'],
        additionalProperties: false,
      },
    },
    unmatched: {
      type: 'array',
      maxItems: shoppingListReaddLimits.maxRequestedPhrases,
      items: {
        type: 'object',
        properties: {
          requestIndex: { type: 'integer', minimum: 0, maximum: shoppingListReaddLimits.maxRequestedPhrases - 1 },
          requestedText: { type: 'string', minLength: 1, maxLength: shoppingListReaddLimits.maxRequestTextLength },
        },
        required: ['requestIndex', 'requestedText'],
        additionalProperties: false,
      },
    },
  },
  required: ['operations', 'unmatched'],
  additionalProperties: false,
} as const;

/** A deterministic fixture seam; it still applies the production validator. */
export class DeterministicShoppingListReaddMatcher implements ShoppingListReaddMatcher {
  constructor(private readonly plan: ShoppingListReaddMatchPlan) {}

  getReadiness(): ShoppingListReaddMatcherReadiness {
    return { runtime: { ready: true }, authentication: { ready: true } };
  }

  async match(
    _requestText: string,
    candidateSnapshot: readonly ShoppingListReaddCandidateSnapshot[],
  ): Promise<ShoppingListReaddMatchPlan> {
    return validateShoppingListReaddMatchPlan(
      this.plan,
      candidateSnapshot,
      shoppingListReaddLimits.maxRequestedPhrases,
    );
  }
}

/**
 * Server-side Codex adapter. The API key is intentionally injected by the
 * composition root in a later stage; this constructor never reads local auth
 * files, browser state, desktop credentials, or a general application key.
 */
export class CodexShoppingListReaddMatcher implements ShoppingListReaddMatcher {
  private readonly apiKey?: string;
  private readonly clientFactory: CodexShoppingListReaddClientFactory;
  private readonly runtimeAvailable: boolean;
  private readonly timeoutMs: number;

  constructor(options: {
    apiKey?: string;
    clientFactory?: CodexShoppingListReaddClientFactory;
    runtimeAvailable?: boolean;
    timeoutMs?: number;
  } = {}) {
    this.apiKey = nonemptyString(options.apiKey);
    this.clientFactory = options.clientFactory ?? ((codexOptions) => new Codex(codexOptions));
    this.runtimeAvailable = options.runtimeAvailable ?? true;
    this.timeoutMs = options.timeoutMs ?? DEFAULT_CODEX_SHOPPING_LIST_READD_TIMEOUT_MS;
  }

  getReadiness(): ShoppingListReaddMatcherReadiness {
    return {
      runtime: this.runtimeAvailable
        ? { ready: true }
        : { ready: false, code: 'matcher_runtime_unavailable' },
      authentication: this.apiKey
        ? { ready: true }
        : { ready: false, code: 'authentication_unavailable' },
    };
  }

  async match(
    requestText: string,
    candidateSnapshot: readonly ShoppingListReaddCandidateSnapshot[],
  ): Promise<ShoppingListReaddMatchPlan> {
    const readiness = this.getReadiness();
    if (!readiness.runtime.ready) {
      throw new ShoppingListReaddMatcherUnavailableError('matcher_runtime_unavailable');
    }
    if (!readiness.authentication.ready) {
      throw new ShoppingListReaddMatcherUnavailableError('authentication_unavailable');
    }

    const client = this.clientFactory({
      ...CODEX_SHOPPING_LIST_READD_OPTIONS,
      apiKey: this.apiKey,
    });
    const thread = client.startThread(CODEX_SHOPPING_LIST_READD_THREAD_OPTIONS);
    return runCodexShoppingListReaddTurn(thread, requestText, candidateSnapshot, this.timeoutMs);
  }
}

/**
 * Builds the entire model input from explicitly allowed snapshot fields. It
 * purposely has no product images, listings, retailer/store data, user or
 * device values, application paths, or database commands.
 */
export function buildCodexShoppingListReaddPrompt(
  requestText: string,
  candidateSnapshot: readonly ShoppingListReaddCandidateSnapshot[],
): string {
  const request = boundedRequiredText(requestText, 'request text');
  const items = promptCandidates(candidateSnapshot);

  return [
    'Match requested shopping phrases to existing supplied shopping items only.',
    'Return exactly one JSON object matching the provided schema and no prose.',
    'Use only the JSON below. Do not use tools or outside information.',
    'Never create an item, choose an ID outside items, select the same item twice, add fields, or infer a quantity when the phrase did not explicitly state one.',
    'For each phrase, choose one plausible closest item or put that phrase in unmatched. Do not choose an unrelated item.',
    ...shoppingListReaddMatchingPolicy.map((rule) => `Policy: ${rule}`),
    JSON.stringify({ request, items }),
  ].join('\n');
}

/** Parses only bounded schema-shaped model text. It has no mutation effect. */
export function parseCodexShoppingListReaddResponse(
  response: string,
  candidateSnapshot: readonly ShoppingListReaddCandidateSnapshot[],
): ShoppingListReaddMatchPlan {
  if (Buffer.byteLength(response, 'utf8') > MAX_CODEX_STRUCTURED_OUTPUT_BYTES) {
    throw new ShoppingListReaddMatcherInvalidResultError();
  }

  try {
    return validateShoppingListReaddMatchPlan(
      JSON.parse(response) as unknown,
      candidateSnapshot,
      shoppingListReaddLimits.maxRequestedPhrases,
    );
  } catch (error) {
    if (error instanceof ShoppingListReaddMatcherInvalidResultError) throw error;
    throw new ShoppingListReaddMatcherInvalidResultError();
  }
}

/** Isolated, timeout-bounded Codex turn; it does not write Shopping data. */
export async function runCodexShoppingListReaddTurn(
  thread: Pick<Thread, 'run'>,
  requestText: string,
  candidateSnapshot: readonly ShoppingListReaddCandidateSnapshot[],
  timeoutMs: number = DEFAULT_CODEX_SHOPPING_LIST_READD_TIMEOUT_MS,
): Promise<ShoppingListReaddMatchPlan> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const result = await thread.run(buildCodexShoppingListReaddPrompt(requestText, candidateSnapshot), {
      outputSchema: CODEX_SHOPPING_LIST_READD_OUTPUT_SCHEMA,
      signal: controller.signal,
    });
    return parseCodexShoppingListReaddResponse(result.finalResponse, candidateSnapshot);
  } catch (error) {
    if (error instanceof ShoppingListReaddMatcherInvalidResultError) throw error;
    throw new ShoppingListReaddMatcherUnavailableError('matcher_unavailable');
  } finally {
    clearTimeout(timer);
  }
}

function promptCandidates(
  candidateSnapshot: readonly ShoppingListReaddCandidateSnapshot[],
): Array<{
  id: number;
  version: number;
  name: string;
  brand?: string;
  notes?: string;
  purchased: boolean;
  quantity: number;
}> {
  if (candidateSnapshot.length > shoppingListReaddLimits.maxCandidateItems) {
    throw new ShoppingListReaddMatcherInvalidResultError();
  }

  return candidateSnapshot.map((item) => ({
    id: requiredPositiveInteger(item.itemId, 'item ID'),
    version: requiredPositiveInteger(item.itemVersion, 'item version'),
    name: boundedRequiredText(item.name, 'item name', shoppingListReaddLimits.maxCandidateNameLength),
    ...(item.brand ? { brand: boundedText(item.brand, shoppingListReaddLimits.maxCandidateBrandLength) } : {}),
    ...(item.notes ? { notes: boundedText(item.notes, shoppingListReaddLimits.maxCandidateNotesLength) } : {}),
    purchased: item.purchased,
    quantity: boundedQuantity(item.quantity),
  }));
}

function boundedRequiredText(value: string, field: string, maximumLength: number = shoppingListReaddLimits.maxRequestTextLength): string {
  const normalized = typeof value === 'string' ? value.trim() : '';
  if (!normalized || normalized.length > maximumLength) {
    throw new ShoppingListReaddMatcherInvalidResultError();
  }
  return normalized;
}

function boundedText(value: string, maximumLength: number): string {
  const normalized = value.trim();
  if (!normalized || normalized.length > maximumLength) {
    throw new ShoppingListReaddMatcherInvalidResultError();
  }
  return normalized;
}

function requiredPositiveInteger(value: number, _field: string): number {
  if (!Number.isInteger(value) || value < 1) {
    throw new ShoppingListReaddMatcherInvalidResultError();
  }
  return value;
}

function boundedQuantity(value: number): number {
  if (!Number.isInteger(value) || value < shoppingListReaddLimits.minQuantity || value > shoppingListReaddLimits.maxQuantity) {
    throw new ShoppingListReaddMatcherInvalidResultError();
  }
  return value;
}

function nonemptyString(value: string | undefined): string | undefined {
  const normalized = value?.trim();
  return normalized || undefined;
}

export class ShoppingListReaddMatcherUnavailableError extends Error {
  constructor(public readonly code: 'matcher_runtime_unavailable' | 'authentication_unavailable' | 'matcher_unavailable') {
    super(code);
    this.name = 'ShoppingListReaddMatcherUnavailableError';
  }
}

export class ShoppingListReaddMatcherInvalidResultError extends Error {
  constructor() {
    super('invalid_matcher_result');
    this.name = 'ShoppingListReaddMatcherInvalidResultError';
  }
}
