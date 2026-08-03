import type { EventPushStatus } from './activity.js';
import type { ShoppingTripSnapshot } from './shoppingTrips.js';

export type ShoppingListItem = {
  id: number;
  name: string;
  brand?: string;
  quantity: number;
  notes?: string;
  purchased: boolean;
  created?: string;
  updated?: string;
  version?: number;
  categoryId: number | null;
  image?: string;
  storeListings: ShoppingItemStoreListing[];
};

export type ShoppingItemStoreListingProduct = {
  productId?: string;
  upc?: string;
  productPageURI?: string;
  brand?: string;
  name?: string;
  description?: string;
  image?: string;
};

export type ShoppingItemStoreListingAisle = {
  display?: string;
  description?: string;
  number?: string;
  shelfNumber?: string;
  raw?: Record<string, unknown>;
};

export type ShoppingItemStoreListingPrice = {
  regular?: number;
  promo?: number;
};

export type ShoppingItemStoreListingAvailability = {
  status?: ShoppingStockAvailabilityStatus;
  checkedAt?: string;
  matchStatus?: ShoppingStockPriceCheckMatchStatus;
};

export type ShoppingItemStoreListing = {
  storeId?: number;
  storeName?: string;
  source?: string;
  selectedStoreAddress?: string;
  krogerLocationId?: string;
  product?: ShoppingItemStoreListingProduct;
  aisle?: ShoppingItemStoreListingAisle;
  price?: ShoppingItemStoreListingPrice;
  inventory?: Record<string, unknown>;
  fulfillment?: Record<string, unknown>;
  availability?: ShoppingItemStoreListingAvailability;
  checkedAt?: string;
};

export type ShoppingStore = {
  id: number;
  name: string;
  logo?: string;
};

export type ShoppingCategory = {
  id: number;
  name: string;
};

export type ShoppingListData = {
  items: ShoppingListItem[];
  stores: ShoppingStore[];
  categories: ShoppingCategory[];
};

export type ShoppingListSnapshotResponse = ShoppingListData & {
  ok: true;
  activeTrip: ShoppingTripSnapshot | null;
  generatedAt: string;
};

export type CreateShoppingListItemRequest = {
  name: string;
  brand?: string | null;
  quantity?: number;
  notes?: string | null;
  purchased?: boolean;
  categoryId?: number | null;
  image?: string | null;
  storeListings?: ShoppingItemStoreListing[];
  actor?: string;
  mutationId?: string;
};

export type UpdateShoppingListItemRequest = {
  name?: string;
  brand?: string | null;
  quantity?: number;
  notes?: string | null;
  purchased?: boolean;
  categoryId?: number | null;
  image?: string | null;
  storeListings?: ShoppingItemStoreListing[];
  actor?: string;
  mutationId?: string;
};

export type DeleteShoppingListItemRequest = {
  actor?: string;
  mutationId?: string;
};

export type ShoppingListItemLookupResponse = {
  ok: true;
  query: string;
  match: ShoppingListItem | null;
};

export type KrogerProductSearchResponse = {
  ok: boolean;
  query: string;
  generatedAt: string;
  productStatusCode?: number;
  products: KrogerProductSearchResult[];
  error?: string;
};

export type KrogerProductSearchResult = {
  productId: string | null;
  upc: string | null;
  productPageURI: string | null;
  aisles: unknown[];
  brand: string | null;
  name: string | null;
  description: string | null;
  image: string | null;
  storeListings: ShoppingItemStoreListing[];
};

export type ShoppingListMutationResponse = {
  ok: true;
  item: ShoppingListItem;
  activeTrip: ShoppingTripSnapshot | null;
  mutationId: string;
  generatedAt: string;
  push?: EventPushStatus;
};

export type DeleteShoppingListItemResponse = {
  ok: true;
  itemId: number;
  item: ShoppingListItem;
  activeTrip: ShoppingTripSnapshot | null;
  mutationId: string;
  generatedAt: string;
  push?: EventPushStatus;
};

/** The only availability values the website-research workflow may persist. */
export type ShoppingStockAvailabilityStatus =
  | 'in_stock'
  | 'low_stock'
  | 'out_of_stock'
  | 'unknown';

export type ShoppingStockPriceCheckMatchStatus =
  | 'matched'
  | 'no_match'
  | 'ambiguous'
  | 'website_error'
  | 'store_unconfirmed'
  | 'domain_scope_failure';

export type ShoppingStockPriceCheckStatus =
  | 'queued'
  | 'running'
  | 'completed'
  | 'completed_with_issues'
  | 'failed';

export type ShoppingStockPriceCheckPhase =
  | 'preparing'
  | 'checking_stores'
  | 'matching_products'
  | 'applying_updates'
  | 'finished';

export type ShoppingWebsiteObservedProduct = {
  productId?: string;
  upc?: string;
  brand?: string;
  name?: string;
  image?: string;
};

export type ShoppingWebsiteSelectedStoreEvidence = {
  storeId: number;
  storeName: string;
  source: 'target.com' | 'kingsoopers.com';
  selectedStoreAddress: string;
  /** An allowlisted rendered-page URL with sensitive query data removed. */
  pageURL?: string;
  confirmed: boolean;
};

export type ShoppingStockPriceCheckStoreOutcome = {
  store: ShoppingWebsiteSelectedStoreEvidence;
  availability: ShoppingStockAvailabilityStatus;
  /** Bounded text visibly shown by the permitted rendered page, when supplied. */
  observedAvailabilityText?: string;
  matchStatus: ShoppingStockPriceCheckMatchStatus;
  product?: ShoppingWebsiteObservedProduct;
  aisle?: ShoppingItemStoreListingAisle;
  price?: ShoppingItemStoreListingPrice;
  checkedAt?: string;
  failureCode?: string;
};

export type ShoppingStockPriceCheckItemOutcomeStatus =
  | 'pending'
  | 'updated'
  | 'unmatched'
  | 'failed'
  | 'skipped_stale';

export type ShoppingStockPriceCheckItemSnapshot = {
  itemId: number;
  itemVersion: number;
  name: string;
  brand?: string;
  quantity: number;
  notes?: string;
  categoryId: number | null;
  image?: string;
  storeListings: ShoppingItemStoreListing[];
};

export type ShoppingStockPriceCheckItemOutcome = {
  id: string;
  runId: string;
  item: ShoppingStockPriceCheckItemSnapshot;
  status: ShoppingStockPriceCheckItemOutcomeStatus;
  storeOutcomes: ShoppingStockPriceCheckStoreOutcome[];
  failureCode?: string;
  createdAt: string;
  updatedAt: string;
};

export type ShoppingStockPriceCheckSummary = {
  ok: true;
  id: string;
  status: ShoppingStockPriceCheckStatus;
  phase: ShoppingStockPriceCheckPhase;
  requestedItemCount: number;
  processedItemCount: number;
  updatedItemCount: number;
  unmatchedItemCount: number;
  failedItemCount: number;
  skippedStaleItemCount: number;
  submittedAt: string;
  startedAt: string | null;
  finishedAt: string | null;
  failureCode?: string;
  message?: string;
};

export type StartShoppingStockPriceCheckRequest = {
  actor?: string;
  mutationId: string;
};

/**
 * Public-safe descriptions of how an existing item was selected. These values
 * intentionally reveal no model score, prompt, candidate list, or rationale.
 */
export type ShoppingListReaddMatchKind = 'exact' | 'normalized' | 'semantic';

/**
 * Public outcome for one requested phrase. See the re-add matching policy for
 * the server-side rules; iOS must not infer any internal details from this.
 */
export type ShoppingListReaddOperationOutcome =
  | 're_added'
  | 'quantity_updated'
  | 'already_needed'
  | 'unmatched'
  | 'stale_skipped'
  | 'invalid_request'
  | 'unavailable'
  | 'undone';

export type ShoppingListReaddRunStatus =
  | 'queued'
  | 'matching'
  | 'applying'
  | 'completed'
  | 'completed_with_issues'
  | 'failed'
  | 'undone';

export type ShoppingListReaddOperationSummary = {
  requestIndex: number;
  requestedText: string;
  outcome: ShoppingListReaddOperationOutcome;
  itemId?: number;
  itemName?: string;
  /** Present only when the request explicitly set the quantity. */
  quantity?: number;
  matchKind?: ShoppingListReaddMatchKind;
};

export type ShoppingListReaddUnmatchedPhrase = {
  requestIndex: number;
  requestedText: string;
};

export type ShoppingListReaddUndoAvailability = {
  available: boolean;
  expiresAt?: string;
};

/**
 * The only re-add result shape exposed to iOS. Prompts, raw model output,
 * candidate snapshots, scores, thread IDs, and runtime diagnostics are never
 * part of this contract.
 */
export type ShoppingListReaddSummary = {
  ok: true;
  id: string;
  status: ShoppingListReaddRunStatus;
  operations: ShoppingListReaddOperationSummary[];
  unmatched: ShoppingListReaddUnmatchedPhrase[];
  undo: ShoppingListReaddUndoAvailability;
  submittedAt: string;
  startedAt: string | null;
  finishedAt: string | null;
};

/**
 * The sole public start payload for offline Shopping re-add matching. The API
 * reads the Shopping candidates itself; clients cannot supply item IDs,
 * quantities, prompts, or model controls.
 */
export type StartShoppingListReaddRequest = {
  text: string;
  actor: 'Josh' | 'Mallory';
  mutationId: string;
};
