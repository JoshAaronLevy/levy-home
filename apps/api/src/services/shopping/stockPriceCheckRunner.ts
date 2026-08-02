import type { Logger } from '../../observability/logger.js';
import type { StockPriceCheckService } from './stockPriceCheckService.js';

/** Process-local scheduling only; persisted run state remains the source of truth. */
export type StockPriceCheckRunner = {
  enqueue: (runId: string) => void;
  recover: () => void;
};

export function createStockPriceCheckRunner(options: {
  stockPriceCheckService: StockPriceCheckService;
  logger: Pick<Logger, 'error' | 'info'>;
  fetchActiveRun?: () => Promise<{ id: string } | null>;
  schedule?: (task: () => void) => void;
}): StockPriceCheckRunner {
  const activeRunIds = new Set<string>();
  const schedule = options.schedule ?? ((task: () => void) => setImmediate(task));

  const enqueue = (runId: string): void => {
    if (activeRunIds.has(runId)) return;
    activeRunIds.add(runId);
    schedule(() => {
      void options.stockPriceCheckService.processRun(runId)
        .then((run) => {
          if (!run) return;
          options.logger.info('Shopping stock and price check finished.', {
            jobId: run.id,
            phase: run.phase,
            status: run.status,
            processedItemCount: run.processedItemCount,
            updatedItemCount: run.updatedItemCount,
            unmatchedItemCount: run.unmatchedItemCount,
            failedItemCount: run.failedItemCount,
            skippedStaleItemCount: run.skippedStaleItemCount,
            ...(run.failureCode ? { failureCode: run.failureCode } : {}),
          });
        })
        .catch((_error: unknown) => {
          options.logger.error('Shopping stock and price check runner failed.', { jobId: runId });
        })
        .finally(() => activeRunIds.delete(runId));
    });
  };

  return {
    enqueue,
    recover() {
      schedule(() => {
        const resume = options.fetchActiveRun
          ? options.fetchActiveRun().then((active) => {
            if (!active) return null;
            options.logger.info('Shopping stock and price check recovery scheduled.', { jobId: active.id });
            enqueue(active.id);
            return null;
          })
          : options.stockPriceCheckService.resumeActiveRun();

        void resume
          .then((run) => {
            if (!run) return;
            options.logger.info('Shopping stock and price check recovery finished.', {
              jobId: run.id,
              phase: run.phase,
              status: run.status,
              processedItemCount: run.processedItemCount,
              ...(run.failureCode ? { failureCode: run.failureCode } : {}),
            });
          })
          .catch((_error: unknown) => {
            options.logger.error('Shopping stock and price check recovery failed.', {});
          });
      });
    },
  };
}
