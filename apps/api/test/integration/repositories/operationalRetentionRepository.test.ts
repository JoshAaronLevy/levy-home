import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';

import { createPostgresOperationalRetentionStore } from '../../../src/repositories/operationalRetentionRepository.js';
import { createDisposableShoppingDatabase } from '../../support/pgliteDatabase.js';

test('operational retention deletes only expired terminal rows in bounded indexed batches', async (t) => {
  const disposable = await createDisposableShoppingDatabase();
  t.after(() => disposable.close());
  await disposable.exec(await readFile(
    new URL('../../../migrations/2026-08-16-001-operational-retention.sql', import.meta.url),
    'utf8',
  ));

  const activeDeviceId = 'active-device';
  const inactiveDeviceId = 'inactive-device';
  const activeLookupKey = 'apns:production:active';
  const inactiveLookupKey = 'apns:production:inactive';
  await disposable.database`
    INSERT INTO push_devices (id, lookup_key, token_hash, token, platform, provider, environment)
    VALUES
      (${activeDeviceId}, ${activeLookupKey}, 'active-hash', 'active-token', 'ios', 'apns', 'production'),
      (${inactiveDeviceId}, ${inactiveLookupKey}, 'inactive-hash', 'inactive-token', 'ios', 'apns', 'production')
  `;
  await disposable.database`
    UPDATE push_devices
    SET is_active = false, invalidated_at = now() - INTERVAL '181 days'
    WHERE id = ${inactiveDeviceId}
  `;
  await disposable.database`
    INSERT INTO notification_preferences (device_key)
    VALUES
      (${`device-token:${activeLookupKey}`}),
      (${`device-token:${inactiveLookupKey}`}),
      (${`device-id:${inactiveDeviceId}`})
  `;

  const tripId = randomUUID();
  const retainedTripId = randomUUID();
  await disposable.database`
    INSERT INTO shopping_trips (id, status, started_by, start_mutation_id, ended_by, ended_at, end_mutation_id)
    VALUES
      (${tripId}, 'active', 'Josh', ${randomUUID()}, NULL, NULL, NULL),
      (${retainedTripId}, 'completed', 'Mallory', ${randomUUID()}, 'Mallory', now(), ${randomUUID()})
  `;
  const registrationId = randomUUID();
  await disposable.database`
    INSERT INTO shopping_live_activity_registrations (
      id, push_device_id, resident, environment, token_type, token, token_hash
    )
    VALUES (${registrationId}, ${activeDeviceId}, 'Josh', 'production', 'push_to_start', 'activity-token', 'activity-hash')
  `;
  await disposable.database`
    INSERT INTO shopping_live_activity_deliveries (
      trip_id, registration_id, event_type, state_version, payload, status, updated_at
    )
    VALUES
      (${tripId}, ${registrationId}, 'start', 1, '{}'::jsonb, 'sent', now() - INTERVAL '91 days'),
      (${retainedTripId}, ${registrationId}, 'start', 1, '{}'::jsonb, 'pending', now() - INTERVAL '91 days')
  `;
  await disposable.database`
    INSERT INTO shopping_trip_summary_deliveries (
      trip_id, recipient, push_device_id, title, body, status, updated_at
    )
    VALUES
      (${tripId}, 'Josh', ${activeDeviceId}, 'Done', 'Trip completed.', 'skipped', now() - INTERVAL '91 days'),
      (${retainedTripId}, 'Mallory', ${activeDeviceId}, 'Done', 'Trip completed.', 'ambiguous', now() - INTERVAL '91 days')
  `;

  const expiredToDoId = await insertToDo(disposable, 'Expired reminder');
  const retainedToDoId = await insertToDo(disposable, 'Pending reminder');
  await disposable.database`
    INSERT INTO todo_due_reminder_deliveries (
      todo_item_id, due_date, reminder_kind, recipient_user_id, status, updated_at
    )
    VALUES
      (${expiredToDoId}, '2026-01-01', 'morning', 1, 'sent', now() - INTERVAL '91 days'),
      (${retainedToDoId}, '2026-01-01', 'morning', 1, 'ambiguous', now() - INTERVAL '91 days')
  `;

  const shoppingItemId = await insertShoppingItem(disposable);
  const expiredStockRunId = randomUUID();
  const retainedStockRunId = randomUUID();
  await disposable.database`
    INSERT INTO shopping_stock_price_check_runs (
      id, request_id, status, phase, started_at, finished_at
    )
    VALUES
      (${expiredStockRunId}, ${randomUUID()}, 'completed', 'finished', now() - INTERVAL '31 days', now() - INTERVAL '31 days'),
      (${retainedStockRunId}, ${randomUUID()}, 'running', 'checking_stores', now() - INTERVAL '31 days', NULL)
  `;
  await disposable.database`
    INSERT INTO shopping_stock_price_check_items (run_id, shopping_item_id, item_version, snapshot_position, item_snapshot)
    VALUES (${expiredStockRunId}, ${shoppingItemId}, 1, 0, '{"itemId":1}'::jsonb)
  `;

  const retentionStore = createPostgresOperationalRetentionStore(disposable.database);
  const deliveryCutoff = new Date();
  const stockCutoff = new Date();
  const inactiveDeviceCutoff = new Date();

  assert.equal(await retentionStore.cleanupTerminalLiveActivityDeliveries(deliveryCutoff), 1);
  assert.equal(await retentionStore.cleanupTerminalTripSummaryDeliveries(deliveryCutoff), 1);
  assert.equal(await retentionStore.cleanupTerminalToDoReminderDeliveries(deliveryCutoff), 1);
  assert.equal(await retentionStore.cleanupTerminalStockPriceCheckRuns(stockCutoff), 1);
  assert.equal(await retentionStore.cleanupInactivePushDevices(inactiveDeviceCutoff), 1);

  assert.equal(await rowCount(disposable, 'shopping_live_activity_deliveries'), 1);
  assert.equal(await rowCount(disposable, 'shopping_trip_summary_deliveries'), 1);
  assert.equal(await rowCount(disposable, 'todo_due_reminder_deliveries'), 1);
  assert.equal(await rowCount(disposable, 'shopping_stock_price_check_runs'), 1);
  assert.equal(await rowCount(disposable, 'shopping_stock_price_check_items'), 0, 'run-item JSONB outcomes cascade with their terminal run');
  assert.equal(await rowCount(disposable, 'push_devices'), 1);
  assert.equal(await rowCount(disposable, 'notification_preferences'), 1, 'inactive-device preference records are removed with their device');
});

async function insertToDo(
  disposable: Awaited<ReturnType<typeof createDisposableShoppingDatabase>>,
  name: string,
): Promise<number> {
  const [row] = await disposable.database<{ id: number }>`
    INSERT INTO todo_list (name)
    VALUES (${name})
    RETURNING id
  `;
  assert.ok(row);
  return row.id;
}

async function insertShoppingItem(
  disposable: Awaited<ReturnType<typeof createDisposableShoppingDatabase>>,
): Promise<number> {
  const [row] = await disposable.database<{ id: number }>`
    INSERT INTO shopping_list (name)
    VALUES ('Retained item')
    RETURNING id
  `;
  assert.ok(row);
  return row.id;
}

async function rowCount(
  disposable: Awaited<ReturnType<typeof createDisposableShoppingDatabase>>,
  table: 'shopping_live_activity_deliveries' | 'shopping_trip_summary_deliveries' | 'todo_due_reminder_deliveries' | 'shopping_stock_price_check_runs' | 'shopping_stock_price_check_items' | 'push_devices' | 'notification_preferences',
): Promise<number> {
  let rows: Array<{ count: number }>;

  switch (table) {
    case 'shopping_live_activity_deliveries':
      rows = await disposable.database<{ count: number }>`SELECT COUNT(*)::int AS count FROM shopping_live_activity_deliveries`;
      break;
    case 'shopping_trip_summary_deliveries':
      rows = await disposable.database<{ count: number }>`SELECT COUNT(*)::int AS count FROM shopping_trip_summary_deliveries`;
      break;
    case 'todo_due_reminder_deliveries':
      rows = await disposable.database<{ count: number }>`SELECT COUNT(*)::int AS count FROM todo_due_reminder_deliveries`;
      break;
    case 'shopping_stock_price_check_runs':
      rows = await disposable.database<{ count: number }>`SELECT COUNT(*)::int AS count FROM shopping_stock_price_check_runs`;
      break;
    case 'shopping_stock_price_check_items':
      rows = await disposable.database<{ count: number }>`SELECT COUNT(*)::int AS count FROM shopping_stock_price_check_items`;
      break;
    case 'push_devices':
      rows = await disposable.database<{ count: number }>`SELECT COUNT(*)::int AS count FROM push_devices`;
      break;
    case 'notification_preferences':
      rows = await disposable.database<{ count: number }>`SELECT COUNT(*)::int AS count FROM notification_preferences`;
      break;
  }

  const [row] = rows;
  return row?.count ?? 0;
}
