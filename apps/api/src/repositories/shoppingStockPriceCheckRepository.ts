import type {
  ShoppingListItem,
  ShoppingStockPriceCheckItemOutcome,
  ShoppingStockPriceCheckItemOutcomeStatus,
  ShoppingStockPriceCheckItemSnapshot,
  ShoppingStockPriceCheckPhase,
  ShoppingStockPriceCheckStatus,
  ShoppingStockPriceCheckStoreOutcome,
  ShoppingStockPriceCheckSummary,
} from '../contracts.js';
import {
  getDatabaseClient,
  getDatabaseTransactionRunner,
  type DatabaseQuery,
  type DatabaseTransactionRunner,
} from '../db/client.js';
import {
  jsonb,
  optionalISOString,
  optionalInteger,
  optionalString,
  parseJSONBValue,
  requiredInteger,
  requiredString,
} from '../db/rowReaders.js';
import { fetchNeededShoppingListItems } from './shoppingListRepository.js';

export type ShoppingStockPriceCheckStore = {
  createRun: (request: CreateShoppingStockPriceCheckRunRequest) => Promise<ShoppingStockPriceCheckSummary>;
  fetchRun: (runId: string) => Promise<ShoppingStockPriceCheckSummary | null>;
  fetchActiveRun: () => Promise<ShoppingStockPriceCheckSummary | null>;
  fetchRunByRequestId: (requestId: string) => Promise<ShoppingStockPriceCheckSummary | null>;
  fetchRunItems: (runId: string) => Promise<ShoppingStockPriceCheckItemOutcome[]>;
  claimRun: (runId: string) => Promise<ShoppingStockPriceCheckSummary | null>;
  updateRunPhase: (
    request: UpdateShoppingStockPriceCheckRunPhaseRequest,
  ) => Promise<ShoppingStockPriceCheckSummary | null>;
  recordItemOutcome: (
    request: RecordShoppingStockPriceCheckItemOutcomeRequest,
  ) => Promise<ShoppingStockPriceCheckSummary | null>;
  completeRun: (
    request: CompleteShoppingStockPriceCheckRunRequest,
  ) => Promise<ShoppingStockPriceCheckSummary | null>;
  isItemSnapshotCurrent: (runItemId: string) => Promise<boolean>;
};

export type CreateShoppingStockPriceCheckRunRequest = {
  requestId: string;
  actor?: string;
};

export type UpdateShoppingStockPriceCheckRunPhaseRequest = {
  runId: string;
  phase: Exclude<ShoppingStockPriceCheckPhase, 'preparing' | 'finished'>;
};

export type RecordShoppingStockPriceCheckItemOutcomeRequest = {
  runItemId: string;
  status: Exclude<ShoppingStockPriceCheckItemOutcomeStatus, 'pending'>;
  storeOutcomes: ShoppingStockPriceCheckStoreOutcome[];
  failureCode?: string;
};

export type CompleteShoppingStockPriceCheckRunRequest = {
  runId: string;
  status: Extract<ShoppingStockPriceCheckStatus, 'completed' | 'completed_with_issues' | 'failed'>;
  failureCode?: string;
  message?: string;
};

type ShoppingStockPriceCheckRunRow = Record<string, unknown> & {
  id: unknown;
  status: unknown;
  phase: unknown;
  requestedItemCount: unknown;
  processedItemCount: unknown;
  updatedItemCount: unknown;
  unmatchedItemCount: unknown;
  failedItemCount: unknown;
  skippedStaleItemCount: unknown;
  submittedAt: unknown;
  startedAt: unknown;
  finishedAt: unknown;
  failureCode: unknown;
  message: unknown;
};

type ShoppingStockPriceCheckItemRow = Record<string, unknown> & {
  id: unknown;
  runId: unknown;
  shoppingItemId: unknown;
  itemVersion: unknown;
  itemSnapshot: unknown;
  status: unknown;
  storeOutcomes: unknown;
  failureCode: unknown;
  createdAt: unknown;
  updatedAt: unknown;
};

export function createPostgresShoppingStockPriceCheckStore(options: {
  database?: DatabaseQuery;
  transactionRunner?: DatabaseTransactionRunner;
} = {}): ShoppingStockPriceCheckStore {
  if (Boolean(options.database) !== Boolean(options.transactionRunner)) {
    throw new Error('database and transactionRunner must be injected together.');
  }

  const query = () => options.database ?? getDatabaseClient();
  const transaction = () => options.transactionRunner ?? getDatabaseTransactionRunner();

  return {
    createRun: (request) => transaction()((database) => createShoppingStockPriceCheckRun(database, request)),
    fetchRun: (runId) => fetchShoppingStockPriceCheckRun(query(), runId),
    fetchActiveRun: () => fetchActiveShoppingStockPriceCheckRun(query()),
    fetchRunByRequestId: (requestId) => fetchShoppingStockPriceCheckRunByRequestId(query(), requestId),
    fetchRunItems: (runId) => fetchShoppingStockPriceCheckItems(query(), runId),
    claimRun: (runId) => transaction()((database) => claimShoppingStockPriceCheckRun(database, runId)),
    updateRunPhase: (request) => transaction()((database) => updateShoppingStockPriceCheckRunPhase(database, request)),
    recordItemOutcome: (request) => transaction()((database) => recordShoppingStockPriceCheckItemOutcome(database, request)),
    completeRun: (request) => transaction()((database) => completeShoppingStockPriceCheckRun(database, request)),
    isItemSnapshotCurrent: (runItemId) => isShoppingStockPriceCheckItemSnapshotCurrent(query(), runItemId),
  };
}

export async function createShoppingStockPriceCheckRun(
  database: DatabaseQuery,
  request: CreateShoppingStockPriceCheckRunRequest,
): Promise<ShoppingStockPriceCheckSummary> {
  const [created] = await database<{ id: unknown }>`
    INSERT INTO shopping_stock_price_check_runs (request_id, actor)
    VALUES (${request.requestId}, ${request.actor?.trim() || null})
    RETURNING id
  `;
  const runId = requiredString(created?.id, 'shopping_stock_price_check_runs.id');
  const neededItems = await fetchNeededShoppingListItems(database);

  if (neededItems.length === 0) {
    await database`
      UPDATE shopping_stock_price_check_runs
      SET
        status = 'completed',
        phase = 'finished',
        started_at = now(),
        finished_at = now(),
        message = 'No shopping items need a stock and price check.'
      WHERE id = ${runId}
    `;
  } else {
    await database`
      UPDATE shopping_stock_price_check_runs
      SET requested_item_count = ${neededItems.length}
      WHERE id = ${runId}
    `;

    for (const [position, item] of neededItems.entries()) {
      const snapshot = shoppingStockPriceCheckSnapshotFromItem(item);
      await database`
        INSERT INTO shopping_stock_price_check_items (
          run_id,
          shopping_item_id,
          item_version,
          snapshot_position,
          item_snapshot
        )
        VALUES (
          ${runId},
          ${snapshot.itemId},
          ${snapshot.itemVersion},
          ${position},
          ${jsonb(snapshot)}::jsonb
        )
      `;
    }
  }

  return requireShoppingStockPriceCheckRun(
    await fetchShoppingStockPriceCheckRun(database, runId),
    'create shopping stock and price check',
  );
}

export async function fetchShoppingStockPriceCheckRun(
  database: DatabaseQuery,
  runId: string,
): Promise<ShoppingStockPriceCheckSummary | null> {
  const [row] = await database<ShoppingStockPriceCheckRunRow>`
    SELECT
      id,
      status,
      phase,
      requested_item_count AS "requestedItemCount",
      processed_item_count AS "processedItemCount",
      updated_item_count AS "updatedItemCount",
      unmatched_item_count AS "unmatchedItemCount",
      failed_item_count AS "failedItemCount",
      skipped_stale_item_count AS "skippedStaleItemCount",
      submitted_at AS "submittedAt",
      started_at AS "startedAt",
      finished_at AS "finishedAt",
      failure_code AS "failureCode",
      message
    FROM shopping_stock_price_check_runs
    WHERE id = ${runId}
    LIMIT 1
  `;

  return row ? shoppingStockPriceCheckSummaryFromRow(row) : null;
}

export async function fetchActiveShoppingStockPriceCheckRun(
  database: DatabaseQuery,
): Promise<ShoppingStockPriceCheckSummary | null> {
  const [row] = await database<ShoppingStockPriceCheckRunRow>`
    SELECT
      id,
      status,
      phase,
      requested_item_count AS "requestedItemCount",
      processed_item_count AS "processedItemCount",
      updated_item_count AS "updatedItemCount",
      unmatched_item_count AS "unmatchedItemCount",
      failed_item_count AS "failedItemCount",
      skipped_stale_item_count AS "skippedStaleItemCount",
      submitted_at AS "submittedAt",
      started_at AS "startedAt",
      finished_at AS "finishedAt",
      failure_code AS "failureCode",
      message
    FROM shopping_stock_price_check_runs
    WHERE status IN ('queued', 'running')
    ORDER BY submitted_at DESC
    LIMIT 1
  `;

  return row ? shoppingStockPriceCheckSummaryFromRow(row) : null;
}

export async function fetchShoppingStockPriceCheckRunByRequestId(
  database: DatabaseQuery,
  requestId: string,
): Promise<ShoppingStockPriceCheckSummary | null> {
  const [row] = await database<ShoppingStockPriceCheckRunRow>`
    SELECT
      id,
      status,
      phase,
      requested_item_count AS "requestedItemCount",
      processed_item_count AS "processedItemCount",
      updated_item_count AS "updatedItemCount",
      unmatched_item_count AS "unmatchedItemCount",
      failed_item_count AS "failedItemCount",
      skipped_stale_item_count AS "skippedStaleItemCount",
      submitted_at AS "submittedAt",
      started_at AS "startedAt",
      finished_at AS "finishedAt",
      failure_code AS "failureCode",
      message
    FROM shopping_stock_price_check_runs
    WHERE request_id = ${requestId}
    LIMIT 1
  `;

  return row ? shoppingStockPriceCheckSummaryFromRow(row) : null;
}

export async function fetchShoppingStockPriceCheckItems(
  database: DatabaseQuery,
  runId: string,
): Promise<ShoppingStockPriceCheckItemOutcome[]> {
  const rows = await database<ShoppingStockPriceCheckItemRow>`
    SELECT
      id,
      run_id AS "runId",
      shopping_item_id AS "shoppingItemId",
      item_version AS "itemVersion",
      item_snapshot AS "itemSnapshot",
      status,
      store_outcomes AS "storeOutcomes",
      failure_code AS "failureCode",
      created_at AS "createdAt",
      updated_at AS "updatedAt"
    FROM shopping_stock_price_check_items
    WHERE run_id = ${runId}
    ORDER BY snapshot_position ASC
  `;

  return rows.map(shoppingStockPriceCheckItemOutcomeFromRow);
}

export async function claimShoppingStockPriceCheckRun(
  database: DatabaseQuery,
  runId: string,
): Promise<ShoppingStockPriceCheckSummary | null> {
  const [claimed] = await database<{ id: unknown }>`
    UPDATE shopping_stock_price_check_runs
    SET
      status = 'running',
      phase = 'checking_stores',
      started_at = now()
    WHERE id = ${runId}
      AND status = 'queued'
    RETURNING id
  `;

  if (!claimed) {
    return fetchShoppingStockPriceCheckRun(database, runId);
  }

  return fetchShoppingStockPriceCheckRun(database, requiredString(claimed.id, 'shopping_stock_price_check_runs.id'));
}

export async function updateShoppingStockPriceCheckRunPhase(
  database: DatabaseQuery,
  request: UpdateShoppingStockPriceCheckRunPhaseRequest,
): Promise<ShoppingStockPriceCheckSummary | null> {
  const [updated] = await database<{ id: unknown }>`
    UPDATE shopping_stock_price_check_runs
    SET phase = ${request.phase}
    WHERE id = ${request.runId}
      AND status = 'running'
    RETURNING id
  `;

  return updated
    ? fetchShoppingStockPriceCheckRun(database, requiredString(updated.id, 'shopping_stock_price_check_runs.id'))
    : null;
}

export async function recordShoppingStockPriceCheckItemOutcome(
  database: DatabaseQuery,
  request: RecordShoppingStockPriceCheckItemOutcomeRequest,
): Promise<ShoppingStockPriceCheckSummary | null> {
  const [updated] = await database<{ runId: unknown }>`
    UPDATE shopping_stock_price_check_items AS item
    SET
      status = ${request.status},
      store_outcomes = ${jsonb(request.storeOutcomes)}::jsonb,
      failure_code = ${request.failureCode ?? null}
    FROM shopping_stock_price_check_runs run
    WHERE item.id = ${request.runItemId}
      AND run.id = item.run_id
      AND run.status = 'running'
      AND item.status = 'pending'
    RETURNING item.run_id AS "runId"
  `;

  if (!updated) {
    return null;
  }

  const runId = requiredString(updated.runId, 'shopping_stock_price_check_items.run_id');
  await refreshShoppingStockPriceCheckRunCounters(database, runId);
  return fetchShoppingStockPriceCheckRun(database, runId);
}

export async function completeShoppingStockPriceCheckRun(
  database: DatabaseQuery,
  request: CompleteShoppingStockPriceCheckRunRequest,
): Promise<ShoppingStockPriceCheckSummary | null> {
  const [completed] = await database<{ id: unknown }>`
    UPDATE shopping_stock_price_check_runs
    SET
      status = ${request.status},
      phase = 'finished',
      failure_code = ${request.failureCode ?? null},
      message = ${request.message ?? null},
      finished_at = now()
    WHERE id = ${request.runId}
      AND status IN ('queued', 'running')
    RETURNING id
  `;

  return completed
    ? fetchShoppingStockPriceCheckRun(database, requiredString(completed.id, 'shopping_stock_price_check_runs.id'))
    : null;
}

export async function isShoppingStockPriceCheckItemSnapshotCurrent(
  database: DatabaseQuery,
  runItemId: string,
): Promise<boolean> {
  const [row] = await database<{
    shoppingItemId: unknown;
    itemVersion: unknown;
    currentItemId: unknown;
    currentVersion: unknown;
    purchased: unknown;
  }>`
    SELECT
      snapshot.shopping_item_id AS "shoppingItemId",
      snapshot.item_version AS "itemVersion",
      item.id AS "currentItemId",
      item.version AS "currentVersion",
      item.purchased
    FROM shopping_stock_price_check_items snapshot
    LEFT JOIN shopping_list item ON item.id = snapshot.shopping_item_id
    WHERE snapshot.id = ${runItemId}
    LIMIT 1
  `;

  return Boolean(
    row
    && optionalInteger(row.shoppingItemId) === optionalInteger(row.currentItemId)
    && optionalInteger(row.itemVersion) === optionalInteger(row.currentVersion)
    && row.purchased === false,
  );
}

async function refreshShoppingStockPriceCheckRunCounters(
  database: DatabaseQuery,
  runId: string,
): Promise<void> {
  await database`
    UPDATE shopping_stock_price_check_runs AS run
    SET
      processed_item_count = counts.processed_item_count,
      updated_item_count = counts.updated_item_count,
      unmatched_item_count = counts.unmatched_item_count,
      failed_item_count = counts.failed_item_count,
      skipped_stale_item_count = counts.skipped_stale_item_count
    FROM (
      SELECT
        COUNT(*) FILTER (WHERE status <> 'pending')::integer AS processed_item_count,
        COUNT(*) FILTER (WHERE status = 'updated')::integer AS updated_item_count,
        COUNT(*) FILTER (WHERE status = 'unmatched')::integer AS unmatched_item_count,
        COUNT(*) FILTER (WHERE status = 'failed')::integer AS failed_item_count,
        COUNT(*) FILTER (WHERE status = 'skipped_stale')::integer AS skipped_stale_item_count
      FROM shopping_stock_price_check_items
      WHERE run_id = ${runId}
    ) counts
    WHERE run.id = ${runId}
  `;
}

function shoppingStockPriceCheckSnapshotFromItem(item: ShoppingListItem): ShoppingStockPriceCheckItemSnapshot {
  return {
    itemId: item.id,
    itemVersion: item.version ?? 1,
    name: item.name,
    ...(item.brand ? { brand: item.brand } : {}),
    quantity: item.quantity,
    ...(item.notes ? { notes: item.notes } : {}),
    categoryId: item.categoryId,
    ...(item.image ? { image: item.image } : {}),
    storeListings: item.storeListings,
  };
}

function shoppingStockPriceCheckSummaryFromRow(row: ShoppingStockPriceCheckRunRow): ShoppingStockPriceCheckSummary {
  const status = requiredShoppingStockPriceCheckStatus(row.status);
  const phase = requiredShoppingStockPriceCheckPhase(row.phase);
  const submittedAt = requiredISOString(row.submittedAt, 'shopping_stock_price_check_runs.submitted_at');

  return {
    ok: true,
    id: requiredString(row.id, 'shopping_stock_price_check_runs.id'),
    status,
    phase,
    requestedItemCount: requiredInteger(row.requestedItemCount, 'shopping_stock_price_check_runs.requested_item_count'),
    processedItemCount: requiredInteger(row.processedItemCount, 'shopping_stock_price_check_runs.processed_item_count'),
    updatedItemCount: requiredInteger(row.updatedItemCount, 'shopping_stock_price_check_runs.updated_item_count'),
    unmatchedItemCount: requiredInteger(row.unmatchedItemCount, 'shopping_stock_price_check_runs.unmatched_item_count'),
    failedItemCount: requiredInteger(row.failedItemCount, 'shopping_stock_price_check_runs.failed_item_count'),
    skippedStaleItemCount: requiredInteger(row.skippedStaleItemCount, 'shopping_stock_price_check_runs.skipped_stale_item_count'),
    submittedAt,
    startedAt: optionalISOString(row.startedAt) ?? null,
    finishedAt: optionalISOString(row.finishedAt) ?? null,
    ...(optionalString(row.failureCode) ? { failureCode: optionalString(row.failureCode) } : {}),
    ...(optionalString(row.message) ? { message: optionalString(row.message) } : {}),
  };
}

function shoppingStockPriceCheckItemOutcomeFromRow(
  row: ShoppingStockPriceCheckItemRow,
): ShoppingStockPriceCheckItemOutcome {
  const item = parseSnapshot(row.itemSnapshot);
  const storeOutcomes = parseStoreOutcomes(row.storeOutcomes);

  return {
    id: requiredString(row.id, 'shopping_stock_price_check_items.id'),
    runId: requiredString(row.runId, 'shopping_stock_price_check_items.run_id'),
    item: {
      ...item,
      itemId: requiredInteger(row.shoppingItemId, 'shopping_stock_price_check_items.shopping_item_id'),
      itemVersion: requiredInteger(row.itemVersion, 'shopping_stock_price_check_items.item_version'),
    },
    status: requiredShoppingStockPriceCheckItemOutcomeStatus(row.status),
    storeOutcomes,
    ...(optionalString(row.failureCode) ? { failureCode: optionalString(row.failureCode) } : {}),
    createdAt: requiredISOString(row.createdAt, 'shopping_stock_price_check_items.created_at'),
    updatedAt: requiredISOString(row.updatedAt, 'shopping_stock_price_check_items.updated_at'),
  };
}

function parseSnapshot(value: unknown): ShoppingStockPriceCheckItemSnapshot {
  const parsed = parseJSONBValue(value);

  if (!isRecord(parsed)) {
    throw new Error('Expected shopping_stock_price_check_items.item_snapshot to be an object.');
  }

  const itemId = requiredInteger(parsed.itemId, 'shopping_stock_price_check_items.item_snapshot.itemId');
  const itemVersion = requiredInteger(parsed.itemVersion, 'shopping_stock_price_check_items.item_snapshot.itemVersion');
  const name = requiredString(parsed.name, 'shopping_stock_price_check_items.item_snapshot.name');
  const quantity = requiredInteger(parsed.quantity, 'shopping_stock_price_check_items.item_snapshot.quantity');
  const categoryId = parsed.categoryId === null ? null : requiredInteger(
    parsed.categoryId,
    'shopping_stock_price_check_items.item_snapshot.categoryId',
  );
  const storeListings = Array.isArray(parsed.storeListings)
    ? parsed.storeListings.filter(isRecord)
    : [];

  return {
    itemId,
    itemVersion,
    name,
    ...(optionalString(parsed.brand) ? { brand: optionalString(parsed.brand) } : {}),
    quantity,
    ...(optionalString(parsed.notes) ? { notes: optionalString(parsed.notes) } : {}),
    categoryId,
    ...(optionalString(parsed.image) ? { image: optionalString(parsed.image) } : {}),
    storeListings,
  };
}

function parseStoreOutcomes(value: unknown): ShoppingStockPriceCheckStoreOutcome[] {
  const parsed = parseJSONBValue(value);

  return Array.isArray(parsed) ? parsed.filter(isRecord) as ShoppingStockPriceCheckStoreOutcome[] : [];
}

function requiredShoppingStockPriceCheckStatus(value: unknown): ShoppingStockPriceCheckStatus {
  const status = requiredString(value, 'shopping_stock_price_check_runs.status');

  if (!['queued', 'running', 'completed', 'completed_with_issues', 'failed'].includes(status)) {
    throw new Error(`Unexpected shopping stock and price check status: ${status}`);
  }

  return status as ShoppingStockPriceCheckStatus;
}

function requiredShoppingStockPriceCheckPhase(value: unknown): ShoppingStockPriceCheckPhase {
  const phase = requiredString(value, 'shopping_stock_price_check_runs.phase');

  if (!['preparing', 'checking_stores', 'matching_products', 'applying_updates', 'finished'].includes(phase)) {
    throw new Error(`Unexpected shopping stock and price check phase: ${phase}`);
  }

  return phase as ShoppingStockPriceCheckPhase;
}

function requiredShoppingStockPriceCheckItemOutcomeStatus(
  value: unknown,
): ShoppingStockPriceCheckItemOutcomeStatus {
  const status = requiredString(value, 'shopping_stock_price_check_items.status');

  if (!['pending', 'updated', 'unmatched', 'failed', 'skipped_stale'].includes(status)) {
    throw new Error(`Unexpected shopping stock and price check item status: ${status}`);
  }

  return status as ShoppingStockPriceCheckItemOutcomeStatus;
}

function requiredISOString(value: unknown, fieldName: string): string {
  const timestamp = optionalISOString(value);

  if (!timestamp) {
    throw new Error(`Expected ${fieldName} to be an ISO timestamp.`);
  }

  return timestamp;
}

function requireShoppingStockPriceCheckRun(
  run: ShoppingStockPriceCheckSummary | null,
  operation: string,
): ShoppingStockPriceCheckSummary {
  if (!run) {
    throw new Error(`Expected shopping stock and price check to remain readable after ${operation}.`);
  }

  return run;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}
