import {
  GARAGE_NOTIFICATION_PREFERENCES,
  type DevicePreferenceLocator,
  type NotificationPreference,
  type NotificationPreferencesUpdateRequest,
  type NotificationPreferenceUpdate,
  type RegisteredDevice,
} from '../../contracts.js';
import {
  createDeviceLookupKey,
  type DeviceRegistry,
} from './deviceRegistry.js';

export type NotificationPreferenceStore = {
  getPreferences: (locator?: DevicePreferenceLocator) => NotificationPreference[];
  isNotificationEnabled: (device: RegisteredDevice, category: NotificationPreference['category']) => boolean;
  updatePreferences: (update: NotificationPreferencesUpdateRequest) => NotificationPreference[];
};

export function createInMemoryNotificationPreferenceStore(
  deviceRegistry: Pick<DeviceRegistry, 'getDevice'>,
): NotificationPreferenceStore {
  const preferencesByDeviceKey = new Map<string, NotificationPreference[]>();

  return {
    getPreferences(locator) {
      if (!locator) {
        return GARAGE_NOTIFICATION_PREFERENCES;
      }

      return preferencesByDeviceKey.get(preferenceKeyForLocator(locator, deviceRegistry)) ??
        GARAGE_NOTIFICATION_PREFERENCES;
    },
    isNotificationEnabled(device, category) {
      const preferences = preferencesByDeviceKey.get(preferenceKeyForDevice(device)) ??
        GARAGE_NOTIFICATION_PREFERENCES;
      const preference = preferences.find((entry) => entry.category === category);

      return preference?.isEnabled ?? true;
    },
    updatePreferences(update) {
      const deviceKey = preferenceKeyForLocator(update.locator, deviceRegistry);
      const preferences = applyPreferenceUpdates(GARAGE_NOTIFICATION_PREFERENCES, update.preferences);

      preferencesByDeviceKey.set(deviceKey, preferences);

      return preferences;
    },
  };
}

export function preferenceKeyForLocator(
  locator: DevicePreferenceLocator,
  deviceRegistry: Pick<DeviceRegistry, 'getDevice'>,
): string {
  if ('deviceId' in locator) {
    const device = deviceRegistry.getDevice(locator.deviceId);

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
