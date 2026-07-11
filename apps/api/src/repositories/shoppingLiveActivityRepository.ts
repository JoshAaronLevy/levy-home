import crypto from 'node:crypto';

import type {
  ShoppingLiveActivityDelivery,
  ShoppingLiveActivityDeliveryEvent,
  ShoppingLiveActivityDeliveryStatus,
  ShoppingLiveActivityPayload,
  ShoppingLiveActivityRegistration,
  ShoppingLiveActivityRegistrationRequest,
  ShoppingLiveActivityTokenType,
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
  optionalISOString,
  optionalString,
  parseJSONBValue,
  requiredInteger,
  requiredString,
} from '../db/rowReaders.js';

export type StoredShoppingLiveActivityRegistration = ShoppingLiveActivityRegistration & {
  token: string;
};

export type StoredShoppingLiveActivityDelivery = ShoppingLiveActivityDelivery & {
  payload: ShoppingLiveActivityPayload;
  registration: StoredShoppingLiveActivityRegistration;
};

export type EnqueueShoppingLiveActivityDelivery = {
  tripId: string;
  registrationId: string;
  eventType: ShoppingLiveActivityDeliveryEvent;
  stateVersion: number;
  payload: ShoppingLiveActivityPayload;
};

export type ShoppingLiveActivityStore = {
  register: (request: ShoppingLiveActivityRegistrationRequest) => Promise<ShoppingLiveActivityRegistration>;
  findActiveRegistrations: (options: {
    tokenType: ShoppingLiveActivityTokenType;
    tripId?: string;
    excludeResident?: string;
  }) => Promise<StoredShoppingLiveActivityRegistration[]>;
  enqueueDelivery: (request: EnqueueShoppingLiveActivityDelivery) => Promise<ShoppingLiveActivityDelivery>;
  claimDueDeliveries: (limit: number) => Promise<StoredShoppingLiveActivityDelivery[]>;
  markDeliverySent: (deliveryId: string, apnsId?: string) => Promise<void>;
  markDeliveryRetryableFailure: (deliveryId: string, reason: string, nextAttemptAt: Date) => Promise<void>;
  markDeliveryAmbiguous: (deliveryId: string, reason: string, nextAttemptAt: Date) => Promise<void>;
  markDeliveryPermanentFailure: (deliveryId: string, reason: string) => Promise<void>;
  invalidateRegistration: (registrationId: string) => Promise<void>;
  reconcileAmbiguousStartDeliveries: (options: { tripId: string; pushDeviceId: string }) => Promise<void>;
  supersedePendingUpdates: (tripId: string, newerStateVersion: number) => Promise<void>;
  recoverStaleClaims: () => Promise<void>;
  getDiagnostics: () => Promise<ShoppingLiveActivityDiagnostics>;
};

export type ShoppingLiveActivityDiagnostics = {
  activePushToStartRegistrationCount: number;
  activeUpdateRegistrationCount: number;
  latestDelivery: Pick<ShoppingLiveActivityDelivery, 'id' | 'tripId' | 'eventType' | 'stateVersion' | 'status' | 'attemptCount' | 'apnsId' | 'lastErrorReason' | 'createdAt' | 'sentAt'> | null;
};

type RegistrationRow = Record<string, unknown> & {
  id: unknown;
  pushDeviceId: unknown;
  resident: unknown;
  environment: unknown;
  tokenType: unknown;
  tripId: unknown;
  token: unknown;
  isActive: unknown;
  createdAt: unknown;
  updatedAt: unknown;
};

type DeliveryRow = Record<string, unknown> & {
  id: unknown;
  tripId: unknown;
  registrationId: unknown;
  eventType: unknown;
  stateVersion: unknown;
  status: unknown;
  attemptCount: unknown;
  payload: unknown;
  apnsId: unknown;
  lastErrorReason: unknown;
  createdAt: unknown;
  sentAt: unknown;
  registrationPushDeviceId: unknown;
  registrationResident: unknown;
  registrationEnvironment: unknown;
  registrationTokenType: unknown;
  registrationTripId: unknown;
  registrationToken: unknown;
  registrationIsActive: unknown;
  registrationCreatedAt: unknown;
  registrationUpdatedAt: unknown;
};

export function createPostgresShoppingLiveActivityStore(options: {
  database?: DatabaseQuery;
  transactionRunner?: DatabaseTransactionRunner;
} = {}): ShoppingLiveActivityStore {
  if (Boolean(options.database) !== Boolean(options.transactionRunner)) {
    throw new Error('database and transactionRunner must be injected together.');
  }

  const query = () => options.database ?? getDatabaseClient();
  const transaction = () => options.transactionRunner ?? getDatabaseTransactionRunner();

  return {
    async register(request) {
      return transaction()(async (database) => {
        await database`
          UPDATE shopping_live_activity_registrations
          SET is_active = false, invalidated_at = now()
          WHERE push_device_id = ${request.pushDeviceId}
            AND token_type = ${request.tokenType}
            AND environment = ${request.environment}
            AND COALESCE(trip_id::text, '') = COALESCE(${request.tripId ?? null}::text, '')
            AND is_active
        `;
        const [row] = await database<RegistrationRow>`
          INSERT INTO shopping_live_activity_registrations (
            push_device_id,
            resident,
            environment,
            token_type,
            trip_id,
            token,
            token_hash
          )
          VALUES (
            ${request.pushDeviceId},
            ${request.resident},
            ${request.environment},
            ${request.tokenType},
            ${request.tripId ?? null},
            ${request.token},
            ${tokenHash(request.token)}
          )
          RETURNING
            id,
            push_device_id AS "pushDeviceId",
            resident,
            environment,
            token_type AS "tokenType",
            trip_id AS "tripId",
            token,
            is_active AS "isActive",
            created_at AS "createdAt",
            updated_at AS "updatedAt"
        `;

        return publicRegistrationFromRow(requireRow(row, 'shopping_live_activity_registrations.register'));
      });
    },
    async findActiveRegistrations(options) {
      const rows = options.tokenType === 'push_to_start'
        ? await query()<RegistrationRow>`
            SELECT
              id,
              push_device_id AS "pushDeviceId",
              resident,
              environment,
              token_type AS "tokenType",
              trip_id AS "tripId",
              token,
              is_active AS "isActive",
              created_at AS "createdAt",
              updated_at AS "updatedAt"
            FROM shopping_live_activity_registrations
            WHERE token_type = 'push_to_start'
              AND is_active
          `
        : await query()<RegistrationRow>`
            SELECT
              id,
              push_device_id AS "pushDeviceId",
              resident,
              environment,
              token_type AS "tokenType",
              trip_id AS "tripId",
              token,
              is_active AS "isActive",
              created_at AS "createdAt",
              updated_at AS "updatedAt"
            FROM shopping_live_activity_registrations
            WHERE token_type = 'activity_update'
              AND trip_id = ${options.tripId ?? null}
              AND is_active
          `;

      return rows
        .map(storedRegistrationFromRow)
        .filter((registration) => !options.excludeResident || registration.resident !== options.excludeResident);
    },
    async enqueueDelivery(request) {
      const [row] = await query()<DeliveryRow>`
        INSERT INTO shopping_live_activity_deliveries (
          trip_id,
          registration_id,
          event_type,
          state_version,
          payload
        )
        VALUES (
          ${request.tripId},
          ${request.registrationId},
          ${request.eventType},
          ${request.stateVersion},
          ${jsonb(request.payload)}::jsonb
        )
        ON CONFLICT (trip_id, registration_id, event_type, state_version)
        DO UPDATE SET updated_at = now()
        RETURNING
          id,
          trip_id AS "tripId",
          registration_id AS "registrationId",
          event_type AS "eventType",
          state_version AS "stateVersion",
          status,
          attempt_count AS "attemptCount",
          payload,
          apns_id AS "apnsId",
          last_error_reason AS "lastErrorReason",
          created_at AS "createdAt",
          sent_at AS "sentAt"
      `;

      return deliveryFromRow(requireRow(row, 'shopping_live_activity_deliveries.enqueue'));
    },
    async claimDueDeliveries(limit) {
      return transaction()(async (database) => {
        const rows = await database<DeliveryRow>`
          WITH claimed AS (
            SELECT id
            FROM shopping_live_activity_deliveries
            -- A timeout after a remote start is deliberately not retried here.
            -- APNs can have accepted the request after the connection was lost,
            -- and another start for the same token could create a duplicate Activity.
            WHERE (
              status = 'pending'
              OR (status = 'ambiguous' AND event_type <> 'start')
            )
              AND next_attempt_at <= now()
            ORDER BY created_at ASC
            LIMIT ${Math.max(1, Math.min(limit, 50))}
            FOR UPDATE SKIP LOCKED
          )
          UPDATE shopping_live_activity_deliveries delivery
          SET status = 'sending', attempt_count = attempt_count + 1, updated_at = now()
          FROM claimed
          WHERE delivery.id = claimed.id
          RETURNING
            delivery.id,
            delivery.trip_id AS "tripId",
            delivery.registration_id AS "registrationId",
            delivery.event_type AS "eventType",
            delivery.state_version AS "stateVersion",
            delivery.status,
            delivery.attempt_count AS "attemptCount",
            delivery.payload,
            delivery.apns_id AS "apnsId",
            delivery.last_error_reason AS "lastErrorReason",
            delivery.created_at AS "createdAt",
            delivery.sent_at AS "sentAt"
        `;

        const deliveries = await Promise.all(rows.map(async (delivery) => {
          const [registration] = await database<RegistrationRow>`
            SELECT
              id,
              push_device_id AS "pushDeviceId",
              resident,
              environment,
              token_type AS "tokenType",
              trip_id AS "tripId",
              token,
              is_active AS "isActive",
              created_at AS "createdAt",
              updated_at AS "updatedAt"
            FROM shopping_live_activity_registrations
            WHERE id = ${requiredString(delivery.registrationId, 'delivery.registrationId')}
            LIMIT 1
          `;

          return {
            ...deliveryFromRow(delivery),
            payload: payloadFromRow(delivery.payload),
            registration: storedRegistrationFromRow(requireRow(registration, 'delivery.registration')),
          };
        }));

        return deliveries;
      });
    },
    async markDeliverySent(deliveryId, apnsId) {
      await transaction()(async (database) => {
        await database`
          UPDATE shopping_live_activity_deliveries delivery
          SET
            status = 'sent',
            apns_id = ${apnsId ?? null},
            sent_at = now(),
            last_error_reason = NULL,
            updated_at = now()
          WHERE delivery.id = ${deliveryId}
        `;
        await database`
          UPDATE shopping_live_activity_registrations registration
          SET
            last_accepted_state_version = delivery.state_version,
            last_accepted_at = now(),
            updated_at = now()
          FROM shopping_live_activity_deliveries delivery
          WHERE delivery.id = ${deliveryId}
            AND registration.id = delivery.registration_id
            AND (
              registration.last_accepted_state_version IS NULL
              OR delivery.state_version >= registration.last_accepted_state_version
            )
        `;
      });
    },
    async markDeliveryRetryableFailure(deliveryId, reason, nextAttemptAt) {
      await markDeliveryRetry(query(), deliveryId, 'pending', reason, nextAttemptAt);
    },
    async markDeliveryAmbiguous(deliveryId, reason, nextAttemptAt) {
      await markDeliveryRetry(query(), deliveryId, 'ambiguous', reason, nextAttemptAt);
    },
    async markDeliveryPermanentFailure(deliveryId, reason) {
      await query()`
        UPDATE shopping_live_activity_deliveries
        SET status = 'failed', last_error_reason = ${reason}, updated_at = now()
        WHERE id = ${deliveryId}
      `;
    },
    async invalidateRegistration(registrationId) {
      await query()`
        UPDATE shopping_live_activity_registrations
        SET is_active = false, invalidated_at = now(), updated_at = now()
        WHERE id = ${registrationId} AND is_active
      `;
    },
    async reconcileAmbiguousStartDeliveries({ tripId, pushDeviceId }) {
      await query()`
        UPDATE shopping_live_activity_deliveries delivery
        SET
          status = 'sent',
          sent_at = now(),
          last_error_reason = NULL,
          updated_at = now()
        FROM shopping_live_activity_registrations registration
        WHERE delivery.registration_id = registration.id
          AND delivery.trip_id = ${tripId}
          AND delivery.event_type = 'start'
          AND delivery.status = 'ambiguous'
          AND registration.push_device_id = ${pushDeviceId}
      `;
    },
    async supersedePendingUpdates(tripId, newerStateVersion) {
      await query()`
        UPDATE shopping_live_activity_deliveries
        SET
          status = 'failed',
          last_error_reason = 'superseded by a newer committed shopping trip version',
          updated_at = now()
        WHERE trip_id = ${tripId}
          AND event_type = 'update'
          AND state_version < ${newerStateVersion}
          AND status IN ('pending', 'ambiguous')
      `;
    },
    async recoverStaleClaims() {
      await query()`
        UPDATE shopping_live_activity_deliveries
        SET
          status = 'ambiguous',
          last_error_reason = 'delivery worker restarted before APNs response was recorded',
          next_attempt_at = now() + interval '30 seconds',
          updated_at = now()
        WHERE status = 'sending'
          AND updated_at < now() - interval '60 seconds'
      `;
    },
    async getDiagnostics() {
      const [countRows, latestRows] = await Promise.all([
        query()<{ pushToStartCount: unknown; updateCount: unknown }>`
          SELECT
            COUNT(*) FILTER (WHERE token_type = 'push_to_start' AND is_active)::integer AS "pushToStartCount",
            COUNT(*) FILTER (WHERE token_type = 'activity_update' AND is_active)::integer AS "updateCount"
          FROM shopping_live_activity_registrations
        `,
        query()<DeliveryRow>`
          SELECT
            id,
            trip_id AS "tripId",
            registration_id AS "registrationId",
            event_type AS "eventType",
            state_version AS "stateVersion",
            status,
            attempt_count AS "attemptCount",
            payload,
            apns_id AS "apnsId",
            last_error_reason AS "lastErrorReason",
            created_at AS "createdAt",
            sent_at AS "sentAt"
          FROM shopping_live_activity_deliveries
          ORDER BY created_at DESC
          LIMIT 1
        `,
      ]);
      return {
        activePushToStartRegistrationCount: requiredInteger(countRows[0]?.pushToStartCount, 'shopping_live_activity_registrations.push_to_start_count'),
        activeUpdateRegistrationCount: requiredInteger(countRows[0]?.updateCount, 'shopping_live_activity_registrations.update_count'),
        latestDelivery: latestRows[0] ? deliveryFromRow(latestRows[0]) : null,
      };
    },
  };
}

async function markDeliveryRetry(
  database: DatabaseQuery,
  deliveryId: string,
  status: 'pending' | 'ambiguous',
  reason: string,
  nextAttemptAt: Date,
): Promise<void> {
  await database`
    UPDATE shopping_live_activity_deliveries
    SET
      status = ${status},
      last_error_reason = ${reason},
      next_attempt_at = ${nextAttemptAt.toISOString()},
      updated_at = now()
    WHERE id = ${deliveryId}
  `;
}

function publicRegistrationFromRow(row: RegistrationRow): ShoppingLiveActivityRegistration {
  const stored = storedRegistrationFromRow(row);
  const { token: _token, ...registration } = stored;
  return registration;
}

function storedRegistrationFromRow(row: RegistrationRow): StoredShoppingLiveActivityRegistration {
  return {
    id: requiredString(row.id, 'shopping_live_activity_registrations.id'),
    pushDeviceId: requiredString(row.pushDeviceId, 'shopping_live_activity_registrations.push_device_id'),
    resident: requiredResident(row.resident),
    environment: requiredEnvironment(row.environment),
    tokenType: requiredTokenType(row.tokenType),
    tripId: optionalString(row.tripId) ?? null,
    token: requiredString(row.token, 'shopping_live_activity_registrations.token'),
    isActive: optionalBoolean(row.isActive) ?? false,
    createdAt: requiredISOString(row.createdAt, 'shopping_live_activity_registrations.created_at'),
    updatedAt: requiredISOString(row.updatedAt, 'shopping_live_activity_registrations.updated_at'),
  };
}

function deliveryFromRow(row: DeliveryRow): ShoppingLiveActivityDelivery {
  return {
    id: requiredString(row.id, 'shopping_live_activity_deliveries.id'),
    tripId: requiredString(row.tripId, 'shopping_live_activity_deliveries.trip_id'),
    registrationId: requiredString(row.registrationId, 'shopping_live_activity_deliveries.registration_id'),
    eventType: requiredEventType(row.eventType),
    stateVersion: requiredInteger(row.stateVersion, 'shopping_live_activity_deliveries.state_version'),
    status: requiredDeliveryStatus(row.status),
    attemptCount: requiredInteger(row.attemptCount, 'shopping_live_activity_deliveries.attempt_count'),
    apnsId: optionalString(row.apnsId) ?? null,
    lastErrorReason: optionalString(row.lastErrorReason) ?? null,
    createdAt: requiredISOString(row.createdAt, 'shopping_live_activity_deliveries.created_at'),
    sentAt: optionalISOString(row.sentAt) ?? null,
  };
}

function payloadFromRow(value: unknown): ShoppingLiveActivityPayload {
  const parsed = parseJSONBValue(value);

  if (!parsed || typeof parsed !== 'object') {
    throw new Error('Expected shopping_live_activity_deliveries.payload to be JSON.');
  }

  return parsed as ShoppingLiveActivityPayload;
}

function requireRow<Row>(row: Row | undefined, fieldName: string): Row {
  if (!row) {
    throw new Error(`Expected ${fieldName} to return a row.`);
  }

  return row;
}

function requiredISOString(value: unknown, fieldName: string): string {
  const valueAsISO = optionalISOString(value);

  if (!valueAsISO) {
    throw new Error(`Expected ${fieldName} to be an ISO timestamp.`);
  }

  return valueAsISO;
}

function requiredResident(value: unknown): 'Josh' | 'Mallory' {
  if (value === 'Josh' || value === 'Mallory') {
    return value;
  }

  throw new Error('Expected shopping live activity resident to be Josh or Mallory.');
}

function requiredEnvironment(value: unknown): 'sandbox' | 'production' {
  if (value === 'sandbox' || value === 'production') {
    return value;
  }

  throw new Error('Expected shopping live activity environment to be sandbox or production.');
}

function requiredTokenType(value: unknown): ShoppingLiveActivityTokenType {
  if (value === 'push_to_start' || value === 'activity_update') {
    return value;
  }

  throw new Error('Expected shopping live activity token type to be valid.');
}

function requiredEventType(value: unknown): ShoppingLiveActivityDeliveryEvent {
  if (value === 'start' || value === 'update' || value === 'end') {
    return value;
  }

  throw new Error('Expected shopping live activity delivery event to be valid.');
}

function requiredDeliveryStatus(value: unknown): ShoppingLiveActivityDeliveryStatus {
  if (value === 'pending' || value === 'sending' || value === 'sent' || value === 'failed' || value === 'ambiguous') {
    return value;
  }

  throw new Error('Expected shopping live activity delivery status to be valid.');
}

function tokenHash(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}
