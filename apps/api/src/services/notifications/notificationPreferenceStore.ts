import {
  DEFAULT_NOTIFICATION_PREFERENCES,
  type DevicePreferenceLocator,
  type NotificationPreference,
  type NotificationPreferencesUpdateRequest,
  type NotificationPreferenceUpdate,
  type RegisteredDevice,
} from '../../contracts.js';
import {
  createInMemoryNotificationPreferenceRepository,
  createPostgresNotificationPreferenceRepository,
  type NotificationPreferenceRepository,
} from '../../repositories/notificationPreferenceRepository.js';
import {
  createDeviceLookupKey,
  type DeviceRegistry,
} from './deviceRegistry.js';

export type NotificationPreferenceStore = {
  getPreferences: (locator?: DevicePreferenceLocator) => Promise<NotificationPreference[]>;
  isNotificationEnabled: (
    device: RegisteredDevice,
    category: NotificationPreference['category'],
  ) => Promise<boolean>;
  updatePreferences: (update: NotificationPreferencesUpdateRequest) => Promise<NotificationPreference[]>;
};

export function createNotificationPreferenceStore(
  deviceRegistry: Pick<DeviceRegistry, 'getDevice'>,
  repository: NotificationPreferenceRepository,
): NotificationPreferenceStore {
  return {
    async getPreferences(locator) {
      if (!locator) {
        return DEFAULT_NOTIFICATION_PREFERENCES;
      }

      const deviceKey = await preferenceKeyForLocator(locator, deviceRegistry);
      const updates = await repository.getPreferenceUpdates(deviceKey);

      return updates
        ? applyPreferenceUpdates(DEFAULT_NOTIFICATION_PREFERENCES, updates)
        : DEFAULT_NOTIFICATION_PREFERENCES;
    },
    async isNotificationEnabled(device, category) {
      const updates = await repository.getPreferenceUpdates(preferenceKeyForDevice(device));
      const preferences = updates
        ? applyPreferenceUpdates(DEFAULT_NOTIFICATION_PREFERENCES, updates)
        : DEFAULT_NOTIFICATION_PREFERENCES;
      const preference = preferences.find((entry) => entry.category === category);

      return preference?.isEnabled ?? true;
    },
    async updatePreferences(update) {
      const deviceKey = await preferenceKeyForLocator(update.locator, deviceRegistry);
      const preferences = applyPreferenceUpdates(DEFAULT_NOTIFICATION_PREFERENCES, update.preferences);

      await repository.savePreferences(deviceKey, preferences);

      return preferences;
    },
  };
}

export function createInMemoryNotificationPreferenceStore(
  deviceRegistry: Pick<DeviceRegistry, 'getDevice'>,
  repository: NotificationPreferenceRepository = createInMemoryNotificationPreferenceRepository(),
): NotificationPreferenceStore {
  return createNotificationPreferenceStore(deviceRegistry, repository);
}

export function createPostgresNotificationPreferenceStore(
  deviceRegistry: Pick<DeviceRegistry, 'getDevice'>,
): NotificationPreferenceStore {
  return createNotificationPreferenceStore(deviceRegistry, createPostgresNotificationPreferenceRepository());
}

export async function preferenceKeyForLocator(
  locator: DevicePreferenceLocator,
  deviceRegistry: Pick<DeviceRegistry, 'getDevice'>,
): Promise<string> {
  if ('deviceId' in locator) {
    const device = await deviceRegistry.getDevice(locator.deviceId);

    if (device) {
      return preferenceKeyForDevice(device);
    }

    return `device-id:${locator.deviceId}`;
  }

  return `device-token:${createDeviceLookupKey(locator)}`;
}

export function applyPreferenceUpdates(
  defaults: NotificationPreference[],
  updates: NotificationPreferenceUpdate[],
): NotificationPreference[] {
  const enabledByCategory = new Map(updates.map((update) => [update.category, update.isEnabled]));

  return defaults.map((preference) => ({
    ...preference,
    isEnabled: enabledByCategory.get(preference.category) ?? preference.isEnabled,
  }));
}

function preferenceKeyForDevice(device: Pick<RegisteredDevice, 'token' | 'provider' | 'environment'>): string {
  return `device-token:${createDeviceLookupKey(device)}`;
}
