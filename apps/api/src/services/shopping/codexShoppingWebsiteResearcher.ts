import type { CodexOptions, Thread, ThreadOptions } from '@openai/codex-sdk';

import type { ShoppingStockPriceCheckItemSnapshot } from '../../contracts.js';
import {
  RETAILER_WEBSITE_SCOPE,
  retailerWebsiteStoreForKey,
} from './retailerWebsiteScope.js';
import {
  unavailableRetailerWebsiteResearchResult,
  validateRetailerWebsiteResearchResult,
  type RetailerWebsiteResearchRequest,
  type RetailerWebsiteResearchResult,
  type RetailerWebsiteResearcher,
} from './retailerWebsiteResearcher.js';

const MAX_CODEX_STRUCTURED_OUTPUT_BYTES = 16 * 1024;

/**
 * This configuration records the strongest controls currently exposed by the
 * local SDK/CLI: a read-only, approval-free thread, disabled web search, and
 * a four-host network proxy. The SDK does not expose a browser-only tool or a
 * same-host direct-API prohibition, so this is deliberately not executable.
 */
export const CODEX_SHOPPING_WEBSITE_RESEARCH_OPTIONS: CodexOptions = {
  config: {
    features: {
      network_proxy: {
        enabled: true,
        allow_local_binding: false,
        allow_upstream_proxy: false,
        domains: {
          'target.com': 'allow',
          'www.target.com': 'allow',
          'kingsoopers.com': 'allow',
          'www.kingsoopers.com': 'allow',
        },
      },
    },
  },
  // Do not inherit application secrets or deployment credentials when a
  // verified runtime is eventually wired. The SDK injects its own supported
  // authentication variables; this service does not inspect or log them.
  env: {
    PATH: process.env.PATH ?? '/usr/local/bin:/usr/bin:/bin',
  },
};

export const CODEX_SHOPPING_WEBSITE_THREAD_OPTIONS: ThreadOptions = {
  sandboxMode: 'read-only',
  approvalPolicy: 'never',
  networkAccessEnabled: true,
  webSearchMode: 'disabled',
  webSearchEnabled: false,
  skipGitRepoCheck: true,
  workingDirectory: '/tmp',
};

export const CODEX_SHOPPING_WEBSITE_RESEARCH_OUTPUT_SCHEMA = {
  type: 'object',
  properties: {
    outcome: {
      type: 'string',
      enum: ['matched', 'no_match', 'ambiguous', 'website_error'],
    },
    navigation: {
      type: 'object',
      properties: {
        url: { type: 'string', maxLength: 1024 },
        method: { type: 'string', enum: ['GET', 'HEAD', 'OPTIONS'] },
      },
      required: ['url', 'method'],
      additionalProperties: false,
    },
    renderedStoreText: { type: 'string', maxLength: 300 },
    renderedAvailabilityText: { type: 'string', maxLength: 160 },
    product: {
      type: 'object',
      properties: {
        productId: { type: 'string', maxLength: 128 },
        upc: { type: 'string', maxLength: 32 },
        brand: { type: 'string', maxLength: 120 },
        name: { type: 'string', maxLength: 160 },
      },
      additionalProperties: false,
    },
    aisle: {
      type: 'object',
      properties: {
        display: { type: 'string', maxLength: 160 },
        description: { type: 'string', maxLength: 160 },
        number: { type: 'string', maxLength: 32 },
        shelfNumber: { type: 'string', maxLength: 32 },
      },
      additionalProperties: false,
    },
    price: {
      type: 'object',
      properties: {
        regular: { type: 'number', minimum: 0 },
        promo: { type: 'number', minimum: 0 },
      },
      additionalProperties: false,
    },
  },
  required: ['outcome'],
  additionalProperties: false,
} as const;

export const CODEX_SHOPPING_WEBSITE_RESEARCH_READINESS = Object.freeze({
  enabled: false,
  code: 'site_scope_unavailable',
  reason: 'The local Codex TypeScript SDK/CLI has no browser-only runtime policy that can reject same-host product APIs.',
} as const);

/**
 * Stage 4’s concrete service intentionally fails closed. Do not change
 * `enabled` from false merely because authentication, the SDK, or the four
 * host allowlist is available: a separate, server-compatible browser-only
 * control must be proven first.
 */
export class CodexShoppingWebsiteResearcher implements RetailerWebsiteResearcher {
  readonly scope = RETAILER_WEBSITE_SCOPE;

  async research(request: RetailerWebsiteResearchRequest): Promise<RetailerWebsiteResearchResult> {
    return unavailableRetailerWebsiteResearchResult(request, CODEX_SHOPPING_WEBSITE_RESEARCH_READINESS.code);
  }
}

/**
 * Constructs the minimal prompt to be used only after the readiness gate is
 * replaced by a verified browser-only runtime. It contains no notes, image,
 * store listings, app paths, credentials, customer data, or writable task.
 */
export function buildCodexShoppingWebsiteResearchPrompt(
  request: RetailerWebsiteResearchRequest,
): string {
  const store = retailerWebsiteStoreForKey(request.storeKey);
  const item = promptItem(request.item);

  return [
    'Research one shopping item using only a normal rendered browser page on the fixed retailer website.',
    `Retailer host: ${store.source}.`,
    `Required store address: ${store.address}.`,
    'First set or confirm that exact address in the visible store-selection UI.',
    'Use only the retailer’s visible search and product pages. Do not use web search, curl, fetch, scripts, direct HTTP, JSON, GraphQL, an API, another site, login, cart, pickup, or checkout.',
    'Return only JSON that matches the supplied schema. Report only facts visibly shown by the rendered page.',
    'If the store cannot be confirmed, report no inferred product/price/location facts. If a match is uncertain, use no_match or ambiguous. If the page is unavailable, use website_error.',
    `Item: ${JSON.stringify(item)}.`,
  ].join('\n');
}

/**
 * Converts the final structured SDK response to the Stage 3 contract without
 * exposing raw Codex text. Malformed output is a safe website error; an
 * endpoint-shaped or disallowed navigation remains a domain-scope failure via
 * the Stage 3 validator.
 */
export function parseCodexShoppingWebsiteResearchResponse(
  request: RetailerWebsiteResearchRequest,
  response: string,
): RetailerWebsiteResearchResult {
  if (Buffer.byteLength(response, 'utf8') > MAX_CODEX_STRUCTURED_OUTPUT_BYTES) {
    return unavailableRetailerWebsiteResearchResult(request, 'invalid_agent_result');
  }

  try {
    return validateRetailerWebsiteResearchResult(request, JSON.parse(response) as unknown);
  } catch {
    return unavailableRetailerWebsiteResearchResult(request, 'invalid_agent_result');
  }
}

/**
 * Isolated execution seam for a future verified browser runtime. The current
 * `CodexShoppingWebsiteResearcher` never reaches this function because the
 * documented local SDK lacks the mandatory browser-only policy.
 */
export async function runCodexShoppingWebsiteResearchTurn(
  thread: Pick<Thread, 'run'>,
  request: RetailerWebsiteResearchRequest,
  timeoutMs: number = RETAILER_WEBSITE_SCOPE.policy.jobTimeoutMs,
): Promise<RetailerWebsiteResearchResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const result = await thread.run(buildCodexShoppingWebsiteResearchPrompt(request), {
      outputSchema: CODEX_SHOPPING_WEBSITE_RESEARCH_OUTPUT_SCHEMA,
      signal: controller.signal,
    });
    return parseCodexShoppingWebsiteResearchResponse(request, result.finalResponse);
  } catch {
    return unavailableRetailerWebsiteResearchResult(request, 'website_unavailable');
  } finally {
    clearTimeout(timer);
  }
}

function promptItem(item: ShoppingStockPriceCheckItemSnapshot): {
  itemId: number;
  name: string;
  brand?: string;
  quantity: number;
} {
  return {
    itemId: item.itemId,
    name: boundedPromptText(item.name, 160),
    ...(item.brand ? { brand: boundedPromptText(item.brand, 120) } : {}),
    quantity: item.quantity,
  };
}

function boundedPromptText(value: string, maximumLength: number): string {
  return value.trim().slice(0, maximumLength);
}
