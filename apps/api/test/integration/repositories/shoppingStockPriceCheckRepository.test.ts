import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';

import type {
  ShoppingStockPriceCheckStoreOutcome,
} from '../../../src/contracts.js';
import type { DatabaseQuery } from '../../../src/db/client.js';
import {
  createPostgresShoppingStockPriceCheckStore,
} from '../../../src/repositories/shoppingStockPriceCheckRepository.js';
import { createDisposableShoppingDatabase } from '../../support/pgliteDatabase.js';

async function seedShoppingItem(
  database: DatabaseQuery,
  options: { name: string; purchased?: boolean; version?: number; storeListings?: unknown[] },
): Promise<number> {
  const [row] = await database<{ id: number }>`
    INSERT INTO shopping_list (name, purchased, version, store_listings)
    VALUES (
      ${options.name},
      ${options.purchased ?? false},
      ${options.version ?? 1},
      ${JSON.stringify(options.storeListings ?? [])}::jsonb
    )
    RETURNING id
  `;

  assert.ok(row);
  return row.id;
}

function targetOutcome(): ShoppingStockPriceCheckStoreOutcome {
  return {
    store: {
      storeId: 1,
      storeName: 'Target',
      source: 'target.com',
      selectedStoreAddress: '1365 Sgt Jon Stiles Dr, Highlands Ranch, CO',
      confirmed: true,
    },
    availability: 'in_stock',
    matchStatus: 'matched',
    product: { name: 'Fixture milk' },
    price: { regular: 3.99 },
  };
}

function kingSoopersNoMatchOutcome(): ShoppingStockPriceCheckStoreOutcome {
  return {
    store: {
      storeId: 2,
      storeName: 'King Soopers',
      source: 'kingsoopers.com',
      selectedStoreAddress: '2205 W Wildcat Reserve Pkwy, Highlands Ranch, CO',
      confirmed: true,
    },
    availability: 'unknown',
    matchStatus: 'no_match',
  };
}

test('stock-price migration is repeatable and the repository persists immutable needed-item snapshots', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());

  const migrationURL = new URL(
    '../../../migrations/2026-08-01-001-shopping-stock-price-checks.sql',
    import.meta.url,
  );
  const migration = await readFile(migrationURL, 'utf8');
  await disposable.exec(migration);

  const milkId = await seedShoppingItem(disposable.database, {
    name: 'Milk',
    version: 7,
    storeListings: [{ storeId: 1, storeName: 'Target', price: { regular: 3.99 } }],
  });
  await seedShoppingItem(disposable.database, { name: 'Eggs', version: 4 });
  await seedShoppingItem(disposable.database, { name: 'Already picked up', purchased: true, version: 5 });

  const store = createPostgresShoppingStockPriceCheckStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  const requestId = randomUUID();
  const run = await store.createRun({ requestId, actor: 'Josh' });

  assert.equal(run.status, 'queued');
  assert.equal(run.phase, 'preparing');
  assert.equal(run.requestedItemCount, 2);
  assert.equal(run.processedItemCount, 0);
  assert.equal((await store.fetchRunByRequestId(requestId))?.id, run.id);

  const items = await store.fetchRunItems(run.id);
  assert.deepEqual(items.map((item) => ({
    itemId: item.item.itemId,
    version: item.item.itemVersion,
    name: item.item.name,
    status: item.status,
  })), [
    { itemId: milkId, version: 7, name: 'Milk', status: 'pending' },
    { itemId: milkId + 1, version: 4, name: 'Eggs', status: 'pending' },
  ]);
  assert.deepEqual(items[0]?.item.storeListings, [{ storeId: 1, storeName: 'Target', price: { regular: 3.99 } }]);
});

test('stock-price runs enforce one active job, transitions, durable counts, and terminal state', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  await seedShoppingItem(disposable.database, { name: 'Milk' });
  await seedShoppingItem(disposable.database, { name: 'Eggs' });
  const store = createPostgresShoppingStockPriceCheckStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });

  const run = await store.createRun({ requestId: randomUUID(), actor: 'Josh' });
  await assert.rejects(
    store.createRun({ requestId: randomUUID(), actor: 'Mallory' }),
    /shopping_stock_price_check_runs_one_active_idx|unique constraint/i,
  );
  assert.equal((await store.fetchActiveRun())?.id, run.id);
  assert.equal(await store.updateRunPhase({ runId: run.id, phase: 'matching_products' }), null);

  const claimed = await store.claimRun(run.id);
  assert.equal(claimed?.status, 'running');
  assert.equal(claimed?.phase, 'checking_stores');
  assert.ok(claimed?.startedAt);
  assert.equal((await store.updateRunPhase({ runId: run.id, phase: 'matching_products' }))?.phase, 'matching_products');

  const [first, second] = await store.fetchRunItems(run.id);
  assert.ok(first);
  assert.ok(second);
  const afterFirst = await store.recordItemOutcome({
    runItemId: first.id,
    status: 'updated',
    storeOutcomes: [targetOutcome()],
  });
  assert.deepEqual(
    [afterFirst?.processedItemCount, afterFirst?.updatedItemCount, afterFirst?.unmatchedItemCount],
    [1, 1, 0],
  );
  const afterSecond = await store.recordItemOutcome({
    runItemId: second.id,
    status: 'unmatched',
    storeOutcomes: [kingSoopersNoMatchOutcome()],
  });
  assert.deepEqual(
    [afterSecond?.processedItemCount, afterSecond?.updatedItemCount, afterSecond?.unmatchedItemCount],
    [2, 1, 1],
  );
  assert.equal(await store.recordItemOutcome({
    runItemId: second.id,
    status: 'failed',
    storeOutcomes: [],
    failureCode: 'website_unavailable',
  }), null);

  const completed = await store.completeRun({
    runId: run.id,
    status: 'completed_with_issues',
    message: 'One item needs review.',
  });
  assert.equal(completed?.status, 'completed_with_issues');
  assert.equal(completed?.phase, 'finished');
  assert.ok(completed?.finishedAt);
  assert.equal(await store.fetchActiveRun(), null);
  assert.equal(await store.completeRun({ runId: run.id, status: 'completed' }), null);
});

test('empty needed lists complete without creating an active job', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  await seedShoppingItem(disposable.database, { name: 'Already picked up', purchased: true });
  const store = createPostgresShoppingStockPriceCheckStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });

  const run = await store.createRun({ requestId: randomUUID() });

  assert.deepEqual(
    {
      status: run.status,
      phase: run.phase,
      requested: run.requestedItemCount,
      message: run.message,
    },
    {
      status: 'completed',
      phase: 'finished',
      requested: 0,
      message: 'No shopping items need a stock and price check.',
    },
  );
  assert.ok(run.startedAt);
  assert.ok(run.finishedAt);
  assert.deepEqual(await store.fetchRunItems(run.id), []);
  assert.equal(await store.fetchActiveRun(), null);
});

test('snapshot-current detection rejects a changed, picked-up, or deleted item', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  const itemId = await seedShoppingItem(disposable.database, { name: 'Milk', version: 3 });
  const store = createPostgresShoppingStockPriceCheckStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  const run = await store.createRun({ requestId: randomUUID() });
  const [snapshot] = await store.fetchRunItems(run.id);
  assert.ok(snapshot);
  assert.equal(await store.isItemSnapshotCurrent(snapshot.id), true);

  await disposable.database`
    UPDATE shopping_list SET version = 4 WHERE id = ${itemId}
  `;
  assert.equal(await store.isItemSnapshotCurrent(snapshot.id), false);

  await disposable.database`
    UPDATE shopping_list SET version = 3, purchased = true WHERE id = ${itemId}
  `;
  assert.equal(await store.isItemSnapshotCurrent(snapshot.id), false);

  await disposable.database`DELETE FROM shopping_list WHERE id = ${itemId}`;
  assert.equal(await store.isItemSnapshotCurrent(snapshot.id), false);
});
