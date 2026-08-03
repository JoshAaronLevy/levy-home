import type {
  ShoppingListReaddMatchKind,
  ShoppingListReaddOperationOutcome,
  ShoppingListReaddOperationSummary,
  ShoppingListReaddRunStatus,
  ShoppingListReaddSummary,
  ShoppingListReaddUnmatchedPhrase,
} from '../contracts.js';
import {
  getDatabaseClient,
  getDatabaseTransactionRunner,
  type DatabaseQuery,
  type DatabaseTransactionRunner,
} from '../db/client.js';
import {
  jsonb,
  optionalBoolean,
  optionalInteger,
  optionalISOString,
  optionalString,
  parseJSONBValue,
  requiredInteger,
  requiredString,
} from '../db/rowReaders.js';
import { shoppingListReaddLimits } from '../services/shopping/shoppingListReaddContracts.js';

const finalizableStatuses = new Set<ShoppingListReaddRunStatus>([
  'completed',
  'completed_with_issues',
  'failed',
]);
const operationOutcomes = new Set<ShoppingListReaddOperationOutcome>([
  're_added',
  'quantity_updated',
  'already_needed',
  'unmatched',
  'stale_skipped',
  'invalid_request',
  'unavailable',
  'undone',
]);
const matchKinds = new Set<ShoppingListReaddMatchKind>(['exact', 'normalized', 'semantic']);

/** Retain terminal re-add/Undo audit records for a bounded period only. */
export const shoppingListReaddRetentionDays = 30;

export type ShoppingListReaddStore = {
  createRun: (request: CreateShoppingListReaddRunRequest) => Promise<ShoppingListReaddSummary>;
  fetchRun: (runId: string) => Promise<ShoppingListReaddSummary | null>;
  fetchRunByRequestId: (requestId: string) => Promise<ShoppingListReaddSummary | null>;
  fetchRecoverableRun: () => Promise<ShoppingListReaddSummary | null>;
  claimRun: (runId: string) => Promise<ShoppingListReaddSummary | null>;
  claimRunForProcessing: (runId: string) => Promise<ShoppingListReaddRunClaim | null>;
  fetchRunExecutionInput: (runId: string) => Promise<ShoppingListReaddExecutionRun | null>;
  moveRunToApplying: (runId: string) => Promise<ShoppingListReaddSummary | null>;
  recordApplyingOperation: (request: RecordApplyingShoppingListReaddOperationRequest) => Promise<boolean>;
  finalizeRun: (request: FinalizeShoppingListReaddRunRequest) => Promise<ShoppingListReaddSummary | null>;
  fetchRunOperations: (runId: string) => Promise<ShoppingListReaddPersistedOperation[]>;
  fetchUndoableRun: (runId: string) => Promise<ShoppingListReaddUndoRun | null>;
  recordUndoOperation: (request: RecordShoppingListReaddUndoOperationRequest) => Promise<boolean>;
  markRunUndone: (runId: string) => Promise<ShoppingListReaddSummary | null>;
  cleanupExpiredRuns: (limit?: number) => Promise<number>;
};

export type CreateShoppingListReaddRunRequest = {
  requestId: string;
  actor: 'Josh' | 'Mallory';
  requestedText: string;
};

/**
 * This is the minimum durable fact set for idempotency and safe Undo. It is
 * deliberately not a Shopping row, candidate snapshot, or Codex transcript.
 */
export type ShoppingListReaddOperationPersistenceInput = {
  requestIndex: number;
  requestedText: string;
  outcome: ShoppingListReaddOperationOutcome;
  itemId?: number;
  /** Included only in the bounded public summary, never the operation row. */
  itemName?: string;
  quantity?: number;
  matchKind?: ShoppingListReaddMatchKind;
  snapshotVersion?: number;
  priorPurchased?: boolean;
  priorQuantity?: number;
  appliedPurchased?: boolean;
  appliedQuantity?: number;
  appliedVersion?: number;
  undoEligible?: boolean;
};

export type FinalizeShoppingListReaddRunRequest = {
  runId: string;
  status: Extract<ShoppingListReaddRunStatus, 'completed' | 'completed_with_issues' | 'failed'>;
  operations: ShoppingListReaddOperationPersistenceInput[];
  /** A short-lived absolute expiry set only when at least one write can be undone. */
  undoExpiresAt?: Date;
};

/** Durable pre-write Undo facts, recorded while the parent run is applying. */
export type RecordApplyingShoppingListReaddOperationRequest = {
  runId: string;
  operation: ShoppingListReaddOperationPersistenceInput;
};

export type ShoppingListReaddUndoStatus = 'not_eligible' | 'eligible' | 'reverted' | 'skipped_stale';

export type ShoppingListReaddPersistedOperation = {
  id: string;
  runId: string;
  requestIndex: number;
  requestedText: string;
  outcome: ShoppingListReaddOperationOutcome;
  itemId?: number;
  snapshotVersion?: number;
  priorPurchased?: boolean;
  priorQuantity?: number;
  appliedPurchased?: boolean;
  appliedQuantity?: number;
  appliedVersion?: number;
  matchKind?: ShoppingListReaddMatchKind;
  undoStatus: ShoppingListReaddUndoStatus;
  createdAt: string;
  updatedAt: string;
};

export type ShoppingListReaddUndoRun = {
  run: ShoppingListReaddSummary;
  actor: 'Josh' | 'Mallory';
  operations: ShoppingListReaddPersistedOperation[];
};

/** Internal-only execution input. It is never an HTTP response shape. */
export type ShoppingListReaddExecutionRun = {
  id: string;
  actor: 'Josh' | 'Mallory';
  requestedText: string;
  status: ShoppingListReaddRunStatus;
};

export type ShoppingListReaddRunClaim = {
  run: ShoppingListReaddSummary;
  claimed: boolean;
};

export type RecordShoppingListReaddUndoOperationRequest = {
  operationId: string;
  status: Extract<ShoppingListReaddUndoStatus, 'reverted' | 'skipped_stale'>;
};

type ShoppingListReaddRunRow = Record<string, unknown> & {
  id: unknown;
  actor: unknown;
  status: unknown;
  publicSummary: unknown;
  undoExpiresAt: unknown;
  submittedAt: unknown;
  startedAt: unknown;
  finishedAt: unknown;
};

type ShoppingListReaddOperationRow = Record<string, unknown> & {
  id: unknown;
  runId: unknown;
  requestIndex: unknown;
  requestedText: unknown;
  outcome: unknown;
  itemId: unknown;
  snapshotVersion: unknown;
  priorPurchased: unknown;
  priorQuantity: unknown;
  appliedPurchased: unknown;
  appliedQuantity: unknown;
  appliedVersion: unknown;
  matchKind: unknown;
  undoStatus: unknown;
  createdAt: unknown;
  updatedAt: unknown;
};

export function createPostgresShoppingListReaddStore(options: {
  database?: DatabaseQuery;
  transactionRunner?: DatabaseTransactionRunner;
} = {}): ShoppingListReaddStore {
  if (Boolean(options.database) !== Boolean(options.transactionRunner)) {
    throw new Error('database and transactionRunner must be injected together.');
  }

  const query = () => options.database ?? getDatabaseClient();
  const transaction = () => options.transactionRunner ?? getDatabaseTransactionRunner();

  return {
    createRun: (request) => transaction()((database) => createShoppingListReaddRun(database, request)),
    fetchRun: (runId) => fetchShoppingListReaddRun(query(), runId),
    fetchRunByRequestId: (requestId) => fetchShoppingListReaddRunByRequestId(query(), requestId),
    fetchRecoverableRun: () => fetchRecoverableShoppingListReaddRun(query()),
    claimRun: (runId) => transaction()((database) => claimShoppingListReaddRun(database, runId)),
    claimRunForProcessing: (runId) => transaction()((database) => claimShoppingListReaddRunForProcessing(database, runId)),
    fetchRunExecutionInput: (runId) => fetchShoppingListReaddExecutionRun(query(), runId),
    moveRunToApplying: (runId) => transaction()((database) => moveShoppingListReaddRunToApplying(database, runId)),
    recordApplyingOperation: (request) => transaction()((database) => recordApplyingShoppingListReaddOperation(database, request)),
    finalizeRun: (request) => transaction()((database) => finalizeShoppingListReaddRun(database, request)),
    fetchRunOperations: (runId) => fetchShoppingListReaddOperations(query(), runId),
    fetchUndoableRun: (runId) => fetchShoppingListReaddUndoRun(query(), runId),
    recordUndoOperation: (request) => transaction()((database) => recordShoppingListReaddUndoOperation(database, request)),
    markRunUndone: (runId) => transaction()((database) => markShoppingListReaddRunUndone(database, runId)),
    cleanupExpiredRuns: (limit = 100) => transaction()((database) => cleanupExpiredShoppingListReaddRuns(database, limit)),
  };
}

export async function createShoppingListReaddRun(
  database: DatabaseQuery,
  request: CreateShoppingListReaddRunRequest,
): Promise<ShoppingListReaddSummary> {
  const requestedText = boundedText(request.requestedText, 'requestedText');
  const [created] = await database<{ id: unknown }>`
    INSERT INTO shopping_ai_readd_runs (request_id, actor, requested_text)
    VALUES (${request.requestId}, ${request.actor}, ${requestedText})
    RETURNING id
  `;

  return requireRun(
    await fetchShoppingListReaddRun(database, requiredString(created?.id, 'shopping_ai_readd_runs.id')),
    'create Shopping AI re-add run',
  );
}

export async function fetchShoppingListReaddRun(
  database: DatabaseQuery,
  runId: string,
): Promise<ShoppingListReaddSummary | null> {
  const [row] = await database<ShoppingListReaddRunRow>`
    SELECT
      id, actor, status, public_summary AS "publicSummary", undo_expires_at AS "undoExpiresAt",
      submitted_at AS "submittedAt", started_at AS "startedAt", finished_at AS "finishedAt"
    FROM shopping_ai_readd_runs
    WHERE id = ${runId}
    LIMIT 1
  `;

  return row ? shoppingListReaddSummaryFromRow(row) : null;
}

export async function fetchShoppingListReaddRunByRequestId(
  database: DatabaseQuery,
  requestId: string,
): Promise<ShoppingListReaddSummary | null> {
  const [row] = await database<ShoppingListReaddRunRow>`
    SELECT
      id, actor, status, public_summary AS "publicSummary", undo_expires_at AS "undoExpiresAt",
      submitted_at AS "submittedAt", started_at AS "startedAt", finished_at AS "finishedAt"
    FROM shopping_ai_readd_runs
    WHERE request_id = ${requestId}
    LIMIT 1
  `;

  return row ? shoppingListReaddSummaryFromRow(row) : null;
}

/** One active run is enforced by a database partial index; recovery handles it oldest-first. */
export async function fetchRecoverableShoppingListReaddRun(
  database: DatabaseQuery,
): Promise<ShoppingListReaddSummary | null> {
  const [row] = await database<ShoppingListReaddRunRow>`
    SELECT
      id, status, public_summary AS "publicSummary", undo_expires_at AS "undoExpiresAt",
      submitted_at AS "submittedAt", started_at AS "startedAt", finished_at AS "finishedAt"
    FROM shopping_ai_readd_runs
    WHERE status IN ('queued', 'matching', 'applying')
    ORDER BY submitted_at ASC
    LIMIT 1
  `;
  return row ? shoppingListReaddSummaryFromRow(row) : null;
}

export async function claimShoppingListReaddRun(
  database: DatabaseQuery,
  runId: string,
): Promise<ShoppingListReaddSummary | null> {
  const [claimed] = await database<{ id: unknown }>`
    UPDATE shopping_ai_readd_runs
    SET status = 'matching', started_at = now()
    WHERE id = ${runId} AND status = 'queued'
    RETURNING id
  `;

  return claimed
    ? fetchShoppingListReaddRun(database, requiredString(claimed.id, 'shopping_ai_readd_runs.id'))
    : fetchShoppingListReaddRun(database, runId);
}

export async function claimShoppingListReaddRunForProcessing(
  database: DatabaseQuery,
  runId: string,
): Promise<ShoppingListReaddRunClaim | null> {
  const [claimed] = await database<{ id: unknown }>`
    UPDATE shopping_ai_readd_runs
    SET status = 'matching', started_at = now()
    WHERE id = ${runId} AND status = 'queued'
    RETURNING id
  `;
  const run = await fetchShoppingListReaddRun(database, runId);
  if (!run) return null;
  return { run, claimed: Boolean(claimed) };
}

export async function fetchShoppingListReaddExecutionRun(
  database: DatabaseQuery,
  runId: string,
): Promise<ShoppingListReaddExecutionRun | null> {
  const [row] = await database<Record<string, unknown> & {
    id: unknown;
    actor: unknown;
    requestedText: unknown;
    status: unknown;
  }>`
    SELECT id, actor, requested_text AS "requestedText", status
    FROM shopping_ai_readd_runs
    WHERE id = ${runId}
    LIMIT 1
  `;
  if (!row) return null;
  return {
    id: requiredString(row.id, 'shopping_ai_readd_runs.id'),
    actor: requiredActor(row.actor),
    requestedText: boundedText(row.requestedText, 'shopping_ai_readd_runs.requested_text'),
    status: requiredRunStatus(row.status),
  };
}

export async function moveShoppingListReaddRunToApplying(
  database: DatabaseQuery,
  runId: string,
): Promise<ShoppingListReaddSummary | null> {
  const [updated] = await database<{ id: unknown }>`
    UPDATE shopping_ai_readd_runs
    SET status = 'applying'
    WHERE id = ${runId} AND status = 'matching'
    RETURNING id
  `;

  return updated
    ? fetchShoppingListReaddRun(database, requiredString(updated.id, 'shopping_ai_readd_runs.id'))
    : null;
}

export async function finalizeShoppingListReaddRun(
  database: DatabaseQuery,
  request: FinalizeShoppingListReaddRunRequest,
): Promise<ShoppingListReaddSummary | null> {
  if (!finalizableStatuses.has(request.status)) {
    throw new Error('Shopping AI re-add runs can finalize only as completed, completed_with_issues, or failed.');
  }

  const operations = sanitizeOperations(request.operations);
  if (request.status === 'failed' && operations.some((operation) => operation.undoEligible)) {
    throw new Error('Failed Shopping AI re-add runs cannot expose an Undo window.');
  }
  const undoExpiresAt = validatedUndoExpiry(request.undoExpiresAt, operations);
  const publicSummary = publicSummaryFromOperations(operations);
  const counts = countsFromOperations(operations);
  const [completed] = await database<{ id: unknown }>`
    UPDATE shopping_ai_readd_runs
    SET
      status = ${request.status},
      requested_phrase_count = ${operations.length},
      processed_phrase_count = ${counts.processed},
      readded_count = ${counts.readded},
      quantity_updated_count = ${counts.quantityUpdated},
      already_needed_count = ${counts.alreadyNeeded},
      unmatched_count = ${counts.unmatched},
      stale_skipped_count = ${counts.staleSkipped},
      invalid_request_count = ${counts.invalidRequest},
      unavailable_count = ${counts.unavailable},
      undone_count = ${counts.undone},
      public_summary = ${jsonb(publicSummary)}::jsonb,
      undo_expires_at = ${undoExpiresAt ?? null},
      purge_after = now() + (${shoppingListReaddRetentionDays} * INTERVAL '1 day'),
      finished_at = now()
    WHERE id = ${request.runId} AND status IN ('matching', 'applying')
    RETURNING id
  `;

  if (!completed) {
    return null;
  }

  for (const operation of operations) {
    await upsertShoppingListReaddOperation(database, request.runId, operation);
  }

  return requireRun(await fetchShoppingListReaddRun(database, request.runId), 'finalize Shopping AI re-add run');
}

export async function recordApplyingShoppingListReaddOperation(
  database: DatabaseQuery,
  request: RecordApplyingShoppingListReaddOperationRequest,
): Promise<boolean> {
  const [operation] = sanitizeOperations([request.operation]);
  const [inserted] = await database<{ id: unknown }>`
    INSERT INTO shopping_ai_readd_operations (
      run_id,
      request_index,
      requested_text,
      outcome,
      target_item_id,
      snapshot_version,
      prior_purchased,
      prior_quantity,
      applied_purchased,
      applied_quantity,
      applied_version,
      match_kind,
      undo_status
    )
    SELECT
      ${request.runId},
      ${operation.requestIndex},
      ${operation.requestedText},
      ${operation.outcome},
      ${operation.itemId ?? null},
      ${operation.snapshotVersion ?? null},
      ${operation.priorPurchased ?? null},
      ${operation.priorQuantity ?? null},
      ${operation.appliedPurchased ?? null},
      ${operation.appliedQuantity ?? null},
      ${operation.appliedVersion ?? null},
      ${operation.matchKind ?? null},
      'not_eligible'
    WHERE EXISTS (
      SELECT 1 FROM shopping_ai_readd_runs
      WHERE id = ${request.runId} AND status = 'applying'
    )
    ON CONFLICT (run_id, request_index) DO NOTHING
    RETURNING id
  `;
  return Boolean(inserted);
}

async function upsertShoppingListReaddOperation(
  database: DatabaseQuery,
  runId: string,
  operation: ShoppingListReaddOperationPersistenceInput,
): Promise<void> {
  await database`
      INSERT INTO shopping_ai_readd_operations (
        run_id,
        request_index,
        requested_text,
        outcome,
        target_item_id,
        snapshot_version,
        prior_purchased,
        prior_quantity,
        applied_purchased,
        applied_quantity,
        applied_version,
        match_kind,
        undo_status
      )
      VALUES (
        ${runId},
        ${operation.requestIndex},
        ${operation.requestedText},
        ${operation.outcome},
        ${operation.itemId ?? null},
        ${operation.snapshotVersion ?? null},
        ${operation.priorPurchased ?? null},
        ${operation.priorQuantity ?? null},
        ${operation.appliedPurchased ?? null},
        ${operation.appliedQuantity ?? null},
        ${operation.appliedVersion ?? null},
        ${operation.matchKind ?? null},
        ${operation.undoEligible ? 'eligible' : 'not_eligible'}
      )
      ON CONFLICT (run_id, request_index) DO UPDATE
      SET
        requested_text = EXCLUDED.requested_text,
        outcome = EXCLUDED.outcome,
        target_item_id = EXCLUDED.target_item_id,
        snapshot_version = EXCLUDED.snapshot_version,
        prior_purchased = EXCLUDED.prior_purchased,
        prior_quantity = EXCLUDED.prior_quantity,
        applied_purchased = EXCLUDED.applied_purchased,
        applied_quantity = EXCLUDED.applied_quantity,
        applied_version = EXCLUDED.applied_version,
        match_kind = EXCLUDED.match_kind,
        undo_status = EXCLUDED.undo_status
    `;
}

export async function fetchShoppingListReaddOperations(
  database: DatabaseQuery,
  runId: string,
): Promise<ShoppingListReaddPersistedOperation[]> {
  const rows = await database<ShoppingListReaddOperationRow>`
    SELECT
      id,
      run_id AS "runId",
      request_index AS "requestIndex",
      requested_text AS "requestedText",
      outcome,
      target_item_id AS "itemId",
      snapshot_version AS "snapshotVersion",
      prior_purchased AS "priorPurchased",
      prior_quantity AS "priorQuantity",
      applied_purchased AS "appliedPurchased",
      applied_quantity AS "appliedQuantity",
      applied_version AS "appliedVersion",
      match_kind AS "matchKind",
      undo_status AS "undoStatus",
      created_at AS "createdAt",
      updated_at AS "updatedAt"
    FROM shopping_ai_readd_operations
    WHERE run_id = ${runId}
    ORDER BY request_index ASC
  `;

  return rows.map(shoppingListReaddOperationFromRow);
}

export async function fetchShoppingListReaddUndoRun(
  database: DatabaseQuery,
  runId: string,
): Promise<ShoppingListReaddUndoRun | null> {
  const [row] = await database<ShoppingListReaddRunRow>`
    SELECT
      id, actor, status, public_summary AS "publicSummary", undo_expires_at AS "undoExpiresAt",
      submitted_at AS "submittedAt", started_at AS "startedAt", finished_at AS "finishedAt"
    FROM shopping_ai_readd_runs
    WHERE id = ${runId}
      AND status IN ('completed', 'completed_with_issues')
      AND undo_expires_at > now()
    LIMIT 1
  `;

  if (!row) {
    return null;
  }

  const operations = await fetchShoppingListReaddOperations(database, runId);
  if (!operations.some((operation) => operation.undoStatus === 'eligible')) {
    return null;
  }

  return {
    run: shoppingListReaddSummaryFromRow(row),
    actor: requiredActor(row.actor),
    operations,
  };
}

export async function recordShoppingListReaddUndoOperation(
  database: DatabaseQuery,
  request: RecordShoppingListReaddUndoOperationRequest,
): Promise<boolean> {
  const [updated] = await database<{ id: unknown }>`
    UPDATE shopping_ai_readd_operations AS operation
    SET undo_status = ${request.status}
    FROM shopping_ai_readd_runs run
    WHERE operation.id = ${request.operationId}
      AND run.id = operation.run_id
      AND run.status IN ('completed', 'completed_with_issues')
      AND run.undo_expires_at > now()
      AND operation.undo_status = 'eligible'
    RETURNING operation.id AS id
  `;

  return Boolean(updated);
}

export async function markShoppingListReaddRunUndone(
  database: DatabaseQuery,
  runId: string,
): Promise<ShoppingListReaddSummary | null> {
  const [updated] = await database<{ id: unknown }>`
    UPDATE shopping_ai_readd_runs AS run
    SET status = 'undone'
    WHERE run.id = ${runId}
      AND run.status IN ('completed', 'completed_with_issues')
      AND run.undo_expires_at > now()
      AND EXISTS (
        SELECT 1
        FROM shopping_ai_readd_operations operation
        WHERE operation.run_id = run.id
          AND operation.undo_status IN ('reverted', 'skipped_stale')
      )
      AND NOT EXISTS (
        SELECT 1
        FROM shopping_ai_readd_operations operation
        WHERE operation.run_id = run.id
          AND operation.undo_status = 'eligible'
      )
    RETURNING run.id AS id
  `;

  return updated
    ? fetchShoppingListReaddRun(database, requiredString(updated.id, 'shopping_ai_readd_runs.id'))
    : null;
}

export async function cleanupExpiredShoppingListReaddRuns(
  database: DatabaseQuery,
  limit = 100,
): Promise<number> {
  if (!Number.isInteger(limit) || limit < 1 || limit > 1_000) {
    throw new Error('Shopping AI re-add cleanup limit must be an integer between 1 and 1000.');
  }

  const deleted = await database<{ id: unknown }>`
    DELETE FROM shopping_ai_readd_runs
    WHERE id IN (
      SELECT id
      FROM shopping_ai_readd_runs
      WHERE status IN ('completed', 'completed_with_issues', 'failed', 'undone')
        AND purge_after < now()
      ORDER BY purge_after ASC
      LIMIT ${limit}
    )
    RETURNING id
  `;

  return deleted.length;
}

function shoppingListReaddSummaryFromRow(row: ShoppingListReaddRunRow): ShoppingListReaddSummary {
  const status = requiredRunStatus(row.status);
  const undoExpiresAt = optionalISOString(row.undoExpiresAt);
  const isUndoAvailable = (status === 'completed' || status === 'completed_with_issues')
    && Boolean(undoExpiresAt && Date.parse(undoExpiresAt) > Date.now());
  const publicSummary = parsePublicSummary(row.publicSummary);

  return {
    ok: true,
    id: requiredString(row.id, 'shopping_ai_readd_runs.id'),
    status,
    operations: publicSummary.operations,
    unmatched: publicSummary.unmatched,
    undo: {
      available: isUndoAvailable,
      ...(isUndoAvailable && undoExpiresAt ? { expiresAt: undoExpiresAt } : {}),
    },
    submittedAt: requiredISOString(row.submittedAt, 'shopping_ai_readd_runs.submitted_at'),
    startedAt: optionalISOString(row.startedAt) ?? null,
    finishedAt: optionalISOString(row.finishedAt) ?? null,
  };
}

function shoppingListReaddOperationFromRow(
  row: ShoppingListReaddOperationRow,
): ShoppingListReaddPersistedOperation {
  const outcome = requiredOperationOutcome(row.outcome);
  const matchKind = optionalMatchKind(row.matchKind);
  const undoStatus = requiredUndoStatus(row.undoStatus);
  const operation: ShoppingListReaddPersistedOperation = {
    id: requiredString(row.id, 'shopping_ai_readd_operations.id'),
    runId: requiredString(row.runId, 'shopping_ai_readd_operations.run_id'),
    requestIndex: requiredInteger(row.requestIndex, 'shopping_ai_readd_operations.request_index'),
    requestedText: requiredString(row.requestedText, 'shopping_ai_readd_operations.requested_text'),
    outcome,
    undoStatus,
    createdAt: requiredISOString(row.createdAt, 'shopping_ai_readd_operations.created_at'),
    updatedAt: requiredISOString(row.updatedAt, 'shopping_ai_readd_operations.updated_at'),
  };

  const itemId = optionalInteger(row.itemId);
  const snapshotVersion = optionalInteger(row.snapshotVersion);
  const priorPurchased = optionalBoolean(row.priorPurchased);
  const priorQuantity = optionalInteger(row.priorQuantity);
  const appliedPurchased = optionalBoolean(row.appliedPurchased);
  const appliedQuantity = optionalInteger(row.appliedQuantity);
  const appliedVersion = optionalInteger(row.appliedVersion);

  return {
    ...operation,
    ...(itemId === undefined ? {} : { itemId }),
    ...(snapshotVersion === undefined ? {} : { snapshotVersion }),
    ...(priorPurchased === undefined ? {} : { priorPurchased }),
    ...(priorQuantity === undefined ? {} : { priorQuantity }),
    ...(appliedPurchased === undefined ? {} : { appliedPurchased }),
    ...(appliedQuantity === undefined ? {} : { appliedQuantity }),
    ...(appliedVersion === undefined ? {} : { appliedVersion }),
    ...(matchKind ? { matchKind } : {}),
  };
}

function sanitizeOperations(
  input: ShoppingListReaddOperationPersistenceInput[],
): Array<Required<Pick<ShoppingListReaddOperationPersistenceInput, 'requestIndex' | 'requestedText' | 'outcome'>> & ShoppingListReaddOperationPersistenceInput> {
  if (!Array.isArray(input) || input.length > shoppingListReaddLimits.maxRequestedPhrases) {
    throw new Error(`Shopping AI re-add operations must contain at most ${shoppingListReaddLimits.maxRequestedPhrases} phrases.`);
  }

  const requestIndexes = new Set<number>();
  const itemIds = new Set<number>();
  return input.map((operation) => {
    if (!Number.isInteger(operation.requestIndex) || operation.requestIndex < 0 || requestIndexes.has(operation.requestIndex)) {
      throw new Error('Shopping AI re-add operation requestIndex must be a unique non-negative integer.');
    }
    requestIndexes.add(operation.requestIndex);
    if (!operationOutcomes.has(operation.outcome)) {
      throw new Error('Shopping AI re-add operation outcome is not public-safe.');
    }

    const requestedText = boundedText(operation.requestedText, 'operation requestedText');
    const itemName = operation.itemName === undefined ? undefined : boundedText(operation.itemName, 'operation itemName', 160);
    const itemId = optionalPositiveInteger(operation.itemId, 'operation itemId');
    const snapshotVersion = optionalPositiveInteger(operation.snapshotVersion, 'operation snapshotVersion');
    const priorQuantity = optionalQuantity(operation.priorQuantity, 'operation priorQuantity');
    const appliedQuantity = optionalQuantity(operation.appliedQuantity, 'operation appliedQuantity');
    const appliedVersion = optionalPositiveInteger(operation.appliedVersion, 'operation appliedVersion');
    const quantity = optionalQuantity(operation.quantity, 'operation quantity');
    const matchKind = operation.matchKind === undefined ? undefined : requiredMatchKind(operation.matchKind);
    const undoEligible = operation.undoEligible === true;

    if (itemId !== undefined) {
      if (itemIds.has(itemId)) {
        throw new Error('Shopping AI re-add run cannot persist duplicate target item IDs.');
      }
      itemIds.add(itemId);
    }

    if (undoEligible && (
      itemId === undefined || snapshotVersion === undefined || operation.priorPurchased === undefined
      || priorQuantity === undefined || operation.appliedPurchased === undefined || appliedQuantity === undefined
      || appliedVersion === undefined
    )) {
      throw new Error('Undo-eligible Shopping AI re-add operations require complete prior and applied values.');
    }

    return {
      ...operation,
      requestedText,
      ...(itemName === undefined ? {} : { itemName }),
      ...(itemId === undefined ? {} : { itemId }),
      ...(snapshotVersion === undefined ? {} : { snapshotVersion }),
      ...(priorQuantity === undefined ? {} : { priorQuantity }),
      ...(appliedQuantity === undefined ? {} : { appliedQuantity }),
      ...(appliedVersion === undefined ? {} : { appliedVersion }),
      ...(quantity === undefined ? {} : { quantity }),
      ...(matchKind === undefined ? {} : { matchKind }),
      undoEligible,
    };
  });
}

function publicSummaryFromOperations(
  operations: ShoppingListReaddOperationPersistenceInput[],
): { operations: ShoppingListReaddOperationSummary[]; unmatched: ShoppingListReaddUnmatchedPhrase[] } {
  const publicOperations = operations.map((operation) => ({
    requestIndex: operation.requestIndex,
    requestedText: operation.requestedText,
    outcome: operation.outcome,
    ...(operation.itemId === undefined ? {} : { itemId: operation.itemId }),
    ...(operation.itemName === undefined ? {} : { itemName: operation.itemName }),
    ...(operation.quantity === undefined ? {} : { quantity: operation.quantity }),
    ...(operation.matchKind === undefined ? {} : { matchKind: operation.matchKind }),
  }));
  const unmatched = publicOperations
    .filter((operation) => operation.outcome === 'unmatched')
    .map(({ requestIndex, requestedText }) => ({ requestIndex, requestedText }));
  const result = { operations: publicOperations, unmatched };

  if (Buffer.byteLength(JSON.stringify(result), 'utf8') > 16_384) {
    throw new Error('Shopping AI re-add public summary exceeds its bounded storage limit.');
  }

  return result;
}

function countsFromOperations(operations: ShoppingListReaddOperationPersistenceInput[]): Record<string, number> {
  const counts = {
    processed: operations.length,
    readded: 0,
    quantityUpdated: 0,
    alreadyNeeded: 0,
    unmatched: 0,
    staleSkipped: 0,
    invalidRequest: 0,
    unavailable: 0,
    undone: 0,
  };

  for (const operation of operations) {
    switch (operation.outcome) {
    case 're_added': counts.readded += 1; break;
    case 'quantity_updated': counts.quantityUpdated += 1; break;
    case 'already_needed': counts.alreadyNeeded += 1; break;
    case 'unmatched': counts.unmatched += 1; break;
    case 'stale_skipped': counts.staleSkipped += 1; break;
    case 'invalid_request': counts.invalidRequest += 1; break;
    case 'unavailable': counts.unavailable += 1; break;
    case 'undone': counts.undone += 1; break;
    }
  }

  return counts;
}

function validatedUndoExpiry(
  value: Date | undefined,
  operations: ShoppingListReaddOperationPersistenceInput[],
): Date | undefined {
  const hasUndoableOperation = operations.some((operation) => operation.undoEligible);
  if (!hasUndoableOperation) {
    if (value) {
      throw new Error('Shopping AI re-add runs without an applied operation cannot have an Undo expiry.');
    }
    return undefined;
  }

  if (!(value instanceof Date) || !Number.isFinite(value.getTime()) || value.getTime() <= Date.now()) {
    throw new Error('Undo-eligible Shopping AI re-add runs require a future Undo expiry.');
  }

  return value;
}

function parsePublicSummary(value: unknown): {
  operations: ShoppingListReaddOperationSummary[];
  unmatched: ShoppingListReaddUnmatchedPhrase[];
} {
  const parsed = parseJSONBValue(value);
  if (!isRecord(parsed) || !Array.isArray(parsed.operations) || !Array.isArray(parsed.unmatched)) {
    throw new Error('Expected shopping_ai_readd_runs.public_summary to contain operations and unmatched arrays.');
  }

  return {
    operations: parsed.operations.map(parsePublicOperation),
    unmatched: parsed.unmatched.map(parseUnmatchedPhrase),
  };
}

function parsePublicOperation(value: unknown): ShoppingListReaddOperationSummary {
  if (!isRecord(value)) {
    throw new Error('Expected a public Shopping AI re-add operation object.');
  }
  const operation: ShoppingListReaddOperationSummary = {
    requestIndex: requiredInteger(value.requestIndex, 'shopping_ai_readd_runs.public_summary.operations.requestIndex'),
    requestedText: requiredString(value.requestedText, 'shopping_ai_readd_runs.public_summary.operations.requestedText'),
    outcome: requiredOperationOutcome(value.outcome),
  };
  const itemId = optionalInteger(value.itemId);
  const itemName = optionalString(value.itemName);
  const quantity = optionalInteger(value.quantity);
  const matchKind = optionalMatchKind(value.matchKind);

  return {
    ...operation,
    ...(itemId === undefined ? {} : { itemId }),
    ...(itemName === undefined ? {} : { itemName }),
    ...(quantity === undefined ? {} : { quantity }),
    ...(matchKind === undefined ? {} : { matchKind }),
  };
}

function parseUnmatchedPhrase(value: unknown): ShoppingListReaddUnmatchedPhrase {
  if (!isRecord(value)) {
    throw new Error('Expected a public unmatched Shopping AI re-add phrase object.');
  }
  return {
    requestIndex: requiredInteger(value.requestIndex, 'shopping_ai_readd_runs.public_summary.unmatched.requestIndex'),
    requestedText: requiredString(value.requestedText, 'shopping_ai_readd_runs.public_summary.unmatched.requestedText'),
  };
}

function boundedText(value: unknown, fieldName: string, maxLength: number = shoppingListReaddLimits.maxRequestTextLength): string {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maxLength) {
    throw new Error(`${fieldName} must be a nonempty string of at most ${maxLength} characters.`);
  }
  return value.trim();
}

function optionalPositiveInteger(value: unknown, fieldName: string): number | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 1) {
    throw new Error(`${fieldName} must be a positive integer when provided.`);
  }
  return value;
}

function optionalQuantity(value: unknown, fieldName: string): number | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (typeof value !== 'number' || !Number.isInteger(value) || value < shoppingListReaddLimits.minQuantity || value > shoppingListReaddLimits.maxQuantity) {
    throw new Error(`${fieldName} must be between ${shoppingListReaddLimits.minQuantity} and ${shoppingListReaddLimits.maxQuantity} when provided.`);
  }
  return value;
}

function requiredRunStatus(value: unknown): ShoppingListReaddRunStatus {
  const status = requiredString(value, 'shopping_ai_readd_runs.status');
  if (!['queued', 'matching', 'applying', 'completed', 'completed_with_issues', 'failed', 'undone'].includes(status)) {
    throw new Error(`Unexpected Shopping AI re-add run status: ${status}`);
  }
  return status as ShoppingListReaddRunStatus;
}

function requiredOperationOutcome(value: unknown): ShoppingListReaddOperationOutcome {
  const outcome = requiredString(value, 'shopping_ai_readd_operations.outcome');
  if (!operationOutcomes.has(outcome as ShoppingListReaddOperationOutcome)) {
    throw new Error(`Unexpected Shopping AI re-add operation outcome: ${outcome}`);
  }
  return outcome as ShoppingListReaddOperationOutcome;
}

function requiredMatchKind(value: unknown): ShoppingListReaddMatchKind {
  if (typeof value !== 'string' || !matchKinds.has(value as ShoppingListReaddMatchKind)) {
    throw new Error('Shopping AI re-add matchKind must be exact, normalized, or semantic.');
  }
  return value as ShoppingListReaddMatchKind;
}

function optionalMatchKind(value: unknown): ShoppingListReaddMatchKind | undefined {
  return value === null || value === undefined ? undefined : requiredMatchKind(value);
}

function requiredUndoStatus(value: unknown): ShoppingListReaddUndoStatus {
  const status = requiredString(value, 'shopping_ai_readd_operations.undo_status');
  if (!['not_eligible', 'eligible', 'reverted', 'skipped_stale'].includes(status)) {
    throw new Error(`Unexpected Shopping AI re-add Undo status: ${status}`);
  }
  return status as ShoppingListReaddUndoStatus;
}

function requiredActor(value: unknown): 'Josh' | 'Mallory' {
  if (value === 'Josh' || value === 'Mallory') {
    return value;
  }
  throw new Error('Expected shopping_ai_readd_runs.actor to be Josh or Mallory.');
}

function requiredISOString(value: unknown, fieldName: string): string {
  const timestamp = optionalISOString(value);
  if (!timestamp) {
    throw new Error(`Expected ${fieldName} to be an ISO timestamp.`);
  }
  return timestamp;
}

function requireRun(run: ShoppingListReaddSummary | null, operation: string): ShoppingListReaddSummary {
  if (!run) {
    throw new Error(`Expected Shopping AI re-add run to remain readable after ${operation}.`);
  }
  return run;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}
