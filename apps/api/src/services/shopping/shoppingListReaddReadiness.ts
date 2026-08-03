import type { ShoppingListReaddStore } from '../../repositories/shoppingListReaddRepository.js';

import {
  CodexShoppingListReaddMatcher,
  type ShoppingListReaddMatcher,
  type ShoppingListReaddReadinessCheck,
} from './shoppingListReaddMatcher.js';

export type ShoppingListReaddReadinessResponse = {
  ready: boolean;
  matcherRuntime: ShoppingListReaddReadinessCheck;
  authentication: ShoppingListReaddReadinessCheck;
  persistence: ShoppingListReaddReadinessCheck;
};

export type ShoppingListReaddReadiness = {
  getReadiness: () => Promise<ShoppingListReaddReadinessResponse>;
};

/**
 * Non-sensitive readiness projection for a future narrow HTTP endpoint.
 * It only probes the local persistence seam and matcher configuration; it
 * never invokes Codex, a retailer, or any external network capability.
 */
export async function getShoppingListReaddReadiness(options: {
  matcher?: ShoppingListReaddMatcher;
  store?: Pick<ShoppingListReaddStore, 'fetchRun'>;
} = {}): Promise<ShoppingListReaddReadinessResponse> {
  const matcher = options.matcher ?? new CodexShoppingListReaddMatcher();
  const matcherReadiness = matcher.getReadiness();
  const persistence = await persistenceReadiness(options.store);

  return {
    ready: matcherReadiness.runtime.ready && matcherReadiness.authentication.ready && persistence.ready,
    matcherRuntime: matcherReadiness.runtime,
    authentication: matcherReadiness.authentication,
    persistence,
  };
}

export function createShoppingListReaddReadiness(options: {
  matcher?: ShoppingListReaddMatcher;
  store?: Pick<ShoppingListReaddStore, 'fetchRun'>;
} = {}): ShoppingListReaddReadiness {
  return {
    getReadiness: () => getShoppingListReaddReadiness(options),
  };
}

async function persistenceReadiness(
  store: Pick<ShoppingListReaddStore, 'fetchRun'> | undefined,
): Promise<ShoppingListReaddReadinessCheck> {
  if (!store) return { ready: false, code: 'persistence_unavailable' };

  try {
    await store.fetchRun('00000000-0000-0000-0000-000000000000');
    return { ready: true };
  } catch {
    return { ready: false, code: 'persistence_unavailable' };
  }
}
