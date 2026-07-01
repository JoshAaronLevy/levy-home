import {
  type NotificationPreference,
  type NotificationPreferenceUpdate,
} from '../contracts.js';
import { getDatabaseClient, type DatabaseQuery } from '../db/client.js';
import { jsonb, parseJSONBValue, requiredString } from '../db/rowReaders.js';

export type NotificationPreferenceRepository = {
  getPreferenceUpdates: (deviceKey: string) => Promise<NotificationPreferenceUpdate[] | undefined>;
  savePreferences: (
    deviceKey: string,
    preferences: NotificationPreference[],
  ) => Promise<NotificationPreferenceUpdate[]>;
};

type NotificationPreferenceRow = Record<string, unknown> & {
  deviceKey: unknown;
  preferences: unknown;
};

export function createInMemoryNotificationPreferenceRepository(): NotificationPreferenceRepository {
  const preferencesByDeviceKey = new Map<string, NotificationPreferenceUpdate[]>();

  return {
    async getPreferenceUpdates(deviceKey) {
      return preferencesByDeviceKey.get(deviceKey);
    },
    async savePreferences(deviceKey, preferences) {
      const updates = preferences.map(preferenceUpdateFromPreference);

      preferencesByDeviceKey.set(deviceKey, updates);

      return updates;
    },
  };
}

export function createPostgresNotificationPreferenceRepository(
  database?: DatabaseQuery,
): NotificationPreferenceRepository {
  const query = () => database ?? getDatabaseClient();

  return {
    async getPreferenceUpdates(deviceKey) {
      const [row] = await query()<NotificationPreferenceRow>`
        SELECT
          device_key AS "deviceKey",
          preferences
        FROM notification_preferences
        WHERE device_key = ${deviceKey}
        LIMIT 1
      `;

      return row ? preferenceUpdatesFromRow(row) : undefined;
    },
    async savePreferences(deviceKey, preferences) {
      const [row] = await query()<NotificationPreferenceRow>`
        INSERT INTO notification_preferences (
          device_key,
          preferences,
          updated_at
        )
        VALUES (
          ${deviceKey},
          ${jsonb(preferences.map(preferenceUpdateFromPreference))}::jsonb,
          now()
        )
        ON CONFLICT (device_key) DO UPDATE
        SET
          preferences = EXCLUDED.preferences,
          updated_at = EXCLUDED.updated_at
        RETURNING
          device_key AS "deviceKey",
          preferences
      `;

      if (!row) {
        throw new Error('Expected notification_preferences upsert to return a row.');
      }

      return preferenceUpdatesFromRow(row);
    },
  };
}

function preferenceUpdatesFromRow(row: NotificationPreferenceRow): NotificationPreferenceUpdate[] {
  requiredString(row.deviceKey, 'notification_preferences.device_key');
  const parsedPreferences = parseJSONBValue(row.preferences);

  if (!Array.isArray(parsedPreferences)) {
    return [];
  }

  return parsedPreferences
    .map(preferenceUpdateFromValue)
    .filter((preference): preference is NotificationPreferenceUpdate => preference !== undefined);
}

function preferenceUpdateFromValue(value: unknown): NotificationPreferenceUpdate | undefined {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return undefined;
  }

  const record = value as Record<string, unknown>;

  if (typeof record.category !== 'string' || typeof record.isEnabled !== 'boolean') {
    return undefined;
  }

  return {
    category: record.category as NotificationPreferenceUpdate['category'],
    isEnabled: record.isEnabled,
  };
}

function preferenceUpdateFromPreference(preference: NotificationPreference): NotificationPreferenceUpdate {
  return {
    category: preference.category,
    isEnabled: preference.isEnabled,
  };
}
