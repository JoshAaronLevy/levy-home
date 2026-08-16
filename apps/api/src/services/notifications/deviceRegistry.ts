import crypto from 'node:crypto';

import type {
  RegisterDeviceRequest,
  RegisteredDevice,
} from '../../contracts.js';
import {
  createInMemoryPushDeviceRepository,
  createPostgresPushDeviceRepository,
  type PushDeviceRepository,
} from '../../repositories/pushDeviceRepository.js';

export type DeviceRegistrationResult = {
  device: RegisteredDevice;
  registeredDeviceCount?: number;
  statusCode: 200 | 201;
};

export type DeviceRegistry = {
  count: () => Promise<number>;
  getDevice: (deviceId: string) => Promise<RegisteredDevice | undefined>;
  listDevices: () => Promise<RegisteredDevice[]>;
  invalidateDevice: (deviceId: string) => Promise<void>;
  registerDevice: (registration: RegisterDeviceRequest) => Promise<DeviceRegistrationResult>;
};

export function createDeviceRegistry(repository: PushDeviceRepository): DeviceRegistry {
  return {
    count() {
      return repository.countDevices();
    },
    getDevice(deviceId) {
      return repository.findDeviceById(deviceId);
    },
    listDevices() {
      return repository.listDevices();
    },
    invalidateDevice(deviceId) {
      return repository.invalidateDevice(deviceId);
    },
    async registerDevice(registration) {
      const lookupKey = createDeviceLookupKey(registration);
      const existingDevice = await repository.findDeviceByLookupKey(lookupKey);
      const now = new Date().toISOString();
      const device: RegisteredDevice = {
        ...existingDevice,
        id: existingDevice?.id ?? createDeviceId(registration),
        token: registration.token,
        platform: registration.platform,
        provider: registration.provider,
        ...(registration.environment ? { environment: registration.environment } : {}),
        ...(registration.appVersion ? { appVersion: registration.appVersion } : {}),
        ...(registration.deviceName ? { deviceName: registration.deviceName } : {}),
        registeredAt: existingDevice?.registeredAt ?? now,
        lastSeenAt: now,
      };
      const savedDevice = await repository.saveDevice({
        ...device,
        lookupKey,
        tokenHash: createDeviceTokenHash(registration.token),
      });

      return {
        device: savedDevice,
        ...(registration.includeDeviceCount === false
          ? {}
          : { registeredDeviceCount: await repository.countDevices() }),
        statusCode: existingDevice ? 200 : 201,
      };
    },
  };
}

export function createInMemoryDeviceRegistry(
  repository: PushDeviceRepository = createInMemoryPushDeviceRepository(),
): DeviceRegistry {
  return createDeviceRegistry(repository);
}

export function createPostgresDeviceRegistry(): DeviceRegistry {
  return createDeviceRegistry(createPostgresPushDeviceRepository());
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

export function createDeviceTokenHash(token: string): string {
  return hashToken(token);
}

export function deviceResponse(device: RegisteredDevice): Omit<RegisteredDevice, 'token'> {
  const { token: _token, ...response } = device;
  return response;
}

function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}
