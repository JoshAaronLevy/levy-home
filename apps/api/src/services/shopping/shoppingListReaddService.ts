import crypto from 'node:crypto';

import type { ShoppingListItem, ShoppingListReaddSummary } from '../../contracts.js';
import type {
  ShoppingListReaddOperationPersistenceInput,
  ShoppingListReaddPersistedOperation,
  ShoppingListReaddStore,
} from '../../repositories/shoppingListReaddRepository.js';
import type { ShoppingListStore } from '../../repositories/shoppingListRepository.js';
import {
  ShoppingListReaddContractValidationError,
  type ShoppingListReaddCandidateSnapshot,
  type ShoppingListReaddMatchPlan,
} from './shoppingListReaddContracts.js';
import type { ShoppingListReaddMatcher } from './shoppingListReaddMatcher.js';
import {
  buildShoppingListReaddMatchContext,
  parseShoppingListReaddRequestedPhrases,
  validateShoppingListReaddMatchPlanForRequest,
} from './shoppingListReaddPlanning.js';
import type { ShoppingListMutationService } from './shoppingListMutationService.js';

/** Short, durable window for correcting an automatic household-list match. */
export const shoppingListReaddUndoWindowMs = 5 * 60_000;

export type ShoppingListReaddService = {
  processRun: (runId: string) => Promise<ShoppingListReaddSummary | null>;
  undoRun: (runId: string) => Promise<ShoppingListReaddSummary | null>;
};

/**
 * Applies an already-durable re-add request through the ordinary Shopping
 * mutation service. This service does not create rows and does not expose a
 * direct database write path for either matching or Undo.
 */
export function createShoppingListReaddService(options: {
  matcher: ShoppingListReaddMatcher;
  shoppingListReaddStore: ShoppingListReaddStore;
  shoppingListStore: Pick<ShoppingListStore, 'fetchShoppingList'>;
  shoppingListMutationService: Pick<ShoppingListMutationService, 'applyShoppingListReaddUpdate'>;
  createMutationId?: () => string;
  now?: () => Date;
  undoWindowMs?: number;
}): ShoppingListReaddService {
  const createMutationId = options.createMutationId ?? crypto.randomUUID;
  const now = options.now ?? (() => new Date());
  const undoWindowMs = options.undoWindowMs ?? shoppingListReaddUndoWindowMs;

  if (!Number.isInteger(undoWindowMs) || undoWindowMs < 1) {
    throw new Error('Shopping AI re-add Undo window must be a positive integer.');
  }

  return {
    async processRun(runId) {
      const claim = await options.shoppingListReaddStore.claimRunForProcessing(runId);
      if (!claim || !claim.claimed) return claim?.run ?? null;

      const executionRun = await options.shoppingListReaddStore.fetchRunExecutionInput(runId);
      if (!executionRun) return options.shoppingListReaddStore.fetchRun(runId);

      try {
        const shopping = await options.shoppingListStore.fetchShoppingList();
        const snapshot = candidateSnapshotFromItems(shopping.items);
        const context = buildShoppingListReaddMatchContext(executionRun.requestedText, snapshot);
        const untrustedPlan = await options.matcher.match(executionRun.requestedText, snapshot);
        const plan = validateShoppingListReaddMatchPlanForRequest(untrustedPlan, context);
        const applying = await options.shoppingListReaddStore.moveRunToApplying(runId);
        if (!applying) return options.shoppingListReaddStore.fetchRun(runId);

        const operations = await applyPlan({
          actor: executionRun.actor,
          plan,
          snapshot,
          runId,
          shoppingListReaddStore: options.shoppingListReaddStore,
          shoppingListMutationService: options.shoppingListMutationService,
          createMutationId,
        });
        const hasUndoableOperation = operations.some((operation) => operation.undoEligible);
        const status = operations.some((operation) => isIssueOutcome(operation.outcome))
          ? 'completed_with_issues'
          : 'completed';
        return options.shoppingListReaddStore.finalizeRun({
          runId,
          status,
          operations,
          ...(hasUndoableOperation ? { undoExpiresAt: new Date(now().getTime() + undoWindowMs) } : {}),
        });
      } catch (error) {
        const outcome = error instanceof ShoppingListReaddContractValidationError
          ? 'invalid_request'
          : 'unavailable';
        const failureOperations = failureOperationsForRequest(executionRun.requestedText, outcome);
        return options.shoppingListReaddStore.finalizeRun({
          runId,
          status: 'failed',
          operations: failureOperations,
        });
      }
    },

    async undoRun(runId) {
      const undoRun = await options.shoppingListReaddStore.fetchUndoableRun(runId);
      if (!undoRun) return null;

      for (const operation of undoRun.operations) {
        if (operation.undoStatus !== 'eligible') continue;
        const result = await undoOperation({
          operation,
          actor: undoRun.actor,
          shoppingListMutationService: options.shoppingListMutationService,
          createMutationId,
        });
        await options.shoppingListReaddStore.recordUndoOperation({ operationId: operation.id, status: result });
      }

      return (await options.shoppingListReaddStore.markRunUndone(runId))
        ?? options.shoppingListReaddStore.fetchRun(runId);
    },
  };
}

async function applyPlan(input: {
  actor: 'Josh' | 'Mallory';
  plan: ShoppingListReaddMatchPlan;
  snapshot: readonly ShoppingListReaddCandidateSnapshot[];
  runId: string;
  shoppingListReaddStore: Pick<ShoppingListReaddStore, 'recordApplyingOperation'>;
  shoppingListMutationService: Pick<ShoppingListMutationService, 'applyShoppingListReaddUpdate'>;
  createMutationId: () => string;
}): Promise<ShoppingListReaddOperationPersistenceInput[]> {
  const candidateById = new Map(input.snapshot.map((candidate) => [candidate.itemId, candidate]));
  const operations: ShoppingListReaddOperationPersistenceInput[] = [];

  for (const operation of input.plan.operations) {
    const candidate = candidateById.get(operation.itemId);
    if (!candidate) {
      throw new ShoppingListReaddContractValidationError('Validated matcher operation is outside the candidate snapshot.');
    }

    const desiredQuantity = operation.quantity ?? candidate.quantity;
    const needsReadd = candidate.purchased;
    const needsQuantityUpdate = operation.quantity !== undefined && operation.quantity !== candidate.quantity;
    if (!needsReadd && !needsQuantityUpdate) {
      operations.push({
        requestIndex: operation.requestIndex,
        requestedText: operation.requestedText,
        outcome: 'already_needed',
        itemId: candidate.itemId,
        itemName: candidate.name,
        ...(operation.quantity === undefined ? {} : { quantity: operation.quantity }),
        matchKind: operation.matchKind,
      });
      continue;
    }

    try {
      const priorStateRecorded = await input.shoppingListReaddStore.recordApplyingOperation({
        runId: input.runId,
        operation: {
          requestIndex: operation.requestIndex,
          requestedText: operation.requestedText,
          outcome: needsReadd ? 're_added' : 'quantity_updated',
          itemId: candidate.itemId,
          snapshotVersion: candidate.itemVersion,
          priorPurchased: candidate.purchased,
          priorQuantity: candidate.quantity,
          appliedPurchased: false,
          appliedQuantity: desiredQuantity,
          matchKind: operation.matchKind,
          undoEligible: false,
        },
      });
      if (!priorStateRecorded) {
        throw new Error('Shopping AI re-add run no longer accepts a durable pre-write operation.');
      }
      const write = await input.shoppingListMutationService.applyShoppingListReaddUpdate(
        candidate.itemId,
        {
          expectedVersion: candidate.itemVersion,
          expectedPurchased: candidate.purchased,
          expectedQuantity: candidate.quantity,
          purchased: false,
          ...(needsQuantityUpdate ? { quantity: desiredQuantity } : {}),
          actor: input.actor,
        },
        input.createMutationId(),
      );
      if (write.status === 'stale') {
        operations.push(staleOperation(operation, candidate));
        continue;
      }

      const appliedVersion = positiveVersion(write.response.item.version);
      operations.push({
        requestIndex: operation.requestIndex,
        requestedText: operation.requestedText,
        outcome: needsReadd ? 're_added' : 'quantity_updated',
        itemId: candidate.itemId,
        itemName: candidate.name,
        ...(operation.quantity === undefined ? {} : { quantity: operation.quantity }),
        matchKind: operation.matchKind,
        snapshotVersion: candidate.itemVersion,
        priorPurchased: candidate.purchased,
        priorQuantity: candidate.quantity,
        appliedPurchased: false,
        appliedQuantity: desiredQuantity,
        appliedVersion,
        undoEligible: true,
      });
    } catch {
      operations.push({
        requestIndex: operation.requestIndex,
        requestedText: operation.requestedText,
        outcome: 'unavailable',
        itemId: candidate.itemId,
        itemName: candidate.name,
        ...(operation.quantity === undefined ? {} : { quantity: operation.quantity }),
        matchKind: operation.matchKind,
      });
    }
  }

  for (const unmatched of input.plan.unmatched) {
    operations.push({
      requestIndex: unmatched.requestIndex,
      requestedText: unmatched.requestedText,
      outcome: 'unmatched',
    });
  }

  return operations.sort((left, right) => left.requestIndex - right.requestIndex);
}

async function undoOperation(input: {
  operation: ShoppingListReaddPersistedOperation;
  actor: 'Josh' | 'Mallory';
  shoppingListMutationService: Pick<ShoppingListMutationService, 'applyShoppingListReaddUpdate'>;
  createMutationId: () => string;
}): Promise<'reverted' | 'skipped_stale'> {
  const operation = input.operation;
  if (
    operation.itemId === undefined
    || operation.appliedVersion === undefined
    || operation.appliedPurchased === undefined
    || operation.appliedQuantity === undefined
    || operation.priorPurchased === undefined
    || operation.priorQuantity === undefined
  ) {
    return 'skipped_stale';
  }

  try {
    const write = await input.shoppingListMutationService.applyShoppingListReaddUpdate(
      operation.itemId,
      {
        expectedVersion: operation.appliedVersion,
        expectedPurchased: operation.appliedPurchased,
        expectedQuantity: operation.appliedQuantity,
        purchased: operation.priorPurchased,
        quantity: operation.priorQuantity,
        actor: input.actor,
      },
      input.createMutationId(),
    );
    return write.status === 'updated' ? 'reverted' : 'skipped_stale';
  } catch {
    return 'skipped_stale';
  }
}

function candidateSnapshotFromItems(items: readonly ShoppingListItem[]): ShoppingListReaddCandidateSnapshot[] {
  return items.map((item) => ({
    itemId: item.id,
    itemVersion: positiveVersion(item.version),
    name: item.name,
    ...(item.brand ? { brand: item.brand } : {}),
    ...(item.notes ? { notes: item.notes } : {}),
    purchased: item.purchased,
    quantity: item.quantity,
  }));
}

function staleOperation(
  operation: ShoppingListReaddMatchPlan['operations'][number],
  candidate: ShoppingListReaddCandidateSnapshot,
): ShoppingListReaddOperationPersistenceInput {
  return {
    requestIndex: operation.requestIndex,
    requestedText: operation.requestedText,
    outcome: 'stale_skipped',
    itemId: candidate.itemId,
    itemName: candidate.name,
    ...(operation.quantity === undefined ? {} : { quantity: operation.quantity }),
    matchKind: operation.matchKind,
  };
}

function failureOperationsForRequest(
  requestText: string,
  outcome: Extract<ShoppingListReaddOperationPersistenceInput['outcome'], 'invalid_request' | 'unavailable'>,
): ShoppingListReaddOperationPersistenceInput[] {
  try {
    return parseShoppingListReaddRequestedPhrases(requestText).map((phrase) => ({
      requestIndex: phrase.requestIndex,
      requestedText: phrase.text,
      outcome,
    }));
  } catch {
    return [{ requestIndex: 0, requestedText: 'Shopping request', outcome }];
  }
}

function isIssueOutcome(outcome: ShoppingListReaddOperationPersistenceInput['outcome']): boolean {
  return outcome === 'unmatched'
    || outcome === 'stale_skipped'
    || outcome === 'invalid_request'
    || outcome === 'unavailable';
}

function positiveVersion(value: number | undefined): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 1) {
    throw new Error('Shopping AI re-add requires versioned Shopping items.');
  }
  return value;
}
