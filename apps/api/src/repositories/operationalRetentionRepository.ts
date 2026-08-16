import { getDatabaseClient, type DatabaseQuery } from '../db/client.js';

export const operationalRetentionBatchSize = 100;

export type OperationalRetentionStore = {
  cleanupTerminalLiveActivityDeliveries: (before: Date, limit?: number) => Promise<number>;
  cleanupTerminalTripSummaryDeliveries: (before: Date, limit?: number) => Promise<number>;
  cleanupTerminalToDoReminderDeliveries: (before: Date, limit?: number) => Promise<number>;
  cleanupTerminalStockPriceCheckRuns: (before: Date, limit?: number) => Promise<number>;
  cleanupInactivePushDevices: (before: Date, limit?: number) => Promise<number>;
};

type DeletedRow = { id: unknown };

/**
 * Performs only indexed, bounded deletes. Each query locks its own candidate
 * rows so independently deployed API processes can run retention safely.
 */
export function createPostgresOperationalRetentionStore(
  database?: DatabaseQuery,
): OperationalRetentionStore {
  const query = () => database ?? getDatabaseClient();

  return {
    async cleanupTerminalLiveActivityDeliveries(before, limit) {
      const deleted = await query()<DeletedRow>`
        WITH candidates AS (
          SELECT id
          FROM shopping_live_activity_deliveries
          WHERE status IN ('sent', 'failed')
            AND updated_at < ${retentionCutoff(before)}
          ORDER BY updated_at ASC
          LIMIT ${boundedLimit(limit)}
          FOR UPDATE SKIP LOCKED
        )
        DELETE FROM shopping_live_activity_deliveries delivery
        USING candidates
        WHERE delivery.id = candidates.id
        RETURNING delivery.id
      `;

      return deleted.length;
    },
    async cleanupTerminalTripSummaryDeliveries(before, limit) {
      const deleted = await query()<DeletedRow>`
        WITH candidates AS (
          SELECT id
          FROM shopping_trip_summary_deliveries
          WHERE status IN ('sent', 'failed', 'skipped')
            AND updated_at < ${retentionCutoff(before)}
          ORDER BY updated_at ASC
          LIMIT ${boundedLimit(limit)}
          FOR UPDATE SKIP LOCKED
        )
        DELETE FROM shopping_trip_summary_deliveries delivery
        USING candidates
        WHERE delivery.id = candidates.id
        RETURNING delivery.id
      `;

      return deleted.length;
    },
    async cleanupTerminalToDoReminderDeliveries(before, limit) {
      const deleted = await query()<DeletedRow>`
        WITH candidates AS (
          SELECT id
          FROM todo_due_reminder_deliveries
          WHERE status IN ('sent', 'failed', 'skipped')
            AND updated_at < ${retentionCutoff(before)}
          ORDER BY updated_at ASC
          LIMIT ${boundedLimit(limit)}
          FOR UPDATE SKIP LOCKED
        )
        DELETE FROM todo_due_reminder_deliveries delivery
        USING candidates
        WHERE delivery.id = candidates.id
        RETURNING delivery.id
      `;

      return deleted.length;
    },
    async cleanupTerminalStockPriceCheckRuns(before, limit) {
      const deleted = await query()<DeletedRow>`
        WITH candidates AS (
          SELECT id
          FROM shopping_stock_price_check_runs
          WHERE status IN ('completed', 'completed_with_issues', 'failed')
            AND finished_at < ${retentionCutoff(before)}
          ORDER BY finished_at ASC
          LIMIT ${boundedLimit(limit)}
          FOR UPDATE SKIP LOCKED
        )
        DELETE FROM shopping_stock_price_check_runs run
        USING candidates
        WHERE run.id = candidates.id
        RETURNING run.id
      `;

      return deleted.length;
    },
    async cleanupInactivePushDevices(before, limit) {
      const deleted = await query()<DeletedRow>`
        WITH candidates AS (
          SELECT id, lookup_key
          FROM push_devices
          WHERE NOT is_active
            AND invalidated_at IS NOT NULL
            AND invalidated_at < ${retentionCutoff(before)}
          ORDER BY invalidated_at ASC
          LIMIT ${boundedLimit(limit)}
          FOR UPDATE SKIP LOCKED
        ),
        deleted_preferences AS (
          DELETE FROM notification_preferences preference
          USING candidates
          WHERE preference.device_key = 'device-token:' || candidates.lookup_key
            OR preference.device_key = 'device-id:' || candidates.id
          RETURNING preference.device_key
        )
        DELETE FROM push_devices device
        USING candidates
        WHERE device.id = candidates.id
        RETURNING device.id
      `;

      return deleted.length;
    },
  };
}

function boundedLimit(limit: number | undefined): number {
  const resolved = limit ?? operationalRetentionBatchSize;

  if (!Number.isInteger(resolved) || resolved < 1 || resolved > 1_000) {
    throw new Error('Operational retention cleanup limit must be an integer between 1 and 1000.');
  }

  return resolved;
}

function retentionCutoff(before: Date): string {
  if (!Number.isFinite(before.getTime())) {
    throw new Error('Operational retention cutoff must be a valid Date.');
  }

  return before.toISOString();
}
