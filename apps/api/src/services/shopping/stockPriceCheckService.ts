import crypto from 'node:crypto';

import type {
  ShoppingItemStoreListing,
  ShoppingStockPriceCheckItemOutcome,
  ShoppingStockPriceCheckItemOutcomeStatus,
  ShoppingStockPriceCheckStoreOutcome,
  ShoppingStockPriceCheckSummary,
} from '../../contracts.js';
import type { ShoppingStockPriceCheckStore } from '../../repositories/shoppingStockPriceCheckRepository.js';
import { safeErrorMessage, type Logger } from '../../observability/logger.js';
import {
  RETAILER_WEBSITE_SCOPE,
  retailerWebsiteStoreForKey,
  type RetailerWebsiteStore,
} from './retailerWebsiteScope.js';
import {
  unavailableRetailerWebsiteResearchResult,
  type RetailerWebsiteResearchRequest,
  type RetailerWebsiteResearchResult,
  type RetailerWebsiteResearcher,
} from './retailerWebsiteResearcher.js';
import type { ShoppingListMutationService } from './shoppingListMutationService.js';

/**
 * Runs the durable, fixed-store website-research workflow created in Stages
 * 1–4. It intentionally knows nothing about retailer APIs: research is always
 * delegated through the constrained rendered-website boundary.
 */
export type StockPriceCheckService = {
  processRun: (runId: string) => Promise<ShoppingStockPriceCheckSummary | null>;
  resumeActiveRun: () => Promise<ShoppingStockPriceCheckSummary | null>;
};

export function createStockPriceCheckService(options: {
  stockPriceCheckStore: ShoppingStockPriceCheckStore;
  shoppingListMutationService: Pick<ShoppingListMutationService, 'applyStockPriceCheckListings'>;
  retailerWebsiteResearcher: RetailerWebsiteResearcher;
  logger?: Pick<Logger, 'error' | 'info' | 'warn'>;
  createMutationId?: () => string;
}): StockPriceCheckService {
  const createMutationId = options.createMutationId ?? crypto.randomUUID;

  const service: StockPriceCheckService = {
    async processRun(runId) {
      const claimed = await options.stockPriceCheckStore.claimRun(runId);
      if (!claimed || isTerminal(claimed)) return claimed;

      try {
        const items = await options.stockPriceCheckStore.fetchRunItems(runId);
        const pendingItems = items.filter((item) => item.status === 'pending');

        if (items.length > RETAILER_WEBSITE_SCOPE.policy.maxItemsPerJob) {
          await recordTooLargeRun(pendingItems);
          return completeRunFor(runId, 'failed', 'job_item_limit_exceeded', 'The saved job exceeds the fixed website-research item limit.');
        }

        await options.stockPriceCheckStore.updateRunPhase({ runId, phase: 'matching_products' });
        let sawIssue = false;

        for (const item of pendingItems) {
          const result = await processItem(item);
          sawIssue ||= result.hadIssue;
        }

        await options.stockPriceCheckStore.updateRunPhase({ runId, phase: 'applying_updates' });
        const finalItems = await options.stockPriceCheckStore.fetchRunItems(runId);
        const finalStatus = runTerminalStatus(finalItems, sawIssue);
        return completeRunFor(
          runId,
          finalStatus,
          finalStatus === 'failed' ? 'website_research_failed' : undefined,
          finalRunMessage(finalStatus),
        );
      } catch (error) {
        options.logger?.error('Shopping stock and price check crashed before completion.', {
          runId,
          error: safeErrorMessage(error),
        });
        return completeRunFor(runId, 'failed', 'stock_price_check_internal_error', 'The check stopped safely before all updates could be applied.');
      }
    },
    async resumeActiveRun() {
      const active = await options.stockPriceCheckStore.fetchActiveRun();
      return active ? service.processRun(active.id) : null;
    },
  };
  return service;

  async function processItem(item: ShoppingStockPriceCheckItemOutcome): Promise<{ hadIssue: boolean }> {
    if (!(await options.stockPriceCheckStore.isItemSnapshotCurrent(item.id))) {
      await recordOutcome(item, 'skipped_stale', [], 'item_snapshot_stale');
      return { hadIssue: true };
    }

    const storeOutcomes = await researchFixedStores(item);
    const failures = storeOutcomes.filter(isResearchFailure);
    const safeOutcomes = storeOutcomes.filter((outcome) => !isResearchFailure(outcome));

    if (safeOutcomes.length === 0) {
      await recordOutcome(item, 'failed', storeOutcomes, failures[0]?.failureCode ?? 'website_unavailable');
      return { hadIssue: true };
    }

    const managedListings = safeOutcomes.map((outcome) => managedListingFromOutcome(outcome));
    const storeListings = mergeManagedListings(item.item.storeListings, managedListings);
    const write = await options.shoppingListMutationService.applyStockPriceCheckListings(
      item.item.itemId,
      { expectedVersion: item.item.itemVersion, storeListings },
      createMutationId(),
    );

    if (write.status === 'stale') {
      await recordOutcome(item, 'skipped_stale', storeOutcomes, 'item_snapshot_stale');
      return { hadIssue: true };
    }

    const status: ShoppingStockPriceCheckItemOutcomeStatus = safeOutcomes.some((outcome) => outcome.matchStatus === 'matched')
      ? 'updated'
      : 'unmatched';
    await recordOutcome(item, status, storeOutcomes);
    return { hadIssue: failures.length > 0 || safeOutcomes.some((outcome) => outcome.matchStatus !== 'matched') };
  }

  async function researchFixedStores(item: ShoppingStockPriceCheckItemOutcome): Promise<ShoppingStockPriceCheckStoreOutcome[]> {
    const outcomes: ShoppingStockPriceCheckStoreOutcome[] = [];

    // Deliberately sequential: it keeps an individual job below the fixed
    // browser-navigation budget and makes interrupted runs deterministic.
    for (const store of RETAILER_WEBSITE_SCOPE.stores) {
      const request: RetailerWebsiteResearchRequest = { item: item.item, storeKey: store.key };
      try {
        const received = await options.retailerWebsiteResearcher.research(request);
        outcomes.push(normalizeResearchOutcome(request, received));
      } catch (error) {
        options.logger?.warn('Fixed-store website research failed for one store.', {
          runItemId: item.id,
          itemId: item.item.itemId,
          storeKey: store.key,
          error: safeErrorMessage(error),
        });
        outcomes.push(unavailableRetailerWebsiteResearchResult(request, 'website_unavailable'));
      }
    }

    return outcomes;
  }

  async function recordOutcome(
    item: ShoppingStockPriceCheckItemOutcome,
    status: Exclude<ShoppingStockPriceCheckItemOutcomeStatus, 'pending'>,
    storeOutcomes: ShoppingStockPriceCheckStoreOutcome[],
    failureCode?: string,
  ): Promise<void> {
    const recorded = await options.stockPriceCheckStore.recordItemOutcome({
      runItemId: item.id,
      status,
      storeOutcomes,
      ...(failureCode ? { failureCode } : {}),
    });
    if (!recorded) {
      throw new Error(`Shopping stock and price outcome was not recorded for ${item.id}.`);
    }
  }

  async function recordTooLargeRun(items: ShoppingStockPriceCheckItemOutcome[]): Promise<void> {
    for (const item of items) {
      const outcomes = RETAILER_WEBSITE_SCOPE.stores.map((store) => unavailableRetailerWebsiteResearchResult(
        { item: item.item, storeKey: store.key },
        'site_scope_unavailable',
      ));
      await recordOutcome(item, 'failed', outcomes, 'job_item_limit_exceeded');
    }
  }

  async function completeRunFor(
    runId: string,
    status: Extract<ShoppingStockPriceCheckSummary['status'], 'completed' | 'completed_with_issues' | 'failed'>,
    failureCode?: string,
    message?: string,
  ): Promise<ShoppingStockPriceCheckSummary | null> {
    return options.stockPriceCheckStore.completeRun({
      runId,
      status,
      ...(failureCode ? { failureCode } : {}),
      ...(message ? { message } : {}),
    });
  }
}

function normalizeResearchOutcome(
  request: RetailerWebsiteResearchRequest,
  received: RetailerWebsiteResearchResult,
): ShoppingStockPriceCheckStoreOutcome {
  const store = retailerWebsiteStoreForKey(request.storeKey);

  if (!isStoreOutcome(received) || !hasExpectedStoreIdentity(received, store) || !hasAllowedOutcomeShape(received)) {
    return unavailableRetailerWebsiteResearchResult(request, 'invalid_agent_result');
  }

  return received;
}

function isStoreOutcome(value: unknown): value is ShoppingStockPriceCheckStoreOutcome {
  if (!value || typeof value !== 'object') return false;
  const candidate = value as Record<string, unknown>;
  return Boolean(candidate.store) && typeof candidate.store === 'object'
    && 'availability' in candidate && 'matchStatus' in candidate;
}

function hasExpectedStoreIdentity(
  outcome: ShoppingStockPriceCheckStoreOutcome,
  expected: RetailerWebsiteStore,
): boolean {
  return outcome.store.storeId === expected.appStoreId
    && outcome.store.storeName === expected.appStoreName
    && outcome.store.source === expected.source
    && outcome.store.selectedStoreAddress === expected.address;
}

function hasAllowedOutcomeShape(outcome: ShoppingStockPriceCheckStoreOutcome): boolean {
  if (!['matched', 'no_match', 'ambiguous', 'website_error', 'store_unconfirmed', 'domain_scope_failure'].includes(outcome.matchStatus)) {
    return false;
  }
  if (!['in_stock', 'low_stock', 'out_of_stock', 'unknown'].includes(outcome.availability)) {
    return false;
  }
  if (typeof outcome.store.confirmed !== 'boolean') return false;
  if (outcome.matchStatus === 'matched') {
    return outcome.store.confirmed === true
      && Boolean(outcome.product && (outcome.product.name || outcome.product.productId || outcome.product.upc));
  }
  if (outcome.matchStatus === 'no_match' || outcome.matchStatus === 'ambiguous') {
    return outcome.store.confirmed === true && outcome.availability === 'unknown';
  }
  if (outcome.matchStatus === 'store_unconfirmed') {
    return outcome.store.confirmed === false && outcome.availability === 'unknown';
  }
  return outcome.availability === 'unknown';
}

function isResearchFailure(outcome: ShoppingStockPriceCheckStoreOutcome): boolean {
  return outcome.matchStatus === 'website_error' || outcome.matchStatus === 'domain_scope_failure';
}

function managedListingFromOutcome(outcome: ShoppingStockPriceCheckStoreOutcome): ShoppingItemStoreListing {
  const checkedAt = validCheckedAt(outcome.checkedAt) ?? new Date().toISOString();
  const base: ShoppingItemStoreListing = {
    storeId: outcome.store.storeId,
    storeName: outcome.store.storeName,
    source: outcome.store.source,
    selectedStoreAddress: outcome.store.selectedStoreAddress,
    availability: {
      status: outcome.availability,
      matchStatus: outcome.matchStatus,
      checkedAt,
    },
    checkedAt,
  };

  if (outcome.matchStatus !== 'matched') return base;

  return {
    ...base,
    ...(outcome.product ? { product: outcome.product } : {}),
    ...(outcome.aisle ? { aisle: outcome.aisle } : {}),
    ...(outcome.price ? { price: outcome.price } : {}),
  };
}

/** Replaces only a listing managed by this exact fixed retailer/store/address. */
export function mergeManagedListings(
  existing: ShoppingItemStoreListing[],
  replacements: ShoppingItemStoreListing[],
): ShoppingItemStoreListing[] {
  const managedKeys = new Set(replacements.map(managedListingKey));
  return [
    ...existing.filter((listing) => !managedKeys.has(managedListingKey(listing))),
    ...replacements,
  ];
}

function managedListingKey(listing: ShoppingItemStoreListing): string {
  return `${listing.storeId ?? ''}\u0000${listing.source ?? ''}\u0000${listing.selectedStoreAddress ?? ''}`;
}

function validCheckedAt(value: string | undefined): string | undefined {
  return value && Number.isFinite(Date.parse(value)) ? value : undefined;
}

function isTerminal(run: ShoppingStockPriceCheckSummary): boolean {
  return run.status === 'completed' || run.status === 'completed_with_issues' || run.status === 'failed';
}

function runTerminalStatus(
  items: ShoppingStockPriceCheckItemOutcome[],
  sawIssue: boolean,
): Extract<ShoppingStockPriceCheckSummary['status'], 'completed' | 'completed_with_issues' | 'failed'> {
  if (items.length > 0 && items.every((item) => item.status === 'failed')) return 'failed';
  if (sawIssue || items.some((item) => item.status !== 'updated')) return 'completed_with_issues';
  return 'completed';
}

function finalRunMessage(status: ShoppingStockPriceCheckSummary['status']): string | undefined {
  if (status === 'completed') return 'Stock and price listings were refreshed from the fixed retailer websites.';
  if (status === 'completed_with_issues') return 'Some listings need review; prior verified facts were retained where website research failed.';
  return 'No safe website listings could be applied.';
}
