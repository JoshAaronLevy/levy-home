import type {
  CompleteShoppingTripPersistenceRequest,
  ClaimShoppingTripDisplayRequest,
  ShoppingItemEstimate,
  ShoppingItemStoreListing,
  ShoppingListItem,
  ShoppingTripItemSnapshot,
  ShoppingTripItemState,
  ShoppingTripDisplayDisposition,
  ShoppingTripDisplayDispositionKind,
  ShoppingTripResident,
  ShoppingTripSnapshot,
  ShoppingTripStatus,
  StartShoppingTripPersistenceRequest,
} from '../contracts.js';
import {
  getDatabaseClient,
  getDatabaseTransactionRunner,
  type DatabaseQuery,
  type DatabaseTransactionRunner,
} from '../db/client.js';
import {
  optionalISOString,
  optionalInteger,
  optionalString,
  requiredInteger,
  requiredString,
} from '../db/rowReaders.js';
import { fetchNeededShoppingListItems } from './shoppingListRepository.js';

export type ShoppingTripStore = {
  fetchActiveTrip: () => Promise<ShoppingTripSnapshot | null>;
  fetchTrip: (tripId: string) => Promise<ShoppingTripSnapshot | null>;
  fetchTripByStartMutationId: (mutationId: string) => Promise<ShoppingTripSnapshot | null>;
  fetchTripByEndMutationId: (mutationId: string) => Promise<ShoppingTripSnapshot | null>;
  fetchTripItems: (tripId: string) => Promise<ShoppingTripItemSnapshot[]>;
  startTrip: (request: StartShoppingTripPersistenceRequest) => Promise<ShoppingTripSnapshot>;
  startTripWithDisplay: (request: StartShoppingTripPersistenceRequest & {
    originatingPushDeviceId: string;
  }) => Promise<ShoppingTripStartWithDisplayResult>;
  claimDisplay: (request: ClaimShoppingTripDisplayRequest) => Promise<ShoppingTripDisplayDisposition | null>;
  completeTrip: (
    request: CompleteShoppingTripPersistenceRequest,
  ) => Promise<ShoppingTripSnapshot | null>;
};

export type ShoppingTripStartWithDisplayResult = {
  trip: ShoppingTripSnapshot;
  displayDisposition: ShoppingTripDisplayDisposition;
};

type ShoppingTripAggregateRow = Record<string, unknown> & {
  id: unknown;
  status: unknown;
  startedBy: unknown;
  startedAt: unknown;
  endedBy: unknown;
  endedAt: unknown;
  pickedUpCount: unknown;
  remainingCount: unknown;
  totalItemCount: unknown;
  estimatedTotalCents: unknown;
  pricedPickedItemCount: unknown;
  unpricedPickedItemCount: unknown;
  currencyCode: unknown;
  version: unknown;
  activityUpdatedAtEpochSeconds: unknown;
};

type ShoppingTripIDRow = Record<string, unknown> & {
  id: unknown;
};

type ShoppingTripItemRow = Record<string, unknown> & {
  id: unknown;
  tripId: unknown;
  shoppingItemId: unknown;
  name: unknown;
  quantity: unknown;
  estimatedUnitPriceCents: unknown;
  priceSource: unknown;
  storeId: unknown;
  state: unknown;
  pickedUpBy: unknown;
  pickedUpAt: unknown;
  createdAt: unknown;
  updatedAt: unknown;
};

type ShoppingTripDisplayDispositionRow = Record<string, unknown> & {
  tripId: unknown;
  pushDeviceId: unknown;
  resident: unknown;
  kind: unknown;
  remoteStartCount: unknown;
};

export class ShoppingTripHasNoNeededItemsError extends Error {
  constructor() {
    super('A shopping trip requires at least one needed item.');
    this.name = 'ShoppingTripHasNoNeededItemsError';
  }
}

export type ShoppingTripItemMutation =
  | { kind: 'created'; item: ShoppingListItem; actor?: string }
  | { kind: 'updated'; previousItem: ShoppingListItem; item: ShoppingListItem; actor?: string }
  | { kind: 'deleted'; item: ShoppingListItem; actor?: string };

export function createPostgresShoppingTripStore(options: {
  database?: DatabaseQuery;
  transactionRunner?: DatabaseTransactionRunner;
} = {}): ShoppingTripStore {
  if (Boolean(options.database) !== Boolean(options.transactionRunner)) {
    throw new Error('database and transactionRunner must be injected together.');
  }

  const query = () => options.database ?? getDatabaseClient();
  const transaction = () => options.transactionRunner ?? getDatabaseTransactionRunner();

  return {
    async fetchActiveTrip() {
      return fetchActiveShoppingTrip(query());
    },
    async fetchTrip(tripId) {
      return fetchShoppingTrip(query(), tripId);
    },
    async fetchTripByStartMutationId(mutationId) {
      return fetchShoppingTripByStartMutationId(query(), mutationId);
    },
    async fetchTripByEndMutationId(mutationId) {
      return fetchShoppingTripByEndMutationId(query(), mutationId);
    },
    async fetchTripItems(tripId) {
      return fetchShoppingTripItems(query(), tripId);
    },
    async startTrip(request) {
      return transaction()((database) => createShoppingTrip(database, request));
    },
    async startTripWithDisplay(request) {
      return transaction()(async (database) => {
        const trip = await createShoppingTrip(database, request);
        const displayDisposition = await reserveInitialTripDisplays(database, trip.id, request);
        return { trip, displayDisposition };
      });
    },
    async claimDisplay(request) {
      return transaction()(async (database) => {
        const trip = await fetchShoppingTrip(database, request.tripId);

        if (!trip || trip.status !== 'active') {
          return null;
        }

        const existing = await fetchTripDisplayDisposition(database, request.tripId, request.pushDeviceId);

        if (existing) {
          return existing;
        }

        await database`
          INSERT INTO shopping_trip_display_dispositions (
            trip_id,
            push_device_id,
            resident,
            kind
          )
          VALUES (${request.tripId}, ${request.pushDeviceId}, ${request.resident}, 'start_locally')
          ON CONFLICT (trip_id, push_device_id) DO NOTHING
        `;

        return requireDisplayDisposition(
          await fetchTripDisplayDisposition(database, request.tripId, request.pushDeviceId),
          'claim shopping trip display',
        );
      });
    },
    async completeTrip(request) {
      return transaction()((database) => completeShoppingTrip(database, request));
    },
  };
}

export async function createShoppingTrip(
  database: DatabaseQuery,
  request: StartShoppingTripPersistenceRequest,
): Promise<ShoppingTripSnapshot> {
  const [tripRow] = await database<ShoppingTripIDRow>`
    INSERT INTO shopping_trips (
      started_by,
      start_mutation_id,
      currency_code
    )
    VALUES (
      ${request.startedBy},
      ${request.mutationId},
      ${request.currencyCode ?? 'USD'}
    )
    RETURNING id
  `;

  const tripId = requiredString(tripRow?.id, 'shopping_trips.id');
  const neededItems = await fetchNeededShoppingListItems(database);

  if (neededItems.length === 0) {
    throw new ShoppingTripHasNoNeededItemsError();
  }

  for (const [position, item] of neededItems.entries()) {
    await insertShoppingTripItemSnapshot(database, tripId, position, item);
  }

  return requireShoppingTrip(
    await fetchShoppingTrip(database, tripId),
    'create',
  );
}

async function reserveInitialTripDisplays(
  database: DatabaseQuery,
  tripId: string,
  request: StartShoppingTripPersistenceRequest & { originatingPushDeviceId: string },
): Promise<ShoppingTripDisplayDisposition> {
  await database`
    INSERT INTO shopping_trip_display_dispositions (
      trip_id,
      push_device_id,
      resident,
      kind
    )
    VALUES (${tripId}, ${request.originatingPushDeviceId}, ${request.startedBy}, 'start_locally')
  `;

  // Capture the counterpart's current static start-token registration inside
  // the trip transaction. This makes the local/remote ownership decision
  // durable before any APNs work begins after commit.
  await database`
    INSERT INTO shopping_trip_display_dispositions (
      trip_id,
      push_device_id,
      resident,
      kind,
      activity_registration_id
    )
    SELECT
      ${tripId},
      registration.push_device_id,
      registration.resident,
      'remote_start_pending',
      registration.id
    FROM shopping_live_activity_registrations registration
    WHERE registration.token_type = 'push_to_start'
      AND registration.is_active
      AND registration.push_device_id <> ${request.originatingPushDeviceId}
      AND registration.resident <> ${request.startedBy}
    ON CONFLICT (trip_id, push_device_id) DO NOTHING
  `;

  return requireDisplayDisposition(
    await fetchTripDisplayDisposition(database, tripId, request.originatingPushDeviceId),
    'reserve shopping trip display',
  );
}

async function fetchTripDisplayDisposition(
  database: DatabaseQuery,
  tripId: string,
  pushDeviceId: string,
): Promise<ShoppingTripDisplayDisposition | null> {
  const [row] = await database<ShoppingTripDisplayDispositionRow>`
    SELECT
      disposition.trip_id AS "tripId",
      disposition.push_device_id AS "pushDeviceId",
      disposition.resident,
      disposition.kind,
      (
        SELECT COUNT(*)::integer
        FROM shopping_trip_display_dispositions counterpart
        WHERE counterpart.trip_id = disposition.trip_id
          AND counterpart.kind = 'remote_start_pending'
      ) AS "remoteStartCount"
    FROM shopping_trip_display_dispositions disposition
    WHERE disposition.trip_id = ${tripId}
      AND disposition.push_device_id = ${pushDeviceId}
    LIMIT 1
  `;

  return row ? shoppingTripDisplayDispositionFromRow(row) : null;
}

function requireDisplayDisposition(
  disposition: ShoppingTripDisplayDisposition | null,
  operation: string,
): ShoppingTripDisplayDisposition {
  if (!disposition) {
    throw new Error(`Expected a display disposition after ${operation}.`);
  }

  return disposition;
}

export async function completeShoppingTrip(
  database: DatabaseQuery,
  request: CompleteShoppingTripPersistenceRequest,
): Promise<ShoppingTripSnapshot | null> {
  const [tripRow] = await database<ShoppingTripIDRow>`
    UPDATE shopping_trips
    SET
      status = 'completed',
      ended_by = ${request.endedBy},
      ended_at = now(),
      end_mutation_id = ${request.mutationId},
      summary_recipient = ${request.summaryRecipient ?? null},
      version = version + 1
    WHERE id = ${request.tripId}
      AND status = 'active'
    RETURNING id
  `;

  if (!tripRow) {
    return null;
  }

  return fetchShoppingTrip(database, requiredString(tripRow.id, 'shopping_trips.id'));
}

export async function lockActiveShoppingTrip(
  database: DatabaseQuery,
): Promise<ShoppingTripSnapshot | null> {
  const [row] = await database<ShoppingTripIDRow>`
    SELECT id
    FROM shopping_trips
    WHERE status = 'active'
    ORDER BY started_at DESC
    LIMIT 1
    FOR UPDATE
  `;

  return row ? fetchShoppingTrip(database, requiredString(row.id, 'shopping_trips.id')) : null;
}

export async function applyShoppingTripItemMutation(
  database: DatabaseQuery,
  activeTrip: ShoppingTripSnapshot,
  mutation: ShoppingTripItemMutation,
): Promise<ShoppingTripSnapshot> {
  let publicStateChanged = false;

  if (mutation.kind === 'created') {
    if (!mutation.item.purchased) {
      await insertShoppingTripItemAtNextPosition(database, activeTrip.id, mutation.item);
      publicStateChanged = true;
    }
  } else {
    const snapshot = await fetchShoppingTripItemForShoppingItem(database, activeTrip.id, mutation.item.id);

    if (mutation.kind === 'deleted') {
      if (snapshot?.state === 'remaining') {
        await database`
          UPDATE shopping_trip_items
          SET state = 'removed', picked_up_by = NULL, picked_up_at = NULL
          WHERE id = ${snapshot.id}
        `;
        publicStateChanged = true;
      }
    } else if (!snapshot && !mutation.item.purchased) {
      await insertShoppingTripItemAtNextPosition(database, activeTrip.id, mutation.item);
      publicStateChanged = true;
    } else if (snapshot) {
      const purchasedChanged = mutation.previousItem.purchased !== mutation.item.purchased;
      const nextState: ShoppingTripItemState = mutation.item.purchased ? 'picked_up' : 'remaining';
      const estimate = estimateShoppingItem(mutation.item);
      const estimateChanged = snapshot.estimatedUnitPriceCents !== estimate.estimatedUnitPriceCents
        || snapshot.quantity !== mutation.item.quantity;

      if (purchasedChanged || (snapshot.state === 'removed' && nextState === 'remaining')) {
        await database`
          UPDATE shopping_trip_items
          SET
            state = ${nextState},
            picked_up_by = ${nextState === 'picked_up' ? mutation.actor ?? null : null},
            picked_up_at = ${nextState === 'picked_up' ? new Date().toISOString() : null}
          WHERE id = ${snapshot.id}
        `;
        publicStateChanged = true;
      }

      await database`
        UPDATE shopping_trip_items
        SET
          name_snapshot = ${mutation.item.name.trim()},
          quantity_snapshot = ${mutation.item.quantity},
          estimated_unit_price_cents = ${estimate.estimatedUnitPriceCents},
          price_source = ${estimate.priceSource},
          store_id = ${estimate.storeId}
        WHERE id = ${snapshot.id}
      `;

      if (!purchasedChanged && snapshot.state === 'picked_up' && estimateChanged) {
        publicStateChanged = true;
      }
    }
  }

  if (publicStateChanged) {
    const nextTimestamp = Math.max(
      activeTrip.activityUpdatedAtEpochSeconds + 1,
      Math.floor(Date.now() / 1_000),
    );
    await database`
      UPDATE shopping_trips
      SET
        version = version + 1,
        activity_updated_at_epoch_seconds = ${nextTimestamp}
      WHERE id = ${activeTrip.id}
    `;
  }

  return requireShoppingTrip(
    await fetchShoppingTrip(database, activeTrip.id),
    'apply shopping item mutation',
  );
}

export async function fetchActiveShoppingTrip(
  database: DatabaseQuery,
): Promise<ShoppingTripSnapshot | null> {
  const [row] = await database<ShoppingTripAggregateRow>`
    SELECT
      trip.id,
      trip.status,
      trip.started_by AS "startedBy",
      trip.started_at AS "startedAt",
      trip.ended_by AS "endedBy",
      trip.ended_at AS "endedAt",
      COUNT(item.id) FILTER (WHERE item.state = 'picked_up')::integer AS "pickedUpCount",
      COUNT(item.id) FILTER (WHERE item.state = 'remaining')::integer AS "remainingCount",
      COUNT(item.id) FILTER (WHERE item.state IN ('remaining', 'picked_up'))::integer AS "totalItemCount",
      COALESCE(
        SUM(item.estimated_unit_price_cents * item.quantity_snapshot)
          FILTER (WHERE item.state = 'picked_up' AND item.estimated_unit_price_cents IS NOT NULL),
        0
      )::bigint AS "estimatedTotalCents",
      COUNT(item.id) FILTER (
        WHERE item.state = 'picked_up' AND item.estimated_unit_price_cents IS NOT NULL
      )::integer AS "pricedPickedItemCount",
      COUNT(item.id) FILTER (
        WHERE item.state = 'picked_up' AND item.estimated_unit_price_cents IS NULL
      )::integer AS "unpricedPickedItemCount",
      trip.currency_code AS "currencyCode",
      trip.version,
      trip.activity_updated_at_epoch_seconds AS "activityUpdatedAtEpochSeconds"
    FROM shopping_trips trip
    LEFT JOIN shopping_trip_items item ON item.trip_id = trip.id
    WHERE trip.status = 'active'
    GROUP BY trip.id
    ORDER BY trip.started_at DESC
    LIMIT 1
  `;

  return row ? shoppingTripFromRow(row) : null;
}

export async function fetchShoppingTrip(
  database: DatabaseQuery,
  tripId: string,
): Promise<ShoppingTripSnapshot | null> {
  const [row] = await database<ShoppingTripAggregateRow>`
    SELECT
      trip.id,
      trip.status,
      trip.started_by AS "startedBy",
      trip.started_at AS "startedAt",
      trip.ended_by AS "endedBy",
      trip.ended_at AS "endedAt",
      COUNT(item.id) FILTER (WHERE item.state = 'picked_up')::integer AS "pickedUpCount",
      COUNT(item.id) FILTER (WHERE item.state = 'remaining')::integer AS "remainingCount",
      COUNT(item.id) FILTER (WHERE item.state IN ('remaining', 'picked_up'))::integer AS "totalItemCount",
      COALESCE(
        SUM(item.estimated_unit_price_cents * item.quantity_snapshot)
          FILTER (WHERE item.state = 'picked_up' AND item.estimated_unit_price_cents IS NOT NULL),
        0
      )::bigint AS "estimatedTotalCents",
      COUNT(item.id) FILTER (
        WHERE item.state = 'picked_up' AND item.estimated_unit_price_cents IS NOT NULL
      )::integer AS "pricedPickedItemCount",
      COUNT(item.id) FILTER (
        WHERE item.state = 'picked_up' AND item.estimated_unit_price_cents IS NULL
      )::integer AS "unpricedPickedItemCount",
      trip.currency_code AS "currencyCode",
      trip.version,
      trip.activity_updated_at_epoch_seconds AS "activityUpdatedAtEpochSeconds"
    FROM shopping_trips trip
    LEFT JOIN shopping_trip_items item ON item.trip_id = trip.id
    WHERE trip.id = ${tripId}
    GROUP BY trip.id
    LIMIT 1
  `;

  return row ? shoppingTripFromRow(row) : null;
}

export async function fetchShoppingTripByStartMutationId(
  database: DatabaseQuery,
  mutationId: string,
): Promise<ShoppingTripSnapshot | null> {
  return fetchShoppingTripByColumn(database, 'start_mutation_id', mutationId);
}

export async function fetchShoppingTripByEndMutationId(
  database: DatabaseQuery,
  mutationId: string,
): Promise<ShoppingTripSnapshot | null> {
  return fetchShoppingTripByColumn(database, 'end_mutation_id', mutationId);
}

async function fetchShoppingTripByColumn(
  database: DatabaseQuery,
  column: 'start_mutation_id' | 'end_mutation_id',
  mutationId: string,
): Promise<ShoppingTripSnapshot | null> {
  const rows = column === 'start_mutation_id'
    ? await database<ShoppingTripIDRow>`
        SELECT id
        FROM shopping_trips
        WHERE start_mutation_id = ${mutationId}
        LIMIT 1
      `
    : await database<ShoppingTripIDRow>`
        SELECT id
        FROM shopping_trips
        WHERE end_mutation_id = ${mutationId}
        LIMIT 1
      `;
  const tripId = rows[0]?.id;

  return tripId ? fetchShoppingTrip(database, requiredString(tripId, `shopping_trips.${column}`)) : null;
}

export async function fetchShoppingTripItems(
  database: DatabaseQuery,
  tripId: string,
): Promise<ShoppingTripItemSnapshot[]> {
  const rows = await database<ShoppingTripItemRow>`
    SELECT
      id,
      trip_id AS "tripId",
      shopping_item_id AS "shoppingItemId",
      name_snapshot AS "name",
      quantity_snapshot AS "quantity",
      estimated_unit_price_cents AS "estimatedUnitPriceCents",
      price_source AS "priceSource",
      store_id AS "storeId",
      state,
      picked_up_by AS "pickedUpBy",
      picked_up_at AS "pickedUpAt",
      created_at AS "createdAt",
      updated_at AS "updatedAt"
    FROM shopping_trip_items
    WHERE trip_id = ${tripId}
    ORDER BY snapshot_position ASC
  `;

  return rows.map(shoppingTripItemFromRow);
}

export function estimateShoppingItem(item: Pick<ShoppingListItem, 'storeListings'>): ShoppingItemEstimate {
  let selected:
    | {
        listing: ShoppingItemStoreListing;
        price: number;
        cents: number;
      }
    | undefined;

  for (const listing of item.storeListings) {
    const promo = validListingPrice(listing.price?.promo);
    const regular = validListingPrice(listing.price?.regular);
    const price = promo ?? regular;

    if (price === undefined) {
      continue;
    }

    const cents = priceToCents(price);

    if (cents === null || (selected && price <= selected.price)) {
      continue;
    }

    selected = { listing, price, cents };
  }

  if (!selected) {
    return {
      estimatedUnitPriceCents: null,
      priceSource: null,
      storeId: null,
    };
  }

  return {
    estimatedUnitPriceCents: selected.cents,
    priceSource: listingPriceSource(selected.listing),
    storeId: positiveInteger(selected.listing.storeId) ?? null,
  };
}

export function priceToCents(price: number): number | null {
  if (!Number.isFinite(price) || price < 0) {
    return null;
  }

  const cents = Math.round((price + Number.EPSILON) * 100);
  return Number.isSafeInteger(cents) ? cents : null;
}

async function insertShoppingTripItemSnapshot(
  database: DatabaseQuery,
  tripId: string,
  snapshotPosition: number,
  item: ShoppingListItem,
): Promise<void> {
  const name = item.name.trim();

  if (!name) {
    throw new Error(`Shopping item ${item.id} has a blank name.`);
  }

  if (!Number.isInteger(item.quantity) || item.quantity < 1) {
    throw new Error(`Shopping item ${item.id} has an invalid quantity.`);
  }

  const estimate = estimateShoppingItem(item);

  await database`
    INSERT INTO shopping_trip_items (
      trip_id,
      shopping_item_id,
      snapshot_position,
      name_snapshot,
      quantity_snapshot,
      estimated_unit_price_cents,
      price_source,
      store_id,
      state
    )
    VALUES (
      ${tripId},
      ${item.id},
      ${snapshotPosition},
      ${name},
      ${item.quantity},
      ${estimate.estimatedUnitPriceCents},
      ${estimate.priceSource},
      ${estimate.storeId},
      'remaining'
    )
  `;
}

async function insertShoppingTripItemAtNextPosition(
  database: DatabaseQuery,
  tripId: string,
  item: ShoppingListItem,
): Promise<void> {
  const [row] = await database<{ nextPosition: unknown }>`
    SELECT COALESCE(MAX(snapshot_position), -1) + 1 AS "nextPosition"
    FROM shopping_trip_items
    WHERE trip_id = ${tripId}
  `;
  await insertShoppingTripItemSnapshot(
    database,
    tripId,
    requiredInteger(row?.nextPosition, 'shopping_trip_items.next_position'),
    item,
  );
}

async function fetchShoppingTripItemForShoppingItem(
  database: DatabaseQuery,
  tripId: string,
  shoppingItemId: number,
): Promise<ShoppingTripItemSnapshot | null> {
  const rows = await database<ShoppingTripItemRow>`
    SELECT
      id,
      trip_id AS "tripId",
      shopping_item_id AS "shoppingItemId",
      name_snapshot AS "name",
      quantity_snapshot AS "quantity",
      estimated_unit_price_cents AS "estimatedUnitPriceCents",
      price_source AS "priceSource",
      store_id AS "storeId",
      state,
      picked_up_by AS "pickedUpBy",
      picked_up_at AS "pickedUpAt",
      created_at AS "createdAt",
      updated_at AS "updatedAt"
    FROM shopping_trip_items
    WHERE trip_id = ${tripId}
      AND shopping_item_id = ${shoppingItemId}
    LIMIT 1
    FOR UPDATE
  `;

  return rows[0] ? shoppingTripItemFromRow(rows[0]) : null;
}

function shoppingTripFromRow(row: ShoppingTripAggregateRow): ShoppingTripSnapshot {
  return {
    id: requiredString(row.id, 'shopping_trips.id'),
    status: requiredTripStatus(row.status),
    startedBy: requiredResident(row.startedBy, 'shopping_trips.started_by'),
    startedAt: requiredISOString(row.startedAt, 'shopping_trips.started_at'),
    endedBy: optionalResident(row.endedBy, 'shopping_trips.ended_by'),
    endedAt: nullableISOString(row.endedAt, 'shopping_trips.ended_at'),
    pickedUpCount: requiredInteger(row.pickedUpCount, 'shopping_trip_items.picked_up_count'),
    remainingCount: requiredInteger(row.remainingCount, 'shopping_trip_items.remaining_count'),
    totalItemCount: requiredInteger(row.totalItemCount, 'shopping_trip_items.total_item_count'),
    estimatedTotalCents: requiredSafeInteger(
      row.estimatedTotalCents,
      'shopping_trip_items.estimated_total_cents',
    ),
    pricedPickedItemCount: requiredInteger(
      row.pricedPickedItemCount,
      'shopping_trip_items.priced_picked_item_count',
    ),
    unpricedPickedItemCount: requiredInteger(
      row.unpricedPickedItemCount,
      'shopping_trip_items.unpriced_picked_item_count',
    ),
    currencyCode: requiredString(row.currencyCode, 'shopping_trips.currency_code'),
    version: requiredInteger(row.version, 'shopping_trips.version'),
    activityUpdatedAtEpochSeconds: requiredSafeInteger(
      row.activityUpdatedAtEpochSeconds,
      'shopping_trips.activity_updated_at_epoch_seconds',
    ),
  };
}

function shoppingTripDisplayDispositionFromRow(
  row: ShoppingTripDisplayDispositionRow,
): ShoppingTripDisplayDisposition {
  return {
    tripId: requiredString(row.tripId, 'shopping_trip_display_dispositions.trip_id'),
    pushDeviceId: requiredString(row.pushDeviceId, 'shopping_trip_display_dispositions.push_device_id'),
    resident: requiredResident(row.resident, 'shopping_trip_display_dispositions.resident'),
    kind: requiredDisplayDispositionKind(row.kind),
    remoteStartCount: requiredInteger(row.remoteStartCount, 'shopping_trip_display_dispositions.remote_start_count'),
  };
}

function shoppingTripItemFromRow(row: ShoppingTripItemRow): ShoppingTripItemSnapshot {
  return {
    id: requiredString(row.id, 'shopping_trip_items.id'),
    tripId: requiredString(row.tripId, 'shopping_trip_items.trip_id'),
    shoppingItemId: optionalInteger(row.shoppingItemId) ?? null,
    name: requiredString(row.name, 'shopping_trip_items.name_snapshot'),
    quantity: requiredInteger(row.quantity, 'shopping_trip_items.quantity_snapshot'),
    estimatedUnitPriceCents:
      row.estimatedUnitPriceCents === null
        ? null
        : requiredSafeInteger(
            row.estimatedUnitPriceCents,
            'shopping_trip_items.estimated_unit_price_cents',
          ),
    priceSource: optionalString(row.priceSource) ?? null,
    storeId: optionalInteger(row.storeId) ?? null,
    state: requiredTripItemState(row.state),
    pickedUpBy: optionalResident(row.pickedUpBy, 'shopping_trip_items.picked_up_by'),
    pickedUpAt: nullableISOString(row.pickedUpAt, 'shopping_trip_items.picked_up_at'),
    createdAt: requiredISOString(row.createdAt, 'shopping_trip_items.created_at'),
    updatedAt: requiredISOString(row.updatedAt, 'shopping_trip_items.updated_at'),
  };
}

function validListingPrice(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : undefined;
}

function listingPriceSource(listing: ShoppingItemStoreListing): string {
  return (
    optionalString(listing.source)?.trim()
    || optionalString(listing.storeName)?.trim()
    || 'store_listing'
  );
}

function positiveInteger(value: unknown): number | undefined {
  const integer = optionalInteger(value);
  return integer !== undefined && integer > 0 ? integer : undefined;
}

function requiredSafeInteger(value: unknown, fieldName: string): number {
  const number = typeof value === 'string' && value.trim() ? Number(value) : value;

  if (typeof number !== 'number' || !Number.isSafeInteger(number)) {
    throw new Error(`Expected ${fieldName} to be a safe integer.`);
  }

  return number;
}

function requiredISOString(value: unknown, fieldName: string): string {
  const date = optionalISOString(value);

  if (!date) {
    throw new Error(`Expected ${fieldName} to be an ISO timestamp.`);
  }

  return date;
}

function nullableISOString(value: unknown, fieldName: string): string | null {
  if (value === null || value === undefined) {
    return null;
  }

  return requiredISOString(value, fieldName);
}

function requiredResident(value: unknown, fieldName: string): ShoppingTripResident {
  if (value === 'Josh' || value === 'Mallory') {
    return value;
  }

  throw new Error(`Expected ${fieldName} to be Josh or Mallory.`);
}

function requiredDisplayDispositionKind(value: unknown): ShoppingTripDisplayDispositionKind {
  if (value === 'start_locally' || value === 'remote_start_pending') {
    return value;
  }

  throw new Error('Expected shopping trip display disposition kind to be valid.');
}

function optionalResident(value: unknown, fieldName: string): ShoppingTripResident | null {
  if (value === null || value === undefined) {
    return null;
  }

  return requiredResident(value, fieldName);
}

function requiredTripStatus(value: unknown): ShoppingTripStatus {
  if (value === 'active' || value === 'completed') {
    return value;
  }

  throw new Error('Expected shopping_trips.status to be active or completed.');
}

function requiredTripItemState(value: unknown): ShoppingTripItemState {
  if (value === 'remaining' || value === 'picked_up' || value === 'removed') {
    return value;
  }

  throw new Error('Expected shopping_trip_items.state to be remaining, picked_up, or removed.');
}

function requireShoppingTrip(
  trip: ShoppingTripSnapshot | null,
  operation: string,
): ShoppingTripSnapshot {
  if (!trip) {
    throw new Error(`Expected shopping trip ${operation} to return a row.`);
  }

  return trip;
}
