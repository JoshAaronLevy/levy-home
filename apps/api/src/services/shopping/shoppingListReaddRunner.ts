import type { Logger } from '../../observability/logger.js';
import type { ShoppingListReaddSummary } from '../../contracts.js';
import type { ShoppingListReaddService } from './shoppingListReaddService.js';

/**
 * Process-local scheduling only. The durable re-add run controls recovery,
 * while this runner prevents duplicate work inside one API process.
 */
export type ShoppingListReaddRunner = {
  enqueue: (runId: string) => void;
  recover: () => void;
};

export function createShoppingListReaddRunner(options: {
  shoppingListReaddService: ShoppingListReaddService;
  logger: Pick<Logger, 'error' | 'info'>;
  fetchRecoverableRun?: () => Promise<{ id: string } | null>;
  schedule?: (task: () => void) => void;
  now?: () => number;
}): ShoppingListReaddRunner {
  const activeRunIds = new Set<string>();
  const schedule = options.schedule ?? ((task: () => void) => setImmediate(task));
  const now = options.now ?? Date.now;

  const enqueue = (runId: string): void => {
    if (activeRunIds.has(runId)) return;
    activeRunIds.add(runId);
    schedule(() => {
      const startedAt = now();
      void options.shoppingListReaddService.processRun(runId)
        .then((run) => logCompletedRun(options.logger, runId, run, now() - startedAt, false))
        .catch(() => {
          options.logger.error('Shopping AI re-add runner failed.', { runId, phase: 'processing' });
        })
        .finally(() => activeRunIds.delete(runId));
    });
  };

  return {
    enqueue,
    recover() {
      schedule(() => {
        void recoverInterruptedRun(options, now)
          .catch(() => {
            options.logger.error('Shopping AI re-add recovery failed.', { phase: 'recovery' });
          });
      });
    },
  };
}

async function recoverInterruptedRun(
  options: {
    shoppingListReaddService: ShoppingListReaddService;
    logger: Pick<Logger, 'error' | 'info'>;
    fetchRecoverableRun?: () => Promise<{ id: string } | null>;
  },
  now: () => number,
): Promise<void> {
  const interrupted = options.fetchRecoverableRun
    ? await options.fetchRecoverableRun()
    : null;
  if (!interrupted) return;

  const startedAt = now();
  options.logger.info('Shopping AI re-add recovery scheduled.', { runId: interrupted.id, phase: 'recovery' });
  const run = await options.shoppingListReaddService.recoverRun(interrupted.id);
  logCompletedRun(options.logger, interrupted.id, run, now() - startedAt, true);
}

function logCompletedRun(
  logger: Pick<Logger, 'info'>,
  runId: string,
  run: ShoppingListReaddSummary | null,
  elapsedMs: number,
  recovered: boolean,
): void {
  if (!run) return;
  const counts = countOutcomes(run);
  logger.info('Shopping AI re-add run finished.', {
    runId,
    phase: 'finished',
    status: run.status,
    elapsedMs,
    recovered,
    ...counts,
    ...(counts.unavailable > 0 ? { errorCode: 'matcher_unavailable' } : {}),
    ...(counts.invalidRequest > 0 ? { errorCode: 'invalid_matcher_result' } : {}),
  });
}

function countOutcomes(run: ShoppingListReaddSummary): Record<string, number> {
  const counts = {
    readded: 0,
    quantityUpdated: 0,
    alreadyNeeded: 0,
    unmatched: 0,
    staleSkipped: 0,
    invalidRequest: 0,
    unavailable: 0,
  };
  for (const operation of run.operations) {
    switch (operation.outcome) {
    case 're_added': counts.readded += 1; break;
    case 'quantity_updated': counts.quantityUpdated += 1; break;
    case 'already_needed': counts.alreadyNeeded += 1; break;
    case 'unmatched': counts.unmatched += 1; break;
    case 'stale_skipped': counts.staleSkipped += 1; break;
    case 'invalid_request': counts.invalidRequest += 1; break;
    case 'unavailable': counts.unavailable += 1; break;
    case 'undone': break;
    }
  }
  return counts;
}
