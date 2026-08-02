import { Router } from 'express';

import type {
  KrogerProductSearchResponse,
  ShoppingListItemLookupResponse,
  ShoppingListSnapshotResponse,
} from '../contracts.js';
import { asyncHandler } from '../http/asyncHandler.js';
import { HTTPError } from '../http/errors.js';
import type { Logger } from '../observability/logger.js';
import type { ShoppingStockPriceCheckStore } from '../repositories/shoppingStockPriceCheckRepository.js';
import type { ShoppingListMutationService } from '../services/shopping/shoppingListMutationService.js';
import type { ShoppingStockPriceCheckReadiness } from '../services/shopping/stockPriceCheckReadiness.js';
import type { StockPriceCheckRunner } from '../services/shopping/stockPriceCheckRunner.js';
import {
  mutationIdForRequest,
  readShoppingListItemId,
} from '../services/shopping/shoppingListMutationService.js';
import type { ShoppingListStore } from '../repositories/shoppingListRepository.js';
import type { ShoppingTripService } from '../services/shopping/shoppingTripService.js';
import {
  validateCreateShoppingListItemBody,
  validateDeleteShoppingListItemBody,
  validateShoppingListItemLookupQuery,
  validateShoppingProductSearchQuery,
  validateUpdateShoppingListItemBody,
} from '../validation/shoppingValidation.js';
import {
  readShoppingStockPriceCheckId,
  validateStartShoppingStockPriceCheckBody,
} from '../validation/shoppingStockPriceCheckValidation.js';

export type ShoppingListRouteDependencies = {
  krogerProductSearchRunner: (query?: string) => Promise<KrogerProductSearchResponse>;
  shoppingListMutationService: ShoppingListMutationService;
  shoppingListStore: ShoppingListStore;
  shoppingTripService?: ShoppingTripService;
  shoppingStockPriceCheckStore?: ShoppingStockPriceCheckStore;
  shoppingStockPriceCheckReadiness: ShoppingStockPriceCheckReadiness;
  stockPriceCheckRunner?: StockPriceCheckRunner;
  logger?: Pick<Logger, 'info'>;
};

export function createShoppingListRoutes(deps: ShoppingListRouteDependencies): Router {
  const router = Router();

  router.get('/api/shopping-list', asyncHandler(async (_req, res) => {
    const shoppingList = await deps.shoppingListStore.fetchShoppingList();

    const response: ShoppingListSnapshotResponse = {
      ok: true,
      ...shoppingList,
      activeTrip: await deps.shoppingTripService?.getActiveTrip() ?? null,
      generatedAt: new Date().toISOString(),
    };

    res.json(response);
  }));

  router.get('/api/shopping-list/items/lookup', asyncHandler(async (req, res) => {
    const query = validateShoppingListItemLookupQuery(req.query);
    const match = await deps.shoppingListStore.findItemByName(query);
    const response: ShoppingListItemLookupResponse = {
      ok: true,
      query,
      match,
    };

    res.json(response);
  }));

  router.get('/api/shopping-list/products/search', asyncHandler(async (req, res) => {
    const term = validateShoppingProductSearchQuery(req.query);
    const response = await deps.krogerProductSearchRunner(term);

    res.json(response);
  }));

  router.get('/api/shopping-list/ai/readiness', asyncHandler(async (_req, res) => {
    res.json(await deps.shoppingStockPriceCheckReadiness.getReadiness());
  }));

  router.get('/api/shopping-list/ai/stock-price-checks/:jobId', asyncHandler(async (req, res) => {
    const jobId = readShoppingStockPriceCheckId(req.params.jobId);
    const store = requireStockPriceCheckStore(deps);
    const run = await store.fetchRun(jobId);

    if (!run) {
      throw new HTTPError(404, 'Stock and price check was not found.', 'shopping_stock_price_check_not_found');
    }

    res.json(run);
  }));

  router.post('/api/shopping-list/ai/stock-price-checks', asyncHandler(async (req, res) => {
    const request = validateStartShoppingStockPriceCheckBody(req.body);
    const readiness = await deps.shoppingStockPriceCheckReadiness.getReadiness();

    if (!readiness.enabled) {
      throw stockPriceCheckUnavailableError(readiness);
    }

    const store = requireStockPriceCheckStore(deps);
    const runner = requireStockPriceCheckRunner(deps);
    const replay = await store.fetchRunByRequestId(request.mutationId);

    if (replay) {
      if (replay.status === 'queued' || replay.status === 'running') runner.enqueue(replay.id);
      res.status(202).json(replay);
      return;
    }

    try {
      const run = await store.createRun({ requestId: request.mutationId, actor: request.actor });
      deps.logger?.info('Shopping stock and price check queued.', {
        jobId: run.id,
        phase: run.phase,
        requestedItemCount: run.requestedItemCount,
      });
      if (run.status === 'queued' || run.status === 'running') runner.enqueue(run.id);
      res.status(202).json(run);
    } catch (error) {
      if (!isActiveRunConstraint(error)) throw error;
      const activeRun = await store.fetchActiveRun();
      if (!activeRun) throw error;

      res.status(409).json({
        error: 'A stock and price check is already in progress.',
        code: 'shopping_stock_price_check_active',
        activeJob: activeRun,
      });
    }
  }));

  router.post('/api/shopping-list/items', asyncHandler(async (req, res) => {
    const request = validateCreateShoppingListItemBody(req.body);
    const mutationId = mutationIdForRequest(req, request.mutationId);
    const response = await deps.shoppingListMutationService.createItem(request, mutationId);

    res.status(201).json(response);
  }));

  router.patch('/api/shopping-list/items/:itemId', asyncHandler(async (req, res) => {
    const itemId = readShoppingListItemId(req.params.itemId);
    const request = validateUpdateShoppingListItemBody(req.body);
    const mutationId = mutationIdForRequest(req, request.mutationId);
    const response = await deps.shoppingListMutationService.updateItem(itemId, request, mutationId);

    res.json(response);
  }));

  router.delete('/api/shopping-list/items/:itemId', asyncHandler(async (req, res) => {
    const itemId = readShoppingListItemId(req.params.itemId);
    const request = validateDeleteShoppingListItemBody(req.body);
    const mutationId = mutationIdForRequest(req, request.mutationId);
    const response = await deps.shoppingListMutationService.deleteItem(itemId, mutationId, request);

    res.json(response);
  }));

  return router;
}

function requireStockPriceCheckStore(deps: ShoppingListRouteDependencies): ShoppingStockPriceCheckStore {
  if (!deps.shoppingStockPriceCheckStore) {
    throw new HTTPError(503, 'Stock and price checks are not configured.', 'shopping_stock_price_check_not_configured');
  }
  return deps.shoppingStockPriceCheckStore;
}

function requireStockPriceCheckRunner(deps: ShoppingListRouteDependencies): StockPriceCheckRunner {
  if (!deps.stockPriceCheckRunner) {
    throw new HTTPError(503, 'Stock and price checks are not configured.', 'shopping_stock_price_check_not_configured');
  }
  return deps.stockPriceCheckRunner;
}

function stockPriceCheckUnavailableError(
  readiness: Awaited<ReturnType<ShoppingStockPriceCheckReadiness['getReadiness']>>,
): HTTPError {
  const code = readiness.checks.persistence.ok
    ? readiness.checks.codexRuntime.code ?? 'site_scope_unavailable'
    : readiness.checks.persistence.code ?? 'shopping_stock_price_check_not_configured';
  return new HTTPError(503, 'Stock and price checks are unavailable.', code);
}

function isActiveRunConstraint(error: unknown): boolean {
  return typeof error === 'object' && error !== null && (error as { code?: unknown }).code === '23505';
}
