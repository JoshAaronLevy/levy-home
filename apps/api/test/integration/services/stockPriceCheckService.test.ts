import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { test } from 'node:test';

import type {
  ShoppingStockPriceCheckItemSnapshot,
  ShoppingStockPriceCheckStoreOutcome,
} from '../../../src/contracts.js';
import { createPostgresShoppingListStore } from '../../../src/repositories/shoppingListRepository.js';
import { createPostgresShoppingStockPriceCheckStore } from '../../../src/repositories/shoppingStockPriceCheckRepository.js';
import { createPostgresShoppingTripStore } from '../../../src/repositories/shoppingTripRepository.js';
import { createShoppingListMutationService } from '../../../src/services/shopping/shoppingListMutationService.js';
import { createStockPriceCheckService } from '../../../src/services/shopping/stockPriceCheckService.js';
import { RETAILER_WEBSITE_SCOPE, type RetailerWebsiteStoreKey } from '../../../src/services/shopping/retailerWebsiteScope.js';
import type { RetailerWebsiteResearcher } from '../../../src/services/shopping/retailerWebsiteResearcher.js';
import type {
  ShoppingListRealtimeBroadcaster,
  ShoppingListRealtimeSessionRecorder,
} from '../../../src/shoppingListRealtime.js';
import { createDisposableShoppingDatabase } from '../../support/pgliteDatabase.js';

const targetAddress = '1365 Sgt Jon Stiles Dr, Highlands Ranch, CO';
const kingSoopersAddress = '2205 W Wildcat Reserve Pkwy, Highlands Ranch, CO';

test('a durable check replaces only fixed-store listings, preserves manual data, and broadcasts without session pushes', async (t) => {
  const setup = await createServiceFixture(t, [
    {
      name: 'Milk', brand: 'Store brand', quantity: 2, notes: 'Whole', categoryId: 8, image: 'milk.png',
      storeListings: [
        { storeId: 1, storeName: 'Target', source: 'manual', price: { regular: 9.99 } },
        { storeId: 1, storeName: 'Target', source: 'target.com', selectedStoreAddress: targetAddress, price: { regular: 1.11 } },
        { storeId: 2, storeName: 'King Soopers', source: 'kingsoopers.com', selectedStoreAddress: kingSoopersAddress, price: { regular: 2.22 } },
      ],
    },
  ]);
  const run = await setup.stockStore.createRun({ requestId: randomUUID(), actor: 'Josh' });
  const calls: RetailerWebsiteStoreKey[] = [];
  const service = setup.service(researcher((request) => {
    calls.push(request.storeKey);
    return request.storeKey === 'target_highlands_ranch'
      ? matchedTarget()
      : noMatchKingSoopers();
  }));

  const completed = await service.processRun(run.id);
  assert.equal(completed?.status, 'completed_with_issues');
  assert.deepEqual(
    [completed?.processedItemCount, completed?.updatedItemCount, completed?.unmatchedItemCount, completed?.failedItemCount],
    [1, 1, 0, 0],
  );
  assert.deepEqual(calls, ['target_highlands_ranch', 'king_soopers_wildcat_reserve']);

  const milk = await setup.listStore.findItemByName('Milk');
  assert.ok(milk);
  assert.deepEqual(
    { brand: milk.brand, quantity: milk.quantity, notes: milk.notes, categoryId: milk.categoryId, image: milk.image, purchased: milk.purchased },
    { brand: 'Store brand', quantity: 2, notes: 'Whole', categoryId: 8, image: 'milk.png', purchased: false },
  );
  assert.deepEqual(milk.storeListings.find((listing) => listing.source === 'manual')?.price, { regular: 9.99 });
  const target = milk.storeListings.find((listing) => listing.source === 'target.com');
  assert.equal(target?.price?.regular, 3.49);
  assert.equal(target?.availability?.status, 'in_stock');
  const kingSoopers = milk.storeListings.find((listing) => listing.source === 'kingsoopers.com');
  assert.deepEqual(kingSoopers, {
    storeId: 2,
    storeName: 'King Soopers',
    source: 'kingsoopers.com',
    selectedStoreAddress: kingSoopersAddress,
    availability: {
      status: 'unknown',
      matchStatus: 'no_match',
      checkedAt: kingSoopers?.checkedAt,
    },
    checkedAt: kingSoopers?.checkedAt,
  });
  assert.equal(setup.itemUpdated.length, 1);
  assert.equal(setup.sessionRecords.length, 0);

  const [outcome] = await setup.stockStore.fetchRunItems(run.id);
  assert.equal(outcome?.status, 'updated');
  assert.deepEqual(outcome?.storeOutcomes.map((entry) => entry.store.source), ['target.com', 'kingsoopers.com']);
});

test('domain-scope-rejected or malformed store research leaves previous verified listings untouched and records a failed durable run', async (t) => {
  const previousTargetListing = {
    storeId: 1, storeName: 'Target', source: 'target.com', selectedStoreAddress: targetAddress,
    product: { name: 'Prior exact product' }, price: { regular: 4.25 },
  };
  const setup = await createServiceFixture(t, [{ name: 'Eggs', storeListings: [previousTargetListing] }]);
  const run = await setup.stockStore.createRun({ requestId: randomUUID() });
  const service = setup.service(researcher((request) => request.storeKey === 'target_highlands_ranch'
    ? { ...websiteFailure('target_highlands_ranch'), matchStatus: 'domain_scope_failure', failureCode: 'site_scope_unavailable' }
    : ({ store: { ...noMatchKingSoopers().store, source: 'not-allowed.example' }, availability: 'unknown', matchStatus: 'no_match' } as never)));

  const completed = await service.processRun(run.id);
  assert.equal(completed?.status, 'failed');
  assert.equal((await setup.listStore.findItemByName('Eggs'))?.storeListings[0]?.price?.regular, 4.25);
  assert.equal(setup.itemUpdated.length, 0);
  const [outcome] = await setup.stockStore.fetchRunItems(run.id);
  assert.equal(outcome?.status, 'failed');
  assert.deepEqual(outcome?.storeOutcomes.map((entry) => entry.matchStatus), ['domain_scope_failure', 'website_error']);
  assert.deepEqual(outcome?.storeOutcomes.map((entry) => entry.failureCode), ['site_scope_unavailable', 'invalid_agent_result']);
});

test('a changed item is skipped safely and an active run can be deterministically resumed', async (t) => {
  const setup = await createServiceFixture(t, [{ name: 'Bread', storeListings: [] }]);
  const run = await setup.stockStore.createRun({ requestId: randomUUID() });
  let changed = false;
  const staleService = setup.service(researcher(async (request) => {
    if (!changed) {
      changed = true;
      await setup.disposable.database`UPDATE shopping_list SET version = version + 1, notes = 'Changed while checking' WHERE id = ${request.item.itemId}`;
    }
    return request.storeKey === 'target_highlands_ranch' ? matchedTarget() : noMatchKingSoopers();
  }));

  const completed = await staleService.processRun(run.id);
  assert.equal(completed?.status, 'completed_with_issues');
  assert.equal(completed?.skippedStaleItemCount, 1);
  assert.equal(setup.itemUpdated.length, 0);
  assert.equal((await setup.listStore.findItemByName('Bread'))?.notes, 'Changed while checking');

  const runToResume = await setup.stockStore.createRun({ requestId: randomUUID() });
  const resumed = await setup.service(researcher((request) => request.storeKey === 'target_highlands_ranch'
    ? matchedTarget()
    : noMatchKingSoopers())).resumeActiveRun();
  assert.equal(resumed?.id, runToResume.id);
  assert.equal(resumed?.status, 'completed_with_issues');
});

async function createServiceFixture(
  t: { after: (callback: () => unknown) => void },
  items: Array<{
    name: string;
    brand?: string;
    quantity?: number;
    notes?: string;
    categoryId?: number | null;
    image?: string;
    storeListings: unknown[];
  }>,
) {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  for (const item of items) {
    await disposable.database`
      INSERT INTO shopping_list (name, brand, quantity, notes, category_id, image, purchased, store_listings)
      VALUES (
        ${item.name}, ${item.brand ?? null}, ${item.quantity ?? 1}, ${item.notes ?? null},
        ${JSON.stringify(item.categoryId ?? null)}::jsonb, ${item.image ?? null}, false,
        ${JSON.stringify(item.storeListings)}::jsonb
      )
    `;
  }
  const listStore = createPostgresShoppingListStore(disposable.database);
  const stockStore = createPostgresShoppingStockPriceCheckStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  const itemUpdated: string[] = [];
  const sessionRecords: string[] = [];
  const realtime = recordingRealtime(itemUpdated, sessionRecords);
  const mutationService = createShoppingListMutationService({
    logger: silentLogger,
    shoppingListStore: listStore,
    shoppingListRealtime: realtime,
    shoppingTripStore: createPostgresShoppingTripStore({
      database: disposable.database,
      transactionRunner: disposable.transactionRunner,
    }),
    transactionRunner: disposable.transactionRunner,
  });

  return {
    disposable,
    listStore,
    stockStore,
    itemUpdated,
    sessionRecords,
    service: (retailerWebsiteResearcher: RetailerWebsiteResearcher) => createStockPriceCheckService({
      stockPriceCheckStore: stockStore,
      shoppingListMutationService: mutationService,
      retailerWebsiteResearcher,
      logger: silentLogger,
      createMutationId: () => 'stock-check-mutation',
    }),
  };
}

function researcher(
  handler: (request: { item: ShoppingStockPriceCheckItemSnapshot; storeKey: RetailerWebsiteStoreKey }) => Promise<ShoppingStockPriceCheckStoreOutcome> | ShoppingStockPriceCheckStoreOutcome,
): RetailerWebsiteResearcher {
  return { scope: RETAILER_WEBSITE_SCOPE, async research(request) { return handler(request); } };
}

function matchedTarget(): ShoppingStockPriceCheckStoreOutcome {
  return {
    store: { storeId: 1, storeName: 'Target', source: 'target.com', selectedStoreAddress: targetAddress, confirmed: true },
    availability: 'in_stock',
    matchStatus: 'matched',
    product: { productId: 'fixture-milk', name: 'Fixture whole milk' },
    aisle: { display: 'A12' },
    price: { regular: 3.49 },
  };
}

function noMatchKingSoopers(): ShoppingStockPriceCheckStoreOutcome {
  return {
    store: { storeId: 2, storeName: 'King Soopers', source: 'kingsoopers.com', selectedStoreAddress: kingSoopersAddress, confirmed: true },
    availability: 'unknown',
    matchStatus: 'no_match',
  };
}

function websiteFailure(key: RetailerWebsiteStoreKey): ShoppingStockPriceCheckStoreOutcome {
  const target = key === 'target_highlands_ranch';
  return {
    store: target
      ? { storeId: 1, storeName: 'Target', source: 'target.com', selectedStoreAddress: targetAddress, confirmed: false }
      : { storeId: 2, storeName: 'King Soopers', source: 'kingsoopers.com', selectedStoreAddress: kingSoopersAddress, confirmed: false },
    availability: 'unknown',
    matchStatus: 'website_error',
    failureCode: 'website_unavailable',
  };
}

const silentLogger = { debug() {}, error() {}, info() {}, warn() {} };

function recordingRealtime(itemUpdated: string[], sessionRecords: string[]): ShoppingListRealtimeBroadcaster & Partial<ShoppingListRealtimeSessionRecorder> {
  return {
    broadcastItemCreated() {},
    broadcastItemUpdated(item, mutationId) { itemUpdated.push(`${item.id}:${mutationId}`); },
    broadcastItemDeleted() {},
    broadcastStoresChanged() {},
    broadcastCategoriesChanged() {},
    broadcastTripStarted() {},
    broadcastTripUpdated() {},
    broadcastTripEnded() {},
    recordItemMutation(item, mutationId) { sessionRecords.push(`${item.id}:${mutationId}`); },
  };
}
