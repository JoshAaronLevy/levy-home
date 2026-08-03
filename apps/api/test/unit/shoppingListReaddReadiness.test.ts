import assert from 'node:assert/strict';
import { test } from 'node:test';

import { getShoppingListReaddReadiness } from '../../src/services/shopping/shoppingListReaddReadiness.js';
import type { ShoppingListReaddMatcher } from '../../src/services/shopping/shoppingListReaddMatcher.js';

const readyMatcher: ShoppingListReaddMatcher = {
  getReadiness: () => ({ runtime: { ready: true }, authentication: { ready: true } }),
  async match() {
    return { operations: [], unmatched: [] };
  },
};

test('readiness separately reports ready matcher, authentication, and persistence seams', async () => {
  const readiness = await getShoppingListReaddReadiness({
    matcher: readyMatcher,
    store: { async fetchRun() { return null; } },
  });

  assert.deepEqual(readiness, {
    ready: true,
    matcherRuntime: { ready: true },
    authentication: { ready: true },
    persistence: { ready: true },
  });
});

test('readiness fails safely and names only the unavailable subsystem', async () => {
  const missingPersistence = await getShoppingListReaddReadiness({ matcher: readyMatcher });
  assert.deepEqual(missingPersistence.persistence, { ready: false, code: 'persistence_unavailable' });
  assert.equal(missingPersistence.ready, false);

  const unavailableMatcher: ShoppingListReaddMatcher = {
    ...readyMatcher,
    getReadiness: () => ({
      runtime: { ready: false, code: 'matcher_runtime_unavailable' },
      authentication: { ready: false, code: 'authentication_unavailable' },
    }),
  };
  const matcherReadiness = await getShoppingListReaddReadiness({
    matcher: unavailableMatcher,
    store: { async fetchRun() { throw new Error('database unavailable'); } },
  });
  assert.deepEqual(matcherReadiness, {
    ready: false,
    matcherRuntime: { ready: false, code: 'matcher_runtime_unavailable' },
    authentication: { ready: false, code: 'authentication_unavailable' },
    persistence: { ready: false, code: 'persistence_unavailable' },
  });
});
