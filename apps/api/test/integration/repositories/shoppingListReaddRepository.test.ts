import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';

import type { DatabaseQuery } from '../../../src/db/client.js';
import {
  createPostgresShoppingListReaddStore,
} from '../../../src/repositories/shoppingListReaddRepository.js';
import { createDisposableShoppingDatabase } from '../../support/pgliteDatabase.js';

async function seedShoppingItem(database: DatabaseQuery, name: string): Promise<number> {
  const [row] = await database<{ id: number }>`
    INSERT INTO shopping_list (name, purchased, quantity, version)
    VALUES (${name}, true, 1, 4)
    RETURNING id
  `;
  assert.ok(row);
  return row.id;
}

test('AI re-add migration is repeatable and runs are durable, idempotent, bounded, and queryable', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  const migration = await readFile(
    new URL('../../../migrations/2026-08-02-001-shopping-ai-readd-runs.sql', import.meta.url),
    'utf8',
  );
  await disposable.exec(migration);

  const coffeeId = await seedShoppingItem(disposable.database, 'Iced Coffee');
  const store = createPostgresShoppingListReaddStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  const requestId = randomUUID();
  const run = await store.createRun({
    requestId,
    actor: 'Josh',
    requestedText: ' Add 2 coffees and dragonfruit ',
  });

  assert.equal(run.status, 'queued');
  assert.deepEqual(run.operations, []);
  assert.equal((await store.fetchRunByRequestId(requestId))?.id, run.id);
  await assert.rejects(
    store.createRun({ requestId, actor: 'Josh', requestedText: 'Add coffee again' }),
    /unique constraint|duplicate key/i,
  );
  assert.equal(await store.moveRunToApplying(run.id), null);

  assert.equal((await store.claimRun(run.id))?.status, 'matching');
  assert.equal((await store.moveRunToApplying(run.id))?.status, 'applying');
  const completed = await store.finalizeRun({
    runId: run.id,
    status: 'completed_with_issues',
    undoExpiresAt: new Date(Date.now() + 5 * 60_000),
    operations: [
      {
        requestIndex: 0,
        requestedText: '2 coffees',
        outcome: 're_added',
        itemId: coffeeId,
        itemName: 'Iced Coffee',
        quantity: 2,
        matchKind: 'semantic',
        snapshotVersion: 4,
        priorPurchased: true,
        priorQuantity: 1,
        appliedPurchased: false,
        appliedQuantity: 2,
        appliedVersion: 5,
        undoEligible: true,
      },
      {
        requestIndex: 1,
        requestedText: 'dragonfruit',
        outcome: 'unmatched',
      },
    ],
  });

  assert.equal(completed?.status, 'completed_with_issues');
  assert.equal(completed?.undo.available, true);
  assert.deepEqual(completed?.operations.map((operation) => operation.itemName), ['Iced Coffee', undefined]);
  assert.deepEqual(completed?.unmatched, [{ requestIndex: 1, requestedText: 'dragonfruit' }]);
  assert.equal(await store.finalizeRun({ runId: run.id, status: 'completed', operations: [] }), null);

  const operations = await store.fetchRunOperations(run.id);
  assert.deepEqual(operations.map((operation) => ({
    requestIndex: operation.requestIndex,
    itemId: operation.itemId,
    snapshotVersion: operation.snapshotVersion,
    priorPurchased: operation.priorPurchased,
    priorQuantity: operation.priorQuantity,
    appliedPurchased: operation.appliedPurchased,
    appliedQuantity: operation.appliedQuantity,
    appliedVersion: operation.appliedVersion,
    undoStatus: operation.undoStatus,
  })), [
    {
      requestIndex: 0,
      itemId: coffeeId,
      snapshotVersion: 4,
      priorPurchased: true,
      priorQuantity: 1,
      appliedPurchased: false,
      appliedQuantity: 2,
      appliedVersion: 5,
      undoStatus: 'eligible',
    },
    {
      requestIndex: 1,
      itemId: undefined,
      snapshotVersion: undefined,
      priorPurchased: undefined,
      priorQuantity: undefined,
      appliedPurchased: undefined,
      appliedQuantity: undefined,
      appliedVersion: undefined,
      undoStatus: 'not_eligible',
    },
  ]);

  const undoRun = await store.fetchUndoableRun(run.id);
  assert.equal(undoRun?.actor, 'Josh');
  assert.equal(undoRun?.operations.filter((operation) => operation.undoStatus === 'eligible').length, 1);
  assert.equal(await store.markRunUndone(run.id), null);
  assert.equal(await store.recordUndoOperation({ operationId: operations[0]!.id, status: 'reverted' }), true);
  assert.equal((await store.markRunUndone(run.id))?.status, 'undone');
  assert.equal(await store.markRunUndone(run.id), null);
});

test('AI re-add persistence rejects unsafe operation records, expires Undo, and cleans only its own history', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  const store = createPostgresShoppingListReaddStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  const preservedShoppingItemId = await seedShoppingItem(disposable.database, 'Eggs');
  const run = await store.createRun({ requestId: randomUUID(), actor: 'Mallory', requestedText: 'Add eggs' });
  await store.claimRun(run.id);

  await assert.rejects(
    store.finalizeRun({
      runId: run.id,
      status: 'completed',
      operations: [
        { requestIndex: 0, requestedText: 'eggs', outcome: 're_added', itemId: preservedShoppingItemId },
        { requestIndex: 0, requestedText: 'eggs again', outcome: 're_added', itemId: preservedShoppingItemId + 1 },
      ],
    }),
    /requestIndex|duplicate target/i,
  );

  const completed = await store.finalizeRun({
    runId: run.id,
    status: 'completed',
    undoExpiresAt: new Date(Date.now() + 5 * 60_000),
    operations: [{
      requestIndex: 0,
      requestedText: 'eggs',
      outcome: 're_added',
      itemId: preservedShoppingItemId,
      itemName: 'Eggs',
      snapshotVersion: 4,
      priorPurchased: true,
      priorQuantity: 1,
      appliedPurchased: false,
      appliedQuantity: 1,
      appliedVersion: 5,
      undoEligible: true,
    }],
  });
  assert.equal(completed?.undo.available, true);

  await disposable.database`
    UPDATE shopping_ai_readd_runs
    SET undo_expires_at = now() - INTERVAL '1 second', purge_after = now() + INTERVAL '1 day'
    WHERE id = ${run.id}
  `;
  assert.equal(await store.fetchUndoableRun(run.id), null);
  const [operation] = await store.fetchRunOperations(run.id);
  assert.ok(operation);
  assert.equal(await store.recordUndoOperation({ operationId: operation.id, status: 'reverted' }), false);

  await disposable.database`
    UPDATE shopping_ai_readd_runs
    SET purge_after = now() - INTERVAL '1 second'
    WHERE id = ${run.id}
  `;
  assert.equal(await store.cleanupExpiredRuns(), 1);
  assert.equal(await store.fetchRun(run.id), null);
  const [preserved] = await disposable.database<{ id: number }>`
    SELECT id FROM shopping_list WHERE id = ${preservedShoppingItemId}
  `;
  assert.equal(preserved?.id, preservedShoppingItemId);

  const columns = await disposable.database<{ columnName: string }>`
    SELECT column_name AS "columnName"
    FROM information_schema.columns
    WHERE table_name IN ('shopping_ai_readd_runs', 'shopping_ai_readd_operations')
  `;
  const columnNames = new Set(columns.map((column) => column.columnName));
  for (const forbidden of ['prompt', 'raw_model_text', 'raw_response', 'thread_id', 'token', 'cookie', 'website_data', 'credential']) {
    assert.equal(columnNames.has(forbidden), false);
  }
});

test('AI re-add persistence permits only one active run and exposes it for restart recovery', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  const store = createPostgresShoppingListReaddStore({
    database: disposable.database,
    transactionRunner: disposable.transactionRunner,
  });
  const first = await store.createRun({ requestId: randomUUID(), actor: 'Josh', requestedText: 'Add eggs' });
  assert.equal((await store.fetchRecoverableRun())?.id, first.id);
  await assert.rejects(
    store.createRun({ requestId: randomUUID(), actor: 'Mallory', requestedText: 'Add milk' }),
    /unique constraint|duplicate key/i,
  );

  await store.claimRun(first.id);
  assert.equal((await store.fetchRecoverableRun())?.status, 'matching');
  await store.finalizeRun({
    runId: first.id,
    status: 'failed',
    operations: [{ requestIndex: 0, requestedText: 'eggs', outcome: 'unavailable' }],
  });
  assert.equal(await store.fetchRecoverableRun(), null);
  assert.equal((await store.createRun({ requestId: randomUUID(), actor: 'Mallory', requestedText: 'Add milk' })).status, 'queued');
});
