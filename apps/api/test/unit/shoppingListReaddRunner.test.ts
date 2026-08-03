import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { ShoppingListReaddSummary } from '../../src/contracts.js';
import { createShoppingListReaddRunner } from '../../src/services/shopping/shoppingListReaddRunner.js';
import type { ShoppingListReaddService } from '../../src/services/shopping/shoppingListReaddService.js';

test('runner de-duplicates local work, keeps request text out of logs, and safely invokes restart recovery once', async () => {
  const scheduled: Array<() => void> = [];
  const info: Array<Record<string, unknown>> = [];
  const processRunIds: string[] = [];
  const recoverRunIds: string[] = [];
  const service: ShoppingListReaddService = {
    async processRun(runId) { processRunIds.push(runId); return run({ id: runId }); },
    async recoverRun(runId) { recoverRunIds.push(runId); return run({ id: runId, status: 'failed' }); },
    async undoRun() { return null; },
  };
  const runner = createShoppingListReaddRunner({
    shoppingListReaddService: service,
    logger: {
      info(_message, details) { info.push(details ?? {}); },
      error() {},
    },
    fetchRecoverableRun: async () => ({ id: 'restart-run' }),
    schedule(task) { scheduled.push(task); },
    now: () => 100,
  });

  runner.enqueue('run-1');
  runner.enqueue('run-1');
  assert.equal(scheduled.length, 1);
  scheduled.shift()?.();
  await tick();
  assert.deepEqual(processRunIds, ['run-1']);

  runner.recover();
  assert.equal(scheduled.length, 1);
  scheduled.shift()?.();
  await tick();
  assert.deepEqual(recoverRunIds, ['restart-run']);
  assert.equal(JSON.stringify(info).includes('Add eggs and private note'), false);
  assert.ok(info.some((entry) => entry.runId === 'restart-run' && entry.phase === 'recovery'));
});

function run(overrides: Partial<ShoppingListReaddSummary> = {}): ShoppingListReaddSummary {
  return {
    ok: true,
    id: 'run-1',
    status: 'completed',
    operations: [{ requestIndex: 0, requestedText: 'Add eggs and private note', outcome: 'unmatched' }],
    unmatched: [{ requestIndex: 0, requestedText: 'Add eggs and private note' }],
    undo: { available: false },
    submittedAt: '2026-08-03T12:00:00.000Z',
    startedAt: '2026-08-03T12:00:01.000Z',
    finishedAt: '2026-08-03T12:00:02.000Z',
    ...overrides,
  };
}

async function tick(): Promise<void> {
  await new Promise((resolve) => setImmediate(resolve));
}
