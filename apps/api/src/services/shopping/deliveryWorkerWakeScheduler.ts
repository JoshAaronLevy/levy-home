const defaultRecoverySweepIntervalMs = 10 * 60 * 1_000;

type TimeoutHandle = ReturnType<typeof setTimeout>;

export type DeliveryWorkerWakeScheduler = {
  start: () => void;
  stop: () => void;
  runNow: () => void;
  scheduleRetryAt: (retryAt: Date) => void;
};

export function createDeliveryWorkerWakeScheduler(options: {
  run: () => Promise<void>;
  onError: (error: unknown) => void;
  now?: () => Date;
  recoverySweepIntervalMs?: number;
  setTimeout?: (callback: () => void, delayMs: number) => TimeoutHandle;
  clearTimeout?: (timeout: TimeoutHandle) => void;
}): DeliveryWorkerWakeScheduler {
  const now = options.now ?? (() => new Date());
  const recoverySweepIntervalMs = options.recoverySweepIntervalMs ?? defaultRecoverySweepIntervalMs;
  const setTimeoutForWorker = options.setTimeout ?? setTimeout;
  const clearTimeoutForWorker = options.clearTimeout ?? clearTimeout;
  let started = false;
  let wakeTimer: TimeoutHandle | undefined;
  let wakeAtMs: number | undefined;

  const scheduleAt = (targetMs: number): void => {
    if (!started || (wakeAtMs !== undefined && wakeAtMs <= targetMs)) {
      return;
    }

    if (wakeTimer) {
      clearTimeoutForWorker(wakeTimer);
    }

    wakeAtMs = targetMs;
    wakeTimer = setTimeoutForWorker(() => {
      wakeTimer = undefined;
      wakeAtMs = undefined;
      runNow();
    }, Math.max(0, targetMs - now().getTime()));
    wakeTimer.unref?.();
  };

  const scheduleRecoverySweep = (): void => {
    scheduleAt(now().getTime() + recoverySweepIntervalMs);
  };

  const runNow = (): void => {
    void options.run()
      .catch(options.onError)
      .finally(() => {
        scheduleRecoverySweep();
      });
  };

  return {
    start() {
      if (started) {
        return;
      }

      started = true;
      runNow();
    },
    stop() {
      started = false;
      wakeAtMs = undefined;
      if (wakeTimer) {
        clearTimeoutForWorker(wakeTimer);
        wakeTimer = undefined;
      }
    },
    runNow,
    scheduleRetryAt(retryAt) {
      scheduleAt(retryAt.getTime());
    },
  };
}
