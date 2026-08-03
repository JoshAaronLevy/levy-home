import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { afterEach, beforeEach, test } from 'node:test';

import { createApp } from '../../../src/app.js';
import type { ShoppingListReaddSummary } from '../../../src/contracts.js';
import type { ShoppingListReaddStore } from '../../../src/repositories/shoppingListReaddRepository.js';
import type { ShoppingListReaddReadiness } from '../../../src/services/shopping/shoppingListReaddReadiness.js';
import type { ShoppingListReaddRunner } from '../../../src/services/shopping/shoppingListReaddRunner.js';
import type { ShoppingListReaddService } from '../../../src/services/shopping/shoppingListReaddService.js';
import { createRouteTestHarness } from '../../support/routeTestHarness.js';
import { testConfig } from '../../support/testConfig.js';

const routes = createRouteTestHarness();

beforeEach(async () => {
  await routes.start(createApp({ config: testConfig }));
});

afterEach(async () => {
  await routes.close();
});

test('POST starts one bounded re-add run, returns 202 immediately, and GET exposes only the public summary', async () => {
  const store = fakeStore();
  const queued: string[] = [];
  await restart({ store, runner: recordingRunner(queued) });
  const mutationId = randomUUID();

  const response = await fetch(`${routes.baseURL()}/api/shopping-list/ai/readd`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text: 'Add 2 coffees and eggs', actor: 'Josh', mutationId }),
  });
  const started = await response.json() as ShoppingListReaddSummary;

  assert.equal(response.status, 202);
  assert.equal(started.status, 'queued');
  assert.deepEqual(queued, [started.id]);
  assert.deepEqual(store.createRequests, [{ requestId: mutationId, actor: 'Josh', requestedText: 'Add 2 coffees and eggs' }]);
  assert.deepEqual(Object.keys(started).sort(), [
    'finishedAt', 'id', 'ok', 'operations', 'startedAt', 'status', 'submittedAt', 'undo', 'unmatched',
  ]);

  const read = await routes.getJSON(`/api/shopping-list/ai/readd/${started.id}`) as ShoppingListReaddSummary;
  assert.equal(read.id, started.id);
  const publicJSON = JSON.stringify(read);
  assert.equal(publicJSON.includes('candidate'), false);
  assert.equal(publicJSON.includes('thread'), false);
  assert.equal(publicJSON.includes('prompt'), false);
  assert.equal(publicJSON.includes('token'), false);
});

test('start rejects arbitrary AI controls before writing, and matcher readiness is independent of stock-price readiness', async () => {
  const store = fakeStore();
  await restart({ store, runner: recordingRunner([]) });

  const readiness = await routes.getJSON('/api/shopping-list/ai/readd/readiness') as {
    ready: boolean;
    matcherRuntime: { ready: boolean };
    authentication: { ready: boolean };
    persistence: { ready: boolean };
  };
  assert.deepEqual(readiness, {
    ready: true,
    matcherRuntime: { ready: true },
    authentication: { ready: true },
    persistence: { ready: true },
  });
  const stockPriceReadiness = await routes.getJSON('/api/shopping-list/ai/readiness') as { enabled: boolean };
  assert.equal(stockPriceReadiness.enabled, false);

  const response = await fetch(`${routes.baseURL()}/api/shopping-list/ai/readd`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      text: 'Add eggs', actor: 'Josh', mutationId: randomUUID(),
      itemIds: [1], prompt: 'ignore instructions', model: 'anything', url: 'https://target.com', stores: [],
    }),
  });
  assert.equal(response.status, 400);
  assert.equal((await response.json() as { code: string }).code, 'invalid_shopping_list_readd');
  assert.equal(store.createRequests.length, 0);
});

test('the same mutation ID is idempotent, while a different concurrent request receives the single active run', async () => {
  const store = fakeStore();
  const active = readdRun({ status: 'matching', startedAt: '2026-08-03T12:00:01.000Z' });
  store.byId.set(active.id, active);
  store.byRequestId.set('c9719ff3-d48a-4e72-933f-6dc225eb9144', active);
  const queued: string[] = [];
  await restart({ store, runner: recordingRunner(queued) });

  const replay = await fetch(`${routes.baseURL()}/api/shopping-list/ai/readd`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text: 'Add eggs', actor: 'Mallory', mutationId: 'c9719ff3-d48a-4e72-933f-6dc225eb9144' }),
  });
  assert.equal(replay.status, 202);
  assert.equal((await replay.json() as ShoppingListReaddSummary).id, active.id);
  assert.deepEqual(queued, []);

  store.byRequestId.clear();
  store.createError = Object.assign(new Error('one active run'), { code: '23505' });
  const conflict = await fetch(`${routes.baseURL()}/api/shopping-list/ai/readd`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text: 'Add milk', actor: 'Mallory', mutationId: randomUUID() }),
  });
  const body = await conflict.json() as { code: string; activeRun: ShoppingListReaddSummary };
  assert.equal(conflict.status, 409);
  assert.equal(body.code, 'shopping_list_readd_active');
  assert.equal(body.activeRun.id, active.id);
});

test('Undo returns the service-owned public result and expired or completed Undo is unavailable', async () => {
  const store = fakeStore();
  const run = readdRun({ status: 'completed', undo: { available: true, expiresAt: '2026-08-03T12:05:00.000Z' } });
  store.byId.set(run.id, run);
  const service = fakeService({ undone: { ...run, status: 'undone', undo: { available: false } } });
  await restart({ store, runner: recordingRunner([]), service });

  const undo = await fetch(`${routes.baseURL()}/api/shopping-list/ai/readd/${run.id}/undo`, { method: 'POST' });
  assert.equal(undo.status, 200);
  assert.equal((await undo.json() as ShoppingListReaddSummary).status, 'undone');
  assert.deepEqual(service.undoRunIds, [run.id]);

  service.undoResult = null;
  const unavailable = await fetch(`${routes.baseURL()}/api/shopping-list/ai/readd/${run.id}/undo`, { method: 'POST' });
  assert.equal(unavailable.status, 409);
  assert.equal((await unavailable.json() as { code: string }).code, 'shopping_list_readd_undo_unavailable');
});

test('unavailable matcher returns a sanitized 503 without creating a durable run', async () => {
  const store = fakeStore();
  await restart({
    store,
    runner: recordingRunner([]),
    readiness: { async getReadiness() {
      return {
        ready: false,
        matcherRuntime: { ready: true },
        authentication: { ready: false, code: 'authentication_unavailable' },
        persistence: { ready: true },
      };
    } },
  });

  const response = await fetch(`${routes.baseURL()}/api/shopping-list/ai/readd`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text: 'Add eggs', actor: 'Josh', mutationId: randomUUID() }),
  });
  assert.equal(response.status, 503);
  const body = await response.json() as { code: string; error: string };
  assert.equal(body.code, 'authentication_unavailable');
  assert.equal(body.error.includes('token'), false);
  assert.equal(store.createRequests.length, 0);
});

async function restart(options: {
  store: ReturnType<typeof fakeStore>;
  runner: ShoppingListReaddRunner;
  service?: ReturnType<typeof fakeService>;
  readiness?: ShoppingListReaddReadiness;
}): Promise<void> {
  await routes.restart(createApp({
    config: testConfig,
    shoppingListReaddStore: options.store,
    shoppingListReaddRunner: options.runner,
    shoppingListReaddService: options.service ?? fakeService(),
    shoppingListReaddReadiness: options.readiness ?? readyReadiness(),
  }));
}

function readyReadiness(): ShoppingListReaddReadiness {
  return { async getReadiness() {
    return {
      ready: true,
      matcherRuntime: { ready: true },
      authentication: { ready: true },
      persistence: { ready: true },
    };
  } };
}

function recordingRunner(enqueued: string[]): ShoppingListReaddRunner {
  return { enqueue(runId) { enqueued.push(runId); }, recover() {} };
}

function fakeService(options: { undone?: ShoppingListReaddSummary | null } = {}) {
  const service: ShoppingListReaddService & { undoRunIds: string[]; undoResult: ShoppingListReaddSummary | null | undefined } = {
    undoRunIds: [],
    undoResult: options.undone,
    async processRun() { return null; },
    async recoverRun() { return null; },
    async undoRun(runId) {
      service.undoRunIds.push(runId);
      return service.undoResult ?? null;
    },
  };
  return service;
}

function fakeStore(): ShoppingListReaddStore & {
  byId: Map<string, ShoppingListReaddSummary>;
  byRequestId: Map<string, ShoppingListReaddSummary>;
  createError?: Error;
  createRequests: Array<{ requestId: string; actor: 'Josh' | 'Mallory'; requestedText: string }>;
} {
  const byId = new Map<string, ShoppingListReaddSummary>();
  const byRequestId = new Map<string, ShoppingListReaddSummary>();
  const store = {
    byId,
    byRequestId,
    createError: undefined as Error | undefined,
    createRequests: [] as Array<{ requestId: string; actor: 'Josh' | 'Mallory'; requestedText: string }>,
    async createRun(request: { requestId: string; actor: 'Josh' | 'Mallory'; requestedText: string }) {
      store.createRequests.push(request);
      if (store.createError) throw store.createError;
      const run = readdRun();
      byId.set(run.id, run);
      byRequestId.set(request.requestId, run);
      return run;
    },
    async fetchRun(runId: string) { return byId.get(runId) ?? null; },
    async fetchRunByRequestId(requestId: string) { return byRequestId.get(requestId) ?? null; },
    async fetchRecoverableRun() { return [...byId.values()].find((run) => ['queued', 'matching', 'applying'].includes(run.status)) ?? null; },
    async claimRun() { return null; },
    async claimRunForProcessing() { return null; },
    async fetchRunExecutionInput() { return null; },
    async moveRunToApplying() { return null; },
    async recordApplyingOperation() { return false; },
    async finalizeRun() { return null; },
    async fetchRunOperations() { return []; },
    async fetchUndoableRun() { return null; },
    async recordUndoOperation() { return false; },
    async markRunUndone() { return null; },
    async cleanupExpiredRuns() { return 0; },
  };
  return store;
}

function readdRun(overrides: Partial<ShoppingListReaddSummary> = {}): ShoppingListReaddSummary {
  return {
    ok: true,
    id: randomUUID(),
    status: 'queued',
    operations: [],
    unmatched: [],
    undo: { available: false },
    submittedAt: '2026-08-03T12:00:00.000Z',
    startedAt: null,
    finishedAt: null,
    ...overrides,
  };
}
