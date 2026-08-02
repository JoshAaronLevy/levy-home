import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { Thread } from '@openai/codex-sdk';

import type { ShoppingStockPriceCheckItemSnapshot } from '../../src/contracts.js';
import {
  buildCodexShoppingWebsiteResearchPrompt,
  CODEX_SHOPPING_WEBSITE_RESEARCH_OPTIONS,
  CODEX_SHOPPING_WEBSITE_RESEARCH_OUTPUT_SCHEMA,
  CODEX_SHOPPING_WEBSITE_RESEARCH_READINESS,
  CODEX_SHOPPING_WEBSITE_THREAD_OPTIONS,
  CodexShoppingWebsiteResearcher,
  parseCodexShoppingWebsiteResearchResponse,
  runCodexShoppingWebsiteResearchTurn,
} from '../../src/services/shopping/codexShoppingWebsiteResearcher.js';
import type { RetailerWebsiteResearchRequest } from '../../src/services/shopping/retailerWebsiteResearcher.js';

const request: RetailerWebsiteResearchRequest = {
  item: {
    itemId: 42,
    itemVersion: 3,
    name: 'Fixture milk',
    brand: 'Fixture Farms',
    quantity: 2,
    notes: 'Do not include this private note in the prompt.',
    categoryId: 9,
    image: 'https://not-allowed.example/private-image.png',
    storeListings: [{ source: 'manual', product: { name: 'Do not include this listing' } }],
  },
  storeKey: 'target_highlands_ranch',
};

test('Codex Stage 4 configuration remains exact-host, read-only, approval-free, and web-search-disabled', () => {
  assert.deepEqual(CODEX_SHOPPING_WEBSITE_RESEARCH_OPTIONS.config, {
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
  });
  assert.deepEqual(CODEX_SHOPPING_WEBSITE_THREAD_OPTIONS, {
    sandboxMode: 'read-only',
    approvalPolicy: 'never',
    networkAccessEnabled: true,
    webSearchMode: 'disabled',
    webSearchEnabled: false,
    skipGitRepoCheck: true,
    workingDirectory: '/tmp',
  });
  assert.equal(CODEX_SHOPPING_WEBSITE_RESEARCH_READINESS.enabled, false);
  assert.equal(CODEX_SHOPPING_WEBSITE_RESEARCH_READINESS.code, 'site_scope_unavailable');
});

test('Codex prompt is bounded and excludes shopping notes, images, listings, app paths, and credentials', () => {
  const prompt = buildCodexShoppingWebsiteResearchPrompt(request);

  assert.match(prompt, /1365 Sgt Jon Stiles Dr, Highlands Ranch, CO/);
  assert.match(prompt, /Fixture milk/);
  assert.match(prompt, /Fixture Farms/);
  assert.match(prompt, /direct HTTP, JSON, GraphQL, an API/);
  assert.doesNotMatch(prompt, /private note|not-allowed\.example|manual|Do not include this listing/i);
  assert.doesNotMatch(prompt, /\/Users\/|DATABASE_URL|CODEX_API_KEY/i);
});

test('Codex response parser validates structured visible-page evidence and never returns raw text', () => {
  const response = JSON.stringify({
    outcome: 'matched',
    navigation: { url: 'https://www.target.com/p/fixture?session=redacted', method: 'GET' },
    renderedStoreText: 'Target 1365 Sgt Jon Stiles Dr Highlands Ranch CO',
    renderedAvailabilityText: 'In stock',
    product: { name: 'Fixture milk', upc: '000111222333' },
    price: { regular: 3.99 },
    aisle: { display: 'A12' },
  });

  const result = parseCodexShoppingWebsiteResearchResponse(request, response);

  assert.deepEqual(result, {
    store: {
      storeId: 1,
      storeName: 'Target',
      source: 'target.com',
      selectedStoreAddress: '1365 Sgt Jon Stiles Dr, Highlands Ranch, CO',
      pageURL: 'https://www.target.com/p/fixture',
      confirmed: true,
    },
    availability: 'in_stock',
    observedAvailabilityText: 'In stock',
    matchStatus: 'matched',
    product: { upc: '000111222333', name: 'Fixture milk' },
    aisle: { display: 'A12' },
    price: { regular: 3.99 },
  });
  assert.equal(CODEX_SHOPPING_WEBSITE_RESEARCH_OUTPUT_SCHEMA.additionalProperties, false);
});

test('Codex parser fails safely for malformed output while preserving domain-scope rejection', () => {
  const malformed = parseCodexShoppingWebsiteResearchResponse(request, 'not JSON');
  assert.deepEqual(
    { availability: malformed.availability, matchStatus: malformed.matchStatus, failureCode: malformed.failureCode },
    { availability: 'unknown', matchStatus: 'website_error', failureCode: 'invalid_agent_result' },
  );

  const directApi = parseCodexShoppingWebsiteResearchResponse(request, JSON.stringify({
    outcome: 'matched',
    navigation: { url: 'https://www.target.com/api/products/fixture', method: 'GET' },
    renderedStoreText: 'Target 1365 Sgt Jon Stiles Dr Highlands Ranch CO',
    product: { name: 'Fixture milk' },
  }));
  assert.deepEqual(
    { availability: directApi.availability, matchStatus: directApi.matchStatus, failureCode: directApi.failureCode },
    { availability: 'unknown', matchStatus: 'domain_scope_failure', failureCode: 'site_scope_unavailable' },
  );
});

test('the concrete Stage 4 researcher cannot start a Codex thread until browser-only enforcement exists', async () => {
  const researcher = new CodexShoppingWebsiteResearcher();
  const result = await researcher.research(request);

  assert.deepEqual(
    { availability: result.availability, matchStatus: result.matchStatus, failureCode: result.failureCode },
    { availability: 'unknown', matchStatus: 'website_error', failureCode: 'site_scope_unavailable' },
  );
});

test('the isolated execution seam applies structured output and returns a safe timeout failure with fakes', async () => {
  const successThread = {
    async run() {
      return {
        finalResponse: JSON.stringify({
          outcome: 'no_match',
          navigation: { url: 'https://target.com/s', method: 'GET' },
          renderedStoreText: '1365 Sgt Jon Stiles Dr Highlands Ranch CO',
        }),
        items: [],
        usage: null,
      };
    },
  };
  const success = await runCodexShoppingWebsiteResearchTurn(successThread, request, 50);
  assert.deepEqual(
    { availability: success.availability, matchStatus: success.matchStatus },
    { availability: 'unknown', matchStatus: 'no_match' },
  );

  const timeoutThread = {
    run(_prompt: string, options: { signal?: AbortSignal }) {
      return new Promise<never>((_resolve, reject) => {
        options.signal?.addEventListener('abort', () => reject(new Error('aborted')));
      });
    },
  };
  const timeout = await runCodexShoppingWebsiteResearchTurn(
    timeoutThread as unknown as Pick<Thread, 'run'>,
    request,
    1,
  );
  assert.deepEqual(
    { availability: timeout.availability, matchStatus: timeout.matchStatus, failureCode: timeout.failureCode },
    { availability: 'unknown', matchStatus: 'website_error', failureCode: 'website_unavailable' },
  );
});
