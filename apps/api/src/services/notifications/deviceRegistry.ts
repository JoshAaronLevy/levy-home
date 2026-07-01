import crypto from 'node:crypto';

import type {
  RegisterDeviceRequest,
  RegisteredDevice,
} from '../../contracts.js';

export type DeviceRegistrationResult = {
  device: RegisteredDevice;
  registeredDeviceCount: number;
  statusCode: 200 | 201;
};

export type DeviceRegistry = {
  count: () => number;
  getDevice: (deviceId: string) => RegisteredDevice | undefined;
  listDevices: () => RegisteredDevice[];
  registerDevice: (registration: RegisterDeviceRequest) => DeviceRegistrationResult;
};

export function createInMemoryDeviceRegistry(): DeviceRegistry {
  const registeredDevicesById = new Map<string, RegisteredDevice>();
  const registeredDeviceIdsByLookupKey = new Map<string, string>();

  return {
    count() {
      return registeredDevicesById.size;
    },
    getDevice(deviceId) {
      return registeredDevicesById.get(deviceId);
    },
    listDevices() {
      return Array.from(registeredDevicesById.values());
    },
    registerDevice(registration) {
      const lookupKey = createDeviceLookupKey(registration);
      const existingDeviceId = registeredDeviceIdsByLookupKey.get(lookupKey);
      const now = new Date().toISOString();
      const device: RegisteredDevice = {
        ...(existingDeviceId ? registeredDevicesById.get(existingDeviceId) : undefined),
        id: existingDeviceId ?? createDeviceId(registration),
        token: registration.token,
        platform: registration.platform,
        provider: registration.provider,
        ...(registration.environment ? { environment: registration.environment } : {}),
        ...(registration.appVersion ? { appVersion: registration.appVersion } : {}),
        ...(registration.deviceName ? { deviceName: registration.deviceName } : {}),
        registeredAt: existingDeviceId
          ? (registeredDevicesById.get(existingDeviceId)?.registeredAt ?? now)
          : now,
        lastSeenAt: now,
      };

      registeredDevicesById.set(device.id, device);
      registeredDeviceIdsByLookupKey.set(lookupKey, device.id);

      return {
        device,
        registeredDeviceCount: registeredDevicesById.size,
        statusCode: existingDeviceId ? 200 : 201,
      };
    },
  };
}

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

function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}
