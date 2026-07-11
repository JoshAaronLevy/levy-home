import type { DatabaseQuery, DatabaseTransactionRunner } from '../db/client.js';
import { getDatabaseClient, getDatabaseTransactionRunner } from '../db/client.js';
import { optionalISOString, optionalString, requiredInteger, requiredString } from '../db/rowReaders.js';

export type ShoppingTripSummaryDelivery = {
  id: string;
  tripId: string;
  recipient: 'Josh' | 'Mallory';
  pushDeviceId: string;
  title: string;
  body: string;
  status: 'pending' | 'sending' | 'sent' | 'failed' | 'skipped' | 'ambiguous';
  attemptCount: number;
  apnsId: string | null;
  lastErrorReason: string | null;
  createdAt: string;
  sentAt: string | null;
};

type SummaryRow = Record<string, unknown> & {
  id: unknown;
  tripId: unknown;
  recipient: unknown;
  pushDeviceId: unknown;
  title: unknown;
  body: unknown;
  status: unknown;
  attemptCount: unknown;
  apnsId: unknown;
  lastErrorReason: unknown;
  createdAt: unknown;
  sentAt: unknown;
};

export type ShoppingTripSummaryStore = {
  claimDueDeliveries: (limit: number) => Promise<ShoppingTripSummaryDelivery[]>;
  markSent: (deliveryId: string, apnsId?: string) => Promise<void>;
  markSkipped: (deliveryId: string, reason: string) => Promise<void>;
  markPermanentFailure: (deliveryId: string, reason: string) => Promise<void>;
  markRetryableFailure: (deliveryId: string, reason: string, nextAttemptAt: Date, ambiguous?: boolean) => Promise<void>;
  recoverStaleClaims: () => Promise<void>;
};

export function createPostgresShoppingTripSummaryStore(options: {
  database?: DatabaseQuery;
  transactionRunner?: DatabaseTransactionRunner;
} = {}): ShoppingTripSummaryStore {
  if (Boolean(options.database) !== Boolean(options.transactionRunner)) {
    throw new Error('database and transactionRunner must be injected together.');
  }

  const query = () => options.database ?? getDatabaseClient();
  const transaction = () => options.transactionRunner ?? getDatabaseTransactionRunner();

  return {
    async claimDueDeliveries(limit) {
      return transaction()(async (database) => {
        const rows = await database<SummaryRow>`
          WITH claimed AS (
            SELECT id
            FROM shopping_trip_summary_deliveries
            WHERE status IN ('pending', 'ambiguous')
              AND next_attempt_at <= now()
            ORDER BY created_at ASC
            LIMIT ${Math.max(1, Math.min(limit, 50))}
            FOR UPDATE SKIP LOCKED
          )
          UPDATE shopping_trip_summary_deliveries delivery
          SET status = 'sending', attempt_count = attempt_count + 1, updated_at = now()
          FROM claimed
          WHERE delivery.id = claimed.id
          RETURNING
            delivery.id,
            delivery.trip_id AS "tripId",
            delivery.recipient,
            delivery.push_device_id AS "pushDeviceId",
            delivery.title,
            delivery.body,
            delivery.status,
            delivery.attempt_count AS "attemptCount",
            delivery.apns_id AS "apnsId",
            delivery.last_error_reason AS "lastErrorReason",
            delivery.created_at AS "createdAt",
            delivery.sent_at AS "sentAt"
        `;
        return rows.map(summaryDeliveryFromRow);
      });
    },
    async markSent(deliveryId, apnsId) {
      await query()`
        UPDATE shopping_trip_summary_deliveries
        SET status = 'sent', apns_id = ${apnsId ?? null}, sent_at = now(), last_error_reason = NULL, updated_at = now()
        WHERE id = ${deliveryId}
      `;
    },
    async markSkipped(deliveryId, reason) {
      await terminal(query(), deliveryId, 'skipped', reason);
    },
    async markPermanentFailure(deliveryId, reason) {
      await terminal(query(), deliveryId, 'failed', reason);
    },
    async markRetryableFailure(deliveryId, reason, nextAttemptAt, ambiguous = false) {
      await query()`
        UPDATE shopping_trip_summary_deliveries
        SET
          status = ${ambiguous ? 'ambiguous' : 'pending'},
          last_error_reason = ${reason},
          next_attempt_at = ${nextAttemptAt.toISOString()},
          updated_at = now()
        WHERE id = ${deliveryId}
      `;
    },
    async recoverStaleClaims() {
      await query()`
        UPDATE shopping_trip_summary_deliveries
        SET
          status = 'ambiguous',
          last_error_reason = 'summary worker restarted before APNs response was recorded',
          next_attempt_at = now() + interval '30 seconds',
          updated_at = now()
        WHERE status = 'sending'
          AND updated_at < now() - interval '60 seconds'
      `;
    },
  };
}

async function terminal(database: DatabaseQuery, deliveryId: string, status: 'failed' | 'skipped', reason: string): Promise<void> {
  await database`
    UPDATE shopping_trip_summary_deliveries
    SET status = ${status}, last_error_reason = ${reason}, updated_at = now()
    WHERE id = ${deliveryId}
  `;
}

function summaryDeliveryFromRow(row: SummaryRow): ShoppingTripSummaryDelivery {
  return {
    id: requiredString(row.id, 'shopping_trip_summary_deliveries.id'),
    tripId: requiredString(row.tripId, 'shopping_trip_summary_deliveries.trip_id'),
    recipient: requiredRecipient(row.recipient),
    pushDeviceId: requiredString(row.pushDeviceId, 'shopping_trip_summary_deliveries.push_device_id'),
    title: requiredString(row.title, 'shopping_trip_summary_deliveries.title'),
    body: requiredString(row.body, 'shopping_trip_summary_deliveries.body'),
    status: requiredStatus(row.status),
    attemptCount: requiredInteger(row.attemptCount, 'shopping_trip_summary_deliveries.attempt_count'),
    apnsId: optionalString(row.apnsId) ?? null,
    lastErrorReason: optionalString(row.lastErrorReason) ?? null,
    createdAt: requiredISOString(row.createdAt, 'shopping_trip_summary_deliveries.created_at'),
    sentAt: optionalISOString(row.sentAt) ?? null,
  };
}

function requiredRecipient(value: unknown): 'Josh' | 'Mallory' {
  if (value === 'Josh' || value === 'Mallory') return value;
  throw new Error('Expected a valid shopping trip summary recipient.');
}

function requiredStatus(value: unknown): ShoppingTripSummaryDelivery['status'] {
  if (value === 'pending' || value === 'sending' || value === 'sent' || value === 'failed' || value === 'skipped' || value === 'ambiguous') return value;
  throw new Error('Expected a valid shopping trip summary delivery status.');
}

function requiredISOString(value: unknown, fieldName: string): string {
  const timestamp = optionalISOString(value);
  if (!timestamp) throw new Error(`Expected ${fieldName} to be an ISO timestamp.`);
  return timestamp;
}
