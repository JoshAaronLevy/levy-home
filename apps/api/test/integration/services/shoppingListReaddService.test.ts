import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { test } from 'node:test';

import type { ShoppingListReaddMatchPlan } from '../../../src/services/shopping/shoppingListReaddContracts.js';
import type { ShoppingListReaddMatcher } from '../../../src/services/shopping/shoppingListReaddMatcher.js';
import { createShoppingListReaddService } from '../../../src/services/shopping/shoppingListReaddService.js';
import { createPostgresShoppingListReaddStore } from '../../../src/repositories/shoppingListReaddRepository.js';
import { createPostgresShoppingListStore } from '../../../src/repositories/shoppingListRepository.js';
import { createPostgresShoppingTripStore } from '../../../src/repositories/shoppingTripRepository.js';
import { createShoppingListMutationService } from '../../../src/services/shopping/shoppingListMutationService.js';
import type { ShoppingListRealtimeBroadcaster, ShoppingListRealtimeSessionRecorder } from '../../../src/shoppingListRealtime.js';
import { createDisposableShoppingDatabase } from '../../support/pgliteDatabase.js';

test('re-add applies only picked-up matches through normal mutations, is idempotent, and broadcasts updates', async (t) => {
  const fixture = await createFixture(t, [
    { name: 'Iced Coffee', purchased: true, quantity: 1, version: 4 },
    { name: 'Eggs', purchased: true, quantity: 1, version: 6 },
  ]);
  const coffee = await fixture.listStore.findItemByName('Iced Coffee');
  const eggs = await fixture.listStore.findItemByName('Eggs');
  assert.ok(coffee && eggs);
  const run = await fixture.readdStore.createRun({ requestId: randomUUID(), actor: 'Josh', requestedText: 'Add 2 coffees and eggs' });
  const service = fixture.service(matcher({
    operations: [
      { requestIndex: 0, requestedText: '2 coffees', itemId: coffee.id, quantity: 2, matchKind: 'semantic' },
      { requestIndex: 1, requestedText: 'eggs', itemId: eggs.id, matchKind: 'exact' },
    ],
    unmatched: [],
  }));

  const completed = await service.processRun(run.id);
  assert.equal(completed?.status, 'completed');
  assert.equal(completed?.undo.available, true);
  assert.deepEqual(completed?.operations.map(({ outcome, itemName, quantity }) => ({ outcome, itemName, quantity })), [
    { outcome: 're_added', itemName: 'Iced Coffee', quantity: 2 },
    { outcome: 're_added', itemName: 'Eggs', quantity: undefined },
  ]);
  assert.deepEqual(
    { purchased: (await fixture.listStore.findItemByName('Iced Coffee'))?.purchased, quantity: (await fixture.listStore.findItemByName('Iced Coffee'))?.quantity },
    { purchased: false, quantity: 2 },
  );
  assert.equal((await fixture.listStore.findItemByName('Eggs'))?.purchased, false);
  assert.equal(fixture.broadcasts.length, 2);
  assert.equal(fixture.sessionRecords.length, 2);

  const replay = await service.processRun(run.id);
  assert.deepEqual(replay, completed);
  assert.equal(fixture.broadcasts.length, 2);
  const [coffeeOperation] = await fixture.readdStore.fetchRunOperations(run.id);
  assert.deepEqual(
    { snapshotVersion: coffeeOperation?.snapshotVersion, appliedVersion: coffeeOperation?.appliedVersion, undoStatus: coffeeOperation?.undoStatus },
    { snapshotVersion: 4, appliedVersion: 4, undoStatus: 'eligible' },
  );
});

test('already-needed items only change an explicitly different quantity, while unmatched phrases create no item', async (t) => {
  const fixture = await createFixture(t, [{ name: 'Iced Coffee', purchased: false, quantity: 1, version: 3 }]);
  const coffee = await fixture.listStore.findItemByName('Iced Coffee');
  assert.ok(coffee);
  const run = await fixture.readdStore.createRun({ requestId: randomUUID(), actor: 'Mallory', requestedText: 'Add 2 coffees and dragon fruit' });
  const completed = await fixture.service(matcher({
    operations: [{ requestIndex: 0, requestedText: '2 coffees', itemId: coffee.id, quantity: 2, matchKind: 'semantic' }],
    unmatched: [{ requestIndex: 1, requestedText: 'dragon fruit' }],
  })).processRun(run.id);

  assert.equal(completed?.status, 'completed_with_issues');
  assert.deepEqual(completed?.operations.map(({ outcome, quantity }) => ({ outcome, quantity })), [
    { outcome: 'quantity_updated', quantity: 2 },
    { outcome: 'unmatched', quantity: undefined },
  ]);
  assert.equal((await fixture.listStore.findItemByName('Iced Coffee'))?.quantity, 2);
  assert.equal(await fixture.listStore.findItemByName('Dragon fruit'), null);

  const noChangeRun = await fixture.readdStore.createRun({ requestId: randomUUID(), actor: 'Mallory', requestedText: 'Add coffee' });
  const noChange = await fixture.service(matcher({
    operations: [{ requestIndex: 0, requestedText: 'coffee', itemId: coffee.id, matchKind: 'semantic' }],
    unmatched: [],
  })).processRun(noChangeRun.id);
  assert.equal(noChange?.operations[0]?.outcome, 'already_needed');
  assert.equal(noChange?.undo.available, false);
});

test('a changed candidate is recorded as stale and never overwritten', async (t) => {
  const fixture = await createFixture(t, [{ name: 'Eggs', purchased: true, quantity: 1, version: 4 }]);
  const eggs = await fixture.listStore.findItemByName('Eggs');
  assert.ok(eggs);
  const run = await fixture.readdStore.createRun({ requestId: randomUUID(), actor: 'Josh', requestedText: 'Add eggs' });
  const completed = await fixture.service(matcher({
    operations: [{ requestIndex: 0, requestedText: 'eggs', itemId: eggs.id, matchKind: 'exact' }],
    unmatched: [],
  }, async () => {
    await fixture.disposable.database`UPDATE shopping_list SET purchased = false, quantity = 3, version = version + 1 WHERE id = ${eggs.id}`;
  })).processRun(run.id);

  assert.equal(completed?.status, 'completed_with_issues');
  assert.equal(completed?.operations[0]?.outcome, 'stale_skipped');
  assert.deepEqual(
    { purchased: (await fixture.listStore.findItemByName('Eggs'))?.purchased, quantity: (await fixture.listStore.findItemByName('Eggs'))?.quantity },
    { purchased: false, quantity: 3 },
  );
  assert.equal(fixture.broadcasts.length, 0);
});

test('a candidate deleted after matching is skipped safely', async (t) => {
  const fixture = await createFixture(t, [{ name: 'Milk', purchased: true, quantity: 1, version: 4 }]);
  const milk = await fixture.listStore.findItemByName('Milk');
  assert.ok(milk);
  const run = await fixture.readdStore.createRun({ requestId: randomUUID(), actor: 'Mallory', requestedText: 'Add milk' });
  const completed = await fixture.service(matcher({
    operations: [{ requestIndex: 0, requestedText: 'milk', itemId: milk.id, matchKind: 'exact' }],
    unmatched: [],
  }, async () => {
    await fixture.disposable.database`DELETE FROM shopping_list WHERE id = ${milk.id}`;
  })).processRun(run.id);

  assert.equal(completed?.operations[0]?.outcome, 'stale_skipped');
  assert.equal(await fixture.listStore.findItemByName('Milk'), null);
  assert.equal(fixture.broadcasts.length, 0);
});

test('Undo restores an unchanged AI update and safely skips a later manual edit, expiry, and repeat undo', async (t) => {
  const fixture = await createFixture(t, [{ name: 'Iced Coffee', purchased: true, quantity: 1, version: 7 }]);
  const coffee = await fixture.listStore.findItemByName('Iced Coffee');
  assert.ok(coffee);

  const restoredRun = await fixture.readdStore.createRun({ requestId: randomUUID(), actor: 'Josh', requestedText: 'Add 2 coffees' });
  const service = fixture.service(matcher({
    operations: [{ requestIndex: 0, requestedText: '2 coffees', itemId: coffee.id, quantity: 2, matchKind: 'semantic' }],
    unmatched: [],
  }));
  await service.processRun(restoredRun.id);
  const undone = await service.undoRun(restoredRun.id);
  assert.equal(undone?.status, 'undone');
  assert.deepEqual(
    { purchased: (await fixture.listStore.findItemByName('Iced Coffee'))?.purchased, quantity: (await fixture.listStore.findItemByName('Iced Coffee'))?.quantity },
    { purchased: true, quantity: 1 },
  );
  assert.equal(await service.undoRun(restoredRun.id), null);

  const changedRun = await fixture.readdStore.createRun({ requestId: randomUUID(), actor: 'Josh', requestedText: 'Add coffees' });
  await fixture.service(matcher({
    operations: [{ requestIndex: 0, requestedText: 'coffees', itemId: coffee.id, matchKind: 'semantic' }],
    unmatched: [],
  })).processRun(changedRun.id);
  await fixture.disposable.database`UPDATE shopping_list SET quantity = 3, version = version + 1 WHERE id = ${coffee.id}`;
  const skipped = await fixture.service(matcher({ operations: [], unmatched: [] })).undoRun(changedRun.id);
  assert.equal(skipped?.status, 'undone');
  assert.equal((await fixture.listStore.findItemByName('Iced Coffee'))?.quantity, 3);
  assert.equal((await fixture.readdStore.fetchRunOperations(changedRun.id))[0]?.undoStatus, 'skipped_stale');

  const expiredRun = await fixture.readdStore.createRun({ requestId: randomUUID(), actor: 'Josh', requestedText: 'Add coffees' });
  await fixture.service(matcher({
    operations: [{ requestIndex: 0, requestedText: 'coffees', itemId: coffee.id, matchKind: 'semantic' }],
    unmatched: [],
  })).processRun(expiredRun.id);
  await fixture.disposable.database`
    UPDATE shopping_ai_readd_runs
    SET undo_expires_at = now() - INTERVAL '1 second', purge_after = now() + INTERVAL '1 day'
    WHERE id = ${expiredRun.id}
  `;
  assert.equal(await fixture.service(matcher({ operations: [], unmatched: [] })).undoRun(expiredRun.id), null);
});

async function createFixture(
  t: { after: (callback: () => unknown) => void },
  items: Array<{ name: string; purchased: boolean; quantity: number; version: number }>,
) {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  for (const item of items) {
    await disposable.database`
      INSERT INTO shopping_list (name, purchased, quantity, version, store_listings)
      VALUES (${item.name}, ${item.purchased}, ${item.quantity}, ${item.version}, '[]'::jsonb)
    `;
  }

  const listStore = createPostgresShoppingListStore(disposable.database);
  const readdStore = createPostgresShoppingListReaddStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  const broadcasts: string[] = [];
  const sessionRecords: string[] = [];
  const mutationService = createShoppingListMutationService({
    logger: { debug() {}, error() {}, info() {}, warn() {} },
    shoppingListStore: listStore,
    shoppingListRealtime: realtime(broadcasts, sessionRecords),
    shoppingTripStore: createPostgresShoppingTripStore({
      database: disposable.database,
      transactionRunner: disposable.transactionRunner,
    }),
    transactionRunner: disposable.transactionRunner,
  });

  return {
    disposable,
    listStore,
    readdStore,
    broadcasts,
    sessionRecords,
    service: (readdMatcher: ShoppingListReaddMatcher) => createShoppingListReaddService({
      matcher: readdMatcher,
      shoppingListReaddStore: readdStore,
      shoppingListStore: listStore,
      shoppingListMutationService: mutationService,
      createMutationId: () => randomUUID(),
    }),
  };
}

function matcher(plan: ShoppingListReaddMatchPlan, beforeReturn?: () => Promise<void>): ShoppingListReaddMatcher {
  return {
    getReadiness: () => ({ runtime: { ready: true }, authentication: { ready: true } }),
    async match() {
      await beforeReturn?.();
      return plan;
    },
  };
}

function realtime(
  broadcasts: string[],
  sessionRecords: string[],
): ShoppingListRealtimeBroadcaster & Partial<ShoppingListRealtimeSessionRecorder> {
  return {
    broadcastItemCreated() {},
    broadcastItemUpdated(item, mutationId) { broadcasts.push(`${item.id}:${mutationId}`); },
    broadcastItemDeleted() {},
    broadcastStoresChanged() {},
    broadcastCategoriesChanged() {},
    broadcastTripStarted() {},
    broadcastTripUpdated() {},
    broadcastTripEnded() {},
    recordItemMutation(item, mutationId, action, actor) { sessionRecords.push(`${item.id}:${mutationId}:${action}:${actor}`); },
  };
}
