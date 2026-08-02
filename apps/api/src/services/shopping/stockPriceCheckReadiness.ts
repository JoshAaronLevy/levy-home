import { CODEX_SHOPPING_WEBSITE_RESEARCH_READINESS } from './codexShoppingWebsiteResearcher.js';
import { RETAILER_WEBSITE_SCOPE } from './retailerWebsiteScope.js';
import type { ShoppingStockPriceCheckStore } from '../../repositories/shoppingStockPriceCheckRepository.js';

export type ShoppingStockPriceCheckReadiness = {
  getReadiness: () => Promise<ShoppingStockPriceCheckReadinessResponse>;
};

export type ShoppingStockPriceCheckReadinessResponse = {
  ok: boolean;
  enabled: boolean;
  checks: {
    persistence: { ok: boolean; configured: boolean; code?: string };
    fixedStoreScope: {
      ok: boolean;
      targetHighlandsRanch: boolean;
      kingSoopersWildcatReserve: boolean;
      allowedHosts: boolean;
      allowedMethods: boolean;
    };
    codexRuntime: { ok: boolean; enabled: boolean; code?: string };
  };
};

export function createShoppingStockPriceCheckReadiness(options: {
  shoppingStockPriceCheckStore?: Pick<ShoppingStockPriceCheckStore, 'fetchActiveRun'>;
  codexRuntime?: typeof CODEX_SHOPPING_WEBSITE_RESEARCH_READINESS;
} = {}): ShoppingStockPriceCheckReadiness {
  return {
    async getReadiness() {
      const persistence = await persistenceReadiness(options.shoppingStockPriceCheckStore);
      const fixedStoreScope = fixedStoreScopeReadiness();
      const runtime = options.codexRuntime ?? CODEX_SHOPPING_WEBSITE_RESEARCH_READINESS;
      const codexRuntime = {
        ok: runtime.enabled,
        enabled: runtime.enabled,
        ...(runtime.enabled ? {} : { code: runtime.code }),
      };

      return {
        // `ok` says the readiness projection itself completed safely. Feature
        // availability is carried by `enabled`, so an intentionally disabled
        // optional AI feature cannot make the whole API fail /ready.
        ok: persistence.ok || !persistence.configured,
        enabled: persistence.ok && fixedStoreScope.ok && codexRuntime.ok,
        checks: { persistence, fixedStoreScope, codexRuntime },
      };
    },
  };
}

async function persistenceReadiness(
  store: Pick<ShoppingStockPriceCheckStore, 'fetchActiveRun'> | undefined,
): Promise<{ ok: boolean; configured: boolean; code?: string }> {
  if (!store) return { ok: false, configured: false, code: 'shopping_stock_price_check_not_configured' };

  try {
    await store.fetchActiveRun();
    return { ok: true, configured: true };
  } catch {
    return { ok: false, configured: true, code: 'shopping_stock_price_check_persistence_unavailable' };
  }
}

function fixedStoreScopeReadiness(): ShoppingStockPriceCheckReadinessResponse['checks']['fixedStoreScope'] {
  const target = RETAILER_WEBSITE_SCOPE.stores.find((store) => store.key === 'target_highlands_ranch');
  const kingSoopers = RETAILER_WEBSITE_SCOPE.stores.find((store) => store.key === 'king_soopers_wildcat_reserve');
  const targetHighlandsRanch = target?.address === '1365 Sgt Jon Stiles Dr, Highlands Ranch, CO';
  const kingSoopersWildcatReserve = kingSoopers?.address === '2205 W Wildcat Reserve Pkwy, Highlands Ranch, CO';
  const allowedHosts = RETAILER_WEBSITE_SCOPE.allowedHosts.length === 4;
  const allowedMethods = RETAILER_WEBSITE_SCOPE.allowedMethods.join(',') === 'GET,HEAD,OPTIONS';

  return {
    ok: Boolean(targetHighlandsRanch && kingSoopersWildcatReserve && allowedHosts && allowedMethods),
    targetHighlandsRanch: Boolean(targetHighlandsRanch),
    kingSoopersWildcatReserve: Boolean(kingSoopersWildcatReserve),
    allowedHosts,
    allowedMethods,
  };
}
