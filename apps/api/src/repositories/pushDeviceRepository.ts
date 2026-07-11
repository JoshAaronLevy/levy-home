import type { RegisteredDevice } from '../contracts.js';
import { getDatabaseClient, type DatabaseQuery } from '../db/client.js';
import { optionalISOString, optionalString, requiredString } from '../db/rowReaders.js';

export type StoredPushDevice = RegisteredDevice & {
  lookupKey: string;
  tokenHash: string;
};

export type PushDeviceRepository = {
  countDevices: () => Promise<number>;
  findDeviceById: (deviceId: string) => Promise<RegisteredDevice | undefined>;
  findDeviceByLookupKey: (lookupKey: string) => Promise<RegisteredDevice | undefined>;
  listDevices: () => Promise<RegisteredDevice[]>;
  saveDevice: (device: StoredPushDevice) => Promise<RegisteredDevice>;
  invalidateDevice: (deviceId: string) => Promise<void>;
};

type PushDeviceRow = Record<string, unknown> & {
  id: unknown;
  token: unknown;
  platform: unknown;
  provider: unknown;
  environment: unknown;
  appVersion: unknown;
  deviceName: unknown;
  registeredAt: unknown;
  lastSeenAt: unknown;
};

type DeviceCountRow = Record<string, unknown> & {
  count: unknown;
};

export function createInMemoryPushDeviceRepository(): PushDeviceRepository {
  const devicesById = new Map<string, RegisteredDevice>();
  const deviceIdsByLookupKey = new Map<string, string>();

  return {
    async countDevices() {
      return devicesById.size;
    },
    async findDeviceById(deviceId) {
      return devicesById.get(deviceId);
    },
    async findDeviceByLookupKey(lookupKey) {
      const deviceId = deviceIdsByLookupKey.get(lookupKey);

      return deviceId ? devicesById.get(deviceId) : undefined;
    },
    async listDevices() {
      return Array.from(devicesById.values());
    },
    async saveDevice(device) {
      const { lookupKey, tokenHash: _tokenHash, ...registeredDevice } = device;

      devicesById.set(registeredDevice.id, registeredDevice);
      deviceIdsByLookupKey.set(lookupKey, registeredDevice.id);

      return registeredDevice;
    },
    async invalidateDevice(deviceId) {
      devicesById.delete(deviceId);
      for (const [lookupKey, storedId] of deviceIdsByLookupKey) {
        if (storedId === deviceId) deviceIdsByLookupKey.delete(lookupKey);
      }
    },
  };
}

export function createPostgresPushDeviceRepository(database?: DatabaseQuery): PushDeviceRepository {
  const query = () => database ?? getDatabaseClient();

  return {
    async countDevices() {
      const [row] = await query()<DeviceCountRow>`
        SELECT COUNT(*)::int AS count
        FROM push_devices
        WHERE is_active
      `;

      return row && typeof row.count === 'number' ? row.count : Number(row?.count ?? 0);
    },
    async findDeviceById(deviceId) {
      const [row] = await query()<PushDeviceRow>`
        SELECT
          id,
          token,
          platform,
          provider,
          environment,
          app_version AS "appVersion",
          device_name AS "deviceName",
          registered_at AS "registeredAt",
          last_seen_at AS "lastSeenAt"
        FROM push_devices
        WHERE id = ${deviceId}
          AND is_active
        LIMIT 1
      `;

      return row ? pushDeviceFromRow(row) : undefined;
    },
    async findDeviceByLookupKey(lookupKey) {
      const [row] = await query()<PushDeviceRow>`
        SELECT
          id,
          token,
          platform,
          provider,
          environment,
          app_version AS "appVersion",
          device_name AS "deviceName",
          registered_at AS "registeredAt",
          last_seen_at AS "lastSeenAt"
        FROM push_devices
        WHERE lookup_key = ${lookupKey}
          AND is_active
        LIMIT 1
      `;

      return row ? pushDeviceFromRow(row) : undefined;
    },
    async listDevices() {
      const rows = await query()<PushDeviceRow>`
        SELECT
          id,
          token,
          platform,
          provider,
          environment,
          app_version AS "appVersion",
          device_name AS "deviceName",
          registered_at AS "registeredAt",
          last_seen_at AS "lastSeenAt"
        FROM push_devices
        WHERE is_active
        ORDER BY registered_at ASC, id ASC
      `;

      return rows.map(pushDeviceFromRow);
    },
    async saveDevice(device) {
      const [row] = await query()<PushDeviceRow>`
        INSERT INTO push_devices (
          id,
          lookup_key,
          token_hash,
          token,
          platform,
          provider,
          environment,
          app_version,
          device_name,
          registered_at,
          last_seen_at
        )
        VALUES (
          ${device.id},
          ${device.lookupKey},
          ${device.tokenHash},
          ${device.token},
          ${device.platform},
          ${device.provider},
          ${device.environment ?? null},
          ${device.appVersion ?? null},
          ${device.deviceName ?? null},
          ${device.registeredAt},
          ${device.lastSeenAt}
        )
        ON CONFLICT (id) DO UPDATE
        SET
          lookup_key = EXCLUDED.lookup_key,
          token_hash = EXCLUDED.token_hash,
          token = EXCLUDED.token,
          platform = EXCLUDED.platform,
          provider = EXCLUDED.provider,
          environment = EXCLUDED.environment,
          app_version = EXCLUDED.app_version,
          device_name = EXCLUDED.device_name,
          is_active = true,
          invalidated_at = NULL,
          last_seen_at = EXCLUDED.last_seen_at
        RETURNING
          id,
          token,
          platform,
          provider,
          environment,
          app_version AS "appVersion",
          device_name AS "deviceName",
          registered_at AS "registeredAt",
          last_seen_at AS "lastSeenAt"
      `;

      if (!row) {
        throw new Error('Expected push_devices upsert to return a row.');
      }

      return pushDeviceFromRow(row);
    },
    async invalidateDevice(deviceId) {
      await query()`
        UPDATE push_devices
        SET is_active = false, invalidated_at = now()
        WHERE id = ${deviceId} AND is_active
      `;
    },
  };
}

function pushDeviceFromRow(row: PushDeviceRow): RegisteredDevice {
  const environment = optionalString(row.environment);
  const appVersion = optionalString(row.appVersion);
  const deviceName = optionalString(row.deviceName);

  return {
    id: requiredString(row.id, 'push_devices.id'),
    token: requiredString(row.token, 'push_devices.token'),
    platform: requiredString(row.platform, 'push_devices.platform') as RegisteredDevice['platform'],
    provider: requiredString(row.provider, 'push_devices.provider') as RegisteredDevice['provider'],
    ...(environment ? { environment: environment as RegisteredDevice['environment'] } : {}),
    ...(appVersion ? { appVersion } : {}),
    ...(deviceName ? { deviceName } : {}),
    registeredAt: optionalISOString(row.registeredAt) ?? new Date(0).toISOString(),
    lastSeenAt: optionalISOString(row.lastSeenAt) ?? new Date(0).toISOString(),
  };
}
