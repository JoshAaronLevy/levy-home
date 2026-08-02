import type {
  ShoppingItemStoreListingAisle,
  ShoppingItemStoreListingPrice,
  ShoppingStockAvailabilityStatus,
  ShoppingStockPriceCheckItemSnapshot,
  ShoppingStockPriceCheckMatchStatus,
  ShoppingStockPriceCheckStoreOutcome,
  ShoppingWebsiteObservedProduct,
} from '../../contracts.js';
import {
  RETAILER_WEBSITE_SCOPE,
  hasConfirmedRetailerWebsiteStoreAddress,
  isAllowedRetailerWebsiteNavigation,
  retailerWebsiteStoreForKey,
  type RetailerWebsiteHTTPMethod,
  type RetailerWebsiteStore,
  type RetailerWebsiteStoreKey,
} from './retailerWebsiteScope.js';

const MAX_PRODUCT_ID_LENGTH = 128;
const MAX_UPC_LENGTH = 32;
const MAX_PRODUCT_NAME_LENGTH = 160;
const MAX_BRAND_LENGTH = 120;
const MAX_AVAILABILITY_TEXT_LENGTH = 160;
const MAX_AISLE_TEXT_LENGTH = 160;

/**
 * The ordered interaction an eventual Stage 4 browser runner must follow.
 * It is descriptive only: this Stage 3 module performs no navigation.
 */
export const RETAILER_WEBSITE_RESEARCH_SEQUENCE = Object.freeze([
  'Open the fixed retailer homepage using normal browser navigation.',
  'Set or confirm the fixed store address in the retailer’s visible store-selection UI.',
  'Use that retailer’s visible search UI for the needed shopping item.',
  'Open an allowlisted rendered product/detail page only when needed.',
  'Return bounded facts visibly shown by the confirmed-store page or a classified safe outcome.',
] as const);

export type RetailerWebsiteResearchRequest = {
  item: ShoppingStockPriceCheckItemSnapshot;
  storeKey: RetailerWebsiteStoreKey;
};

/**
 * Stage 4 supplies the concrete Codex implementation. Stage 3 intentionally
 * defines only this injected, fixed-scope boundary so it can be tested with
 * synthetic rendered-page evidence and cannot receive arbitrary URLs/stores.
 */
export type RetailerWebsiteResearcher = {
  readonly scope: typeof RETAILER_WEBSITE_SCOPE;
  research: (request: RetailerWebsiteResearchRequest) => Promise<RetailerWebsiteResearchResult>;
};

export type RetailerWebsiteResearchResult = ShoppingStockPriceCheckStoreOutcome;

/**
 * Synthetic or runner-produced, user-visible-page evidence. This deliberately
 * has no HTML, cookie, network-response, prompt, or direct-API-payload field.
 */
export type RetailerWebsiteRenderedPageEvidence = {
  outcome: 'matched' | 'no_match' | 'ambiguous' | 'website_error';
  navigation?: {
    url: string;
    method: RetailerWebsiteHTTPMethod | string;
  };
  renderedStoreText?: string;
  renderedAvailabilityText?: string;
  product?: {
    productId?: string;
    upc?: string;
    brand?: string;
    name?: string;
  };
  aisle?: {
    display?: string;
    description?: string;
    number?: string;
    shelfNumber?: string;
  };
  price?: {
    regular?: number;
    promo?: number;
  };
};

export class RetailerWebsiteResearchValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'RetailerWebsiteResearchValidationError';
  }
}

/**
 * Converts only bounded synthetic/rendered-page evidence into an app-safe
 * result. Invalid navigation is classified as a domain-scope failure; malformed
 * evidence is rejected rather than being guessed or persisted.
 *
 * This is not a browser security control. In particular, a same-host URL can
 * still be an API endpoint, so Stage 4 must enforce browser-only execution
 * outside the model and outside this validator.
 */
export function validateRetailerWebsiteResearchResult(
  request: RetailerWebsiteResearchRequest,
  value: unknown,
): RetailerWebsiteResearchResult {
  assertValidResearchRequest(request);
  const evidence = readEvidence(value);
  const store = retailerWebsiteStoreForKey(request.storeKey);
  const navigation = readSafeRenderedPageNavigation(evidence.navigation);

  if (navigation.kind === 'invalid') {
    return safeFailure(store, 'domain_scope_failure', 'site_scope_unavailable');
  }

  if (evidence.outcome === 'website_error') {
    return safeFailure(
      store,
      'website_error',
      'website_unavailable',
      navigation.pageURL,
      hasConfirmedStoreText(evidence.renderedStoreText, store),
    );
  }

  const storeConfirmed = hasConfirmedStoreText(evidence.renderedStoreText, store);

  if (!storeConfirmed) {
    return safeFailure(
      store,
      'store_unconfirmed',
      'store_not_confirmed',
      navigation.pageURL,
      false,
    );
  }

  if (evidence.outcome === 'no_match' || evidence.outcome === 'ambiguous') {
    assertNoMatchedProductFacts(evidence);
    return {
      store: selectedStoreEvidence(store, navigation.pageURL, true),
      availability: 'unknown',
      matchStatus: evidence.outcome,
    };
  }

  const product = readProduct(evidence.product);

  if (!product || (!product.name && !product.productId && !product.upc)) {
    throw new RetailerWebsiteResearchValidationError(
      'A rendered-page match must include a bounded, site-visible product identifier.',
    );
  }

  const observedAvailabilityText = optionalBoundedString(
    evidence.renderedAvailabilityText,
    'renderedAvailabilityText',
    MAX_AVAILABILITY_TEXT_LENGTH,
  );
  const price = readPrice(evidence.price);
  const aisle = readAisle(evidence.aisle);

  return {
    store: selectedStoreEvidence(store, navigation.pageURL, true),
    availability: normalizeRenderedAvailability(observedAvailabilityText),
    ...(observedAvailabilityText ? { observedAvailabilityText } : {}),
    matchStatus: 'matched',
    product,
    ...(aisle ? { aisle } : {}),
    ...(price ? { price } : {}),
  };
}

/** Normalizes only explicit, visibly rendered inventory wording. */
export function normalizeRenderedAvailability(value: string | undefined): ShoppingStockAvailabilityStatus {
  if (!value) {
    return 'unknown';
  }

  const normalized = value.trim().toLocaleLowerCase('en-US');

  if (/\bout of stock\b|\bnot available\b|\bunavailable\b/.test(normalized)) {
    return 'out_of_stock';
  }

  if (/\blow stock\b|\blimited stock\b|\bfew left\b|\bonly\s+\d+\s+left\b/.test(normalized)) {
    return 'low_stock';
  }

  if (/\bin stock\b|\bavailable for pickup\b|\bavailable\b/.test(normalized)) {
    return 'in_stock';
  }

  return 'unknown';
}

function assertValidResearchRequest(request: RetailerWebsiteResearchRequest): void {
  if (!Number.isInteger(request.item.itemId) || request.item.itemId < 1) {
    throw new RetailerWebsiteResearchValidationError('Website research requires a persisted shopping item ID.');
  }

  retailerWebsiteStoreForKey(request.storeKey);
}

function readEvidence(value: unknown): RetailerWebsiteRenderedPageEvidence {
  if (!isRecord(value)) {
    throw new RetailerWebsiteResearchValidationError('Website research evidence must be an object.');
  }

  const outcome = requiredEnum(value.outcome, 'outcome', ['matched', 'no_match', 'ambiguous', 'website_error'] as const);

  return {
    outcome,
    ...(value.navigation === undefined ? {} : { navigation: readNavigation(value.navigation) }),
    ...(value.renderedStoreText === undefined ? {} : {
      renderedStoreText: optionalBoundedString(value.renderedStoreText, 'renderedStoreText', 300),
    }),
    ...(value.renderedAvailabilityText === undefined ? {} : {
      renderedAvailabilityText: optionalBoundedString(
        value.renderedAvailabilityText,
        'renderedAvailabilityText',
        MAX_AVAILABILITY_TEXT_LENGTH,
      ),
    }),
    ...(value.product === undefined ? {} : { product: readProductInput(value.product) }),
    ...(value.aisle === undefined ? {} : { aisle: readAisleInput(value.aisle) }),
    ...(value.price === undefined ? {} : { price: readPriceInput(value.price) }),
  };
}

function readNavigation(value: unknown): NonNullable<RetailerWebsiteRenderedPageEvidence['navigation']> {
  if (!isRecord(value) || typeof value.url !== 'string' || typeof value.method !== 'string') {
    throw new RetailerWebsiteResearchValidationError('Rendered-page navigation must contain a URL and method.');
  }

  return { url: value.url, method: value.method };
}

function readSafeRenderedPageNavigation(
  navigation: RetailerWebsiteRenderedPageEvidence['navigation'],
): { kind: 'valid'; pageURL: string } | { kind: 'invalid' } {
  if (!navigation || !isAllowedRetailerWebsiteNavigation(navigation.url, navigation.method)) {
    return { kind: 'invalid' };
  }

  let url: URL;

  try {
    url = new URL(navigation.url);
  } catch {
    return { kind: 'invalid' };
  }

  if (navigation.method.trim().toUpperCase() !== 'GET' || hasObviousDirectEndpointPath(url.pathname)) {
    return { kind: 'invalid' };
  }

  // A page URL is retained only for provenance. Query and fragment values can
  // carry session/search data, so neither may enter an app-facing result.
  url.search = '';
  url.hash = '';
  return { kind: 'valid', pageURL: url.toString() };
}

function hasObviousDirectEndpointPath(pathname: string): boolean {
  const segments = pathname.toLocaleLowerCase('en-US').split('/').filter(Boolean);

  return segments.some((segment) => ['api', 'graphql', 'json', 'services'].includes(segment))
    || pathname.toLocaleLowerCase('en-US').endsWith('.json')
    || pathname.toLocaleLowerCase('en-US').startsWith('/_next/');
}

function hasConfirmedStoreText(value: string | undefined, store: RetailerWebsiteStore): boolean {
  return value !== undefined && hasConfirmedRetailerWebsiteStoreAddress(value, store);
}

function selectedStoreEvidence(
  store: RetailerWebsiteStore,
  pageURL: string | undefined,
  confirmed: boolean,
): ShoppingStockPriceCheckStoreOutcome['store'] {
  return {
    storeId: store.appStoreId,
    storeName: store.appStoreName,
    source: store.source,
    selectedStoreAddress: store.address,
    ...(pageURL ? { pageURL } : {}),
    confirmed,
  };
}

function safeFailure(
  store: RetailerWebsiteStore,
  matchStatus: Extract<
    ShoppingStockPriceCheckMatchStatus,
    'store_unconfirmed' | 'website_error' | 'domain_scope_failure'
  >,
  failureCode: 'site_scope_unavailable' | 'store_not_confirmed' | 'website_unavailable',
  pageURL?: string,
  confirmed = false,
): RetailerWebsiteResearchResult {
  return {
    store: selectedStoreEvidence(store, pageURL, confirmed),
    availability: 'unknown',
    matchStatus,
    failureCode,
  };
}

function assertNoMatchedProductFacts(evidence: RetailerWebsiteRenderedPageEvidence): void {
  if (evidence.product || evidence.aisle || evidence.price || evidence.renderedAvailabilityText) {
    throw new RetailerWebsiteResearchValidationError(
      'No-match and ambiguous results cannot retain product, price, aisle, or availability facts.',
    );
  }
}

function readProduct(value: RetailerWebsiteRenderedPageEvidence['product']): ShoppingWebsiteObservedProduct | undefined {
  if (!value) {
    return undefined;
  }

  const product = {
    ...(optionalBoundedString(value.productId, 'product.productId', MAX_PRODUCT_ID_LENGTH)
      ? { productId: optionalBoundedString(value.productId, 'product.productId', MAX_PRODUCT_ID_LENGTH) }
      : {}),
    ...(optionalBoundedString(value.upc, 'product.upc', MAX_UPC_LENGTH)
      ? { upc: optionalBoundedString(value.upc, 'product.upc', MAX_UPC_LENGTH) }
      : {}),
    ...(optionalBoundedString(value.brand, 'product.brand', MAX_BRAND_LENGTH)
      ? { brand: optionalBoundedString(value.brand, 'product.brand', MAX_BRAND_LENGTH) }
      : {}),
    ...(optionalBoundedString(value.name, 'product.name', MAX_PRODUCT_NAME_LENGTH)
      ? { name: optionalBoundedString(value.name, 'product.name', MAX_PRODUCT_NAME_LENGTH) }
      : {}),
  };

  return Object.keys(product).length > 0 ? product : undefined;
}

function readProductInput(value: unknown): NonNullable<RetailerWebsiteRenderedPageEvidence['product']> {
  if (!isRecord(value)) {
    throw new RetailerWebsiteResearchValidationError('product must be an object.');
  }

  return {
    ...(value.productId === undefined ? {} : { productId: optionalBoundedString(value.productId, 'product.productId', MAX_PRODUCT_ID_LENGTH) }),
    ...(value.upc === undefined ? {} : { upc: optionalBoundedString(value.upc, 'product.upc', MAX_UPC_LENGTH) }),
    ...(value.brand === undefined ? {} : { brand: optionalBoundedString(value.brand, 'product.brand', MAX_BRAND_LENGTH) }),
    ...(value.name === undefined ? {} : { name: optionalBoundedString(value.name, 'product.name', MAX_PRODUCT_NAME_LENGTH) }),
  };
}

function readAisle(value: RetailerWebsiteRenderedPageEvidence['aisle']): ShoppingItemStoreListingAisle | undefined {
  if (!value) {
    return undefined;
  }

  const aisle = {
    ...(optionalBoundedString(value.display, 'aisle.display', MAX_AISLE_TEXT_LENGTH)
      ? { display: optionalBoundedString(value.display, 'aisle.display', MAX_AISLE_TEXT_LENGTH) }
      : {}),
    ...(optionalBoundedString(value.description, 'aisle.description', MAX_AISLE_TEXT_LENGTH)
      ? { description: optionalBoundedString(value.description, 'aisle.description', MAX_AISLE_TEXT_LENGTH) }
      : {}),
    ...(optionalBoundedString(value.number, 'aisle.number', 32)
      ? { number: optionalBoundedString(value.number, 'aisle.number', 32) }
      : {}),
    ...(optionalBoundedString(value.shelfNumber, 'aisle.shelfNumber', 32)
      ? { shelfNumber: optionalBoundedString(value.shelfNumber, 'aisle.shelfNumber', 32) }
      : {}),
  };

  return Object.keys(aisle).length > 0 ? aisle : undefined;
}

function readAisleInput(value: unknown): NonNullable<RetailerWebsiteRenderedPageEvidence['aisle']> {
  if (!isRecord(value)) {
    throw new RetailerWebsiteResearchValidationError('aisle must be an object.');
  }

  return {
    ...(value.display === undefined ? {} : { display: optionalBoundedString(value.display, 'aisle.display', MAX_AISLE_TEXT_LENGTH) }),
    ...(value.description === undefined ? {} : { description: optionalBoundedString(value.description, 'aisle.description', MAX_AISLE_TEXT_LENGTH) }),
    ...(value.number === undefined ? {} : { number: optionalBoundedString(value.number, 'aisle.number', 32) }),
    ...(value.shelfNumber === undefined ? {} : { shelfNumber: optionalBoundedString(value.shelfNumber, 'aisle.shelfNumber', 32) }),
  };
}

function readPrice(value: RetailerWebsiteRenderedPageEvidence['price']): ShoppingItemStoreListingPrice | undefined {
  if (!value) {
    return undefined;
  }

  const price = {
    ...(readNonnegativeFiniteNumber(value.regular, 'price.regular') !== undefined
      ? { regular: readNonnegativeFiniteNumber(value.regular, 'price.regular') }
      : {}),
    ...(readNonnegativeFiniteNumber(value.promo, 'price.promo') !== undefined
      ? { promo: readNonnegativeFiniteNumber(value.promo, 'price.promo') }
      : {}),
  };

  return Object.keys(price).length > 0 ? price : undefined;
}

function readPriceInput(value: unknown): NonNullable<RetailerWebsiteRenderedPageEvidence['price']> {
  if (!isRecord(value)) {
    throw new RetailerWebsiteResearchValidationError('price must be an object.');
  }

  return {
    ...(value.regular === undefined ? {} : { regular: readNonnegativeFiniteNumber(value.regular, 'price.regular') }),
    ...(value.promo === undefined ? {} : { promo: readNonnegativeFiniteNumber(value.promo, 'price.promo') }),
  };
}

function readNonnegativeFiniteNumber(value: unknown, fieldName: string): number | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    throw new RetailerWebsiteResearchValidationError(`${fieldName} must be a finite, non-negative number.`);
  }

  return value;
}

function optionalBoundedString(value: unknown, fieldName: string, maximumLength: number): string | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== 'string') {
    throw new RetailerWebsiteResearchValidationError(`${fieldName} must be a string.`);
  }

  const normalized = value.trim();

  if (normalized.length === 0) {
    return undefined;
  }

  if (normalized.length > maximumLength) {
    throw new RetailerWebsiteResearchValidationError(`${fieldName} exceeds its maximum length.`);
  }

  return normalized;
}

function requiredEnum<Value extends string>(
  value: unknown,
  fieldName: string,
  allowedValues: readonly Value[],
): Value {
  if (typeof value !== 'string' || !allowedValues.includes(value as Value)) {
    throw new RetailerWebsiteResearchValidationError(`${fieldName} has an unsupported value.`);
  }

  return value as Value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}
