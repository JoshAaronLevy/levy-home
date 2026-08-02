export const RETAILER_WEBSITE_SCOPE = Object.freeze({
  allowedHosts: Object.freeze([
    'target.com',
    'www.target.com',
    'kingsoopers.com',
    'www.kingsoopers.com',
  ]),
  allowedMethods: Object.freeze(['GET', 'HEAD', 'OPTIONS']),
  policy: Object.freeze({
    maxItemsPerJob: 100,
    maxBrowserNavigationsPerStore: 12,
    jobTimeoutMs: 120_000,
    retryPolicy: 'no_automatic_retailer_retry',
    displayPrecedence: 'freshest_confirmed_website_listing_then_manual_fallback',
    publicStatuses: Object.freeze([
      'queued',
      'running',
      'completed',
      'completed_with_issues',
      'failed',
      'ai_unavailable',
      'site_scope_unavailable',
      'store_not_confirmed',
      'website_unavailable',
      'invalid_agent_result',
    ]),
  }),
  stores: Object.freeze([
    Object.freeze({
      key: 'target_highlands_ranch',
      appStoreId: 1,
      appStoreName: 'Target',
      displayName: 'Target — Highlands Ranch',
      address: '1365 Sgt Jon Stiles Dr, Highlands Ranch, CO',
      source: 'target.com',
    }),
    Object.freeze({
      key: 'king_soopers_wildcat_reserve',
      appStoreId: 2,
      appStoreName: 'King Soopers',
      displayName: 'King Soopers — Wildcat Reserve',
      address: '2205 W Wildcat Reserve Pkwy, Highlands Ranch, CO',
      source: 'kingsoopers.com',
    }),
  ]),
} as const);

export type RetailerWebsiteStore = (typeof RETAILER_WEBSITE_SCOPE.stores)[number];
export type RetailerWebsiteStoreKey = RetailerWebsiteStore['key'];
export type RetailerWebsiteHTTPMethod = (typeof RETAILER_WEBSITE_SCOPE.allowedMethods)[number];

const allowedHosts = new Set<string>(RETAILER_WEBSITE_SCOPE.allowedHosts);
const allowedMethods = new Set<string>(RETAILER_WEBSITE_SCOPE.allowedMethods);

/**
 * Stage 1 scope guard. It deliberately permits only the four user-approved
 * retailer hosts over HTTPS. It does not make a network request.
 *
 * A host/method allowlist cannot prove that a same-host URL is a rendered
 * website page rather than an API endpoint. Stage 4 must provide a separately
 * enforced browser-only execution boundary before any live research runs.
 */
export function isAllowedRetailerWebsiteNavigation(
  value: string | URL,
  method: string,
): boolean {
  const normalizedMethod = method.trim().toUpperCase();

  if (!allowedMethods.has(normalizedMethod)) {
    return false;
  }

  let url: URL;

  try {
    url = value instanceof URL ? value : new URL(value);
  } catch {
    return false;
  }

  return (
    url.protocol === 'https:'
    && url.username.length === 0
    && url.password.length === 0
    && url.port.length === 0
    && allowedHosts.has(url.hostname.toLowerCase())
  );
}

export function retailerWebsiteStoreForAppStoreId(forAppStoreId: number): RetailerWebsiteStore | undefined {
  return RETAILER_WEBSITE_SCOPE.stores.find((store) => store.appStoreId === forAppStoreId);
}

export function retailerWebsiteStoreForKey(forKey: RetailerWebsiteStoreKey): RetailerWebsiteStore {
  const store = RETAILER_WEBSITE_SCOPE.stores.find((candidate) => candidate.key === forKey);

  if (!store) {
    throw new Error(`Unsupported retailer website store key: ${forKey}`);
  }

  return store;
}

export function hasConfirmedRetailerWebsiteStoreAddress(
  renderedText: string,
  store: RetailerWebsiteStore,
): boolean {
  return normalizedAddress(renderedText).includes(normalizedAddress(store.address));
}

function normalizedAddress(value: string): string {
  return value
    .trim()
    .toLocaleLowerCase('en-US')
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}
