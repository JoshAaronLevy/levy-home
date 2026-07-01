import crypto from 'node:crypto';

import type {
  DevicePreferenceLocator,
  NotificationPreference,
  RegisteredDevice,
} from '../contracts.js';

export type RegisteredDeviceState = {
  registeredDevicesById: Map<string, RegisteredDevice>;
  registeredDeviceIdsByLookupKey: Map<string, string>;
};

export type NotificationPreferenceState = {
  preferencesByDeviceKey: Map<string, NotificationPreference[]>;
};

export function createDeviceLookupKey(
  registration: Pick<RegisteredDevice, 'token' | 'provider' | 'environment'>,
): string {
  const environment = registration.provider === 'apns' ? registration.environment : (registration.environment ?? 'none');

  return `${registration.provider}:${environment}:${hashToken(registration.token)}`;
}

export function createDeviceId(
  registration: Pick<RegisteredDevice, 'token' | 'provider' | 'environment'>,
): string {
  const environment = registration.provider === 'apns' ? registration.environment : 'none';
  const prefix = registration.provider === 'apns' ? `apns-${environment}` : 'expo';

  return `${prefix}-${hashToken(registration.token).slice(0, 16)}`;
}

export function deviceResponse(device: RegisteredDevice): Omit<RegisteredDevice, 'token'> {
  const { token: _token, ...response } = device;
  return response;
}

export function preferenceKeyForLocator(
  locator: DevicePreferenceLocator,
  registeredDevicesById: Map<string, RegisteredDevice>,
): string {
  if ('deviceId' in locator) {
    const device = registeredDevicesById.get(locator.deviceId);

    if (device) {
      return `device-token:${createDeviceLookupKey(device)}`;
    }

    return `device-id:${locator.deviceId}`;
  }

  return `device-token:${createDeviceLookupKey(locator)}`;
}

function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}
