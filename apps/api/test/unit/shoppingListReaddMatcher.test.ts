import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { Thread } from '@openai/codex-sdk';

import {
  CODEX_SHOPPING_LIST_READD_OUTPUT_SCHEMA,
  CODEX_SHOPPING_LIST_READD_THREAD_OPTIONS,
  CodexShoppingListReaddMatcher,
  DeterministicShoppingListReaddMatcher,
  ShoppingListReaddMatcherInvalidResultError,
  ShoppingListReaddMatcherUnavailableError,
  buildCodexShoppingListReaddPrompt,
  parseCodexShoppingListReaddResponse,
  runCodexShoppingListReaddTurn,
} from '../../src/services/shopping/shoppingListReaddMatcher.js';
import type { ShoppingListReaddCandidateSnapshot } from '../../src/services/shopping/shoppingListReaddContracts.js';

const candidates: ShoppingListReaddCandidateSnapshot[] = [
  { itemId: 14, itemVersion: 8, name: 'Iced Coffee', brand: 'Stok', purchased: true, quantity: 1 },
  { itemId: 22, itemVersion: 4, name: 'Eggs', purchased: true, quantity: 1 },
  { itemId: 23, itemVersion: 2, name: 'Egg Cups', purchased: true, quantity: 1 },
];

test('offline Codex matcher configuration is read-only, approval-free, and network-disabled', () => {
  assert.deepEqual(CODEX_SHOPPING_LIST_READD_THREAD_OPTIONS, {
    sandboxMode: 'read-only',
    approvalPolicy: 'never',
    networkAccessEnabled: false,
    webSearchMode: 'disabled',
    webSearchEnabled: false,
    skipGitRepoCheck: true,
    workingDirectory: '/tmp',
  });
  assert.equal(CODEX_SHOPPING_LIST_READD_OUTPUT_SCHEMA.additionalProperties, false);
});

test('prompt has only approved bounded Shopping context and no retailer, browser, image, or database instructions', () => {
  const prompt = buildCodexShoppingListReaddPrompt('Add 2 coffees and eggs', candidates);

  assert.match(prompt, /"text":"2 coffees"/);
  assert.match(prompt, /"text":"eggs"/);
  assert.match(prompt, /Iced Coffee/);
  assert.match(prompt, /Egg Cups/);
  assert.match(prompt, /Use only the JSON below\. Do not use tools/);
  assert.doesNotMatch(prompt, /target|king soopers|retailer|store listing|browser|image|database|SQL|curl|fetch/i);
  assert.doesNotMatch(prompt, /\/Users\/|CODEX_API_KEY|DATABASE_URL/i);
});

test('deterministic fake validates exact, normalized, and semantic fixture plans without a Codex invocation', async () => {
  const exact = new DeterministicShoppingListReaddMatcher({
    operations: [{ requestIndex: 0, requestedText: 'eggs', itemId: 22, matchKind: 'exact' }],
    unmatched: [],
  });
  const normalized = new DeterministicShoppingListReaddMatcher({
    operations: [{ requestIndex: 0, requestedText: 'egg', itemId: 22, matchKind: 'normalized' }],
    unmatched: [],
  });
  const semantic = new DeterministicShoppingListReaddMatcher({
    operations: [{ requestIndex: 0, requestedText: '2 coffees', itemId: 14, quantity: 2, matchKind: 'semantic' }],
    unmatched: [],
  });

  assert.equal((await exact.match('eggs', candidates)).operations[0]?.itemId, 22);
  assert.equal((await normalized.match('egg', candidates)).operations[0]?.matchKind, 'normalized');
  assert.deepEqual((await semantic.match('2 coffees', candidates)).operations[0], {
    requestIndex: 0,
    requestedText: '2 coffees',
    itemId: 14,
    quantity: 2,
    matchKind: 'semantic',
  });
});

test('fake Codex turn returns a validated structured plan and has no database dependency', async () => {
  const thread = {
    async run(prompt: string) {
      assert.match(prompt, /Iced Coffee/);
      return {
        finalResponse: JSON.stringify({
          operations: [
            { requestIndex: 0, requestedText: '2 coffees', itemId: 14, quantity: 2, matchKind: 'semantic' },
            { requestIndex: 1, requestedText: 'eggs', itemId: 22, matchKind: 'exact' },
          ],
          unmatched: [],
        }),
        items: [],
        usage: null,
      };
    },
  };

  const plan = await runCodexShoppingListReaddTurn(thread, 'Add 2 coffees and eggs', candidates, 50);
  assert.deepEqual(plan.operations.map(({ itemId, quantity, matchKind }) => ({ itemId, quantity, matchKind })), [
    { itemId: 14, quantity: 2, matchKind: 'semantic' },
    { itemId: 22, quantity: undefined, matchKind: 'exact' },
  ]);
});

test('strict parser rejects malformed, unknown, and extra-field matcher output', () => {
  for (const response of [
    'not JSON',
    JSON.stringify({ operations: [{ requestIndex: 0, requestedText: 'eggs', itemId: 22, matchKind: 'exact', explanation: 'no' }], unmatched: [] }),
    JSON.stringify({ operations: [{ requestIndex: 0, requestedText: 'eggs', itemId: 999, matchKind: 'exact' }], unmatched: [] }),
  ]) {
    assert.throws(
      () => parseCodexShoppingListReaddResponse(response, 'Add eggs and more eggs', candidates),
      ShoppingListReaddMatcherInvalidResultError,
    );
  }
});

test('missing authentication and runtime failures are unavailable without revealing a supplied credential', async () => {
  const missingCredential = new CodexShoppingListReaddMatcher({ runtimeAvailable: true });
  assert.deepEqual(missingCredential.getReadiness().authentication, {
    ready: false,
    code: 'authentication_unavailable',
  });
  await assert.rejects(
    () => missingCredential.match('eggs', candidates),
    (error: unknown) => error instanceof ShoppingListReaddMatcherUnavailableError && error.code === 'authentication_unavailable',
  );

  const unavailableRuntime = new CodexShoppingListReaddMatcher({ apiKey: 'never-log-this', runtimeAvailable: false });
  assert.deepEqual(unavailableRuntime.getReadiness().runtime, {
    ready: false,
    code: 'matcher_runtime_unavailable',
  });
  await assert.rejects(
    () => unavailableRuntime.match('eggs', candidates),
    (error: unknown) => error instanceof ShoppingListReaddMatcherUnavailableError && error.code === 'matcher_runtime_unavailable',
  );
});

test('turn timeout fails closed', async () => {
  const timeoutThread = {
    run(_prompt: string, options: { signal?: AbortSignal }) {
      return new Promise<never>((_resolve, reject) => {
        options.signal?.addEventListener('abort', () => reject(new Error('aborted')));
      });
    },
  };

  await assert.rejects(
    () => runCodexShoppingListReaddTurn(timeoutThread as unknown as Pick<Thread, 'run'>, 'eggs', candidates, 1),
    (error: unknown) => error instanceof ShoppingListReaddMatcherUnavailableError && error.code === 'matcher_unavailable',
  );
});
