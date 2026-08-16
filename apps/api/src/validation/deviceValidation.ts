import type {
  APNsEnvironment,
  DevicePlatform,
  PushProvider,
  RegisterDeviceRequest,
} from '../contracts/notifications.js';
import { HTTPError } from '../http/errors.js';
import { isPlainRecord, readOptionalStringOrThrow } from './shared.js';

const devicePlatforms = new Set<DevicePlatform>(['ios', 'android', 'unknown']);
const pushProviders = new Set<PushProvider>(['apns', 'expo']);
const apnsEnvironments = new Set<APNsEnvironment>(['sandbox', 'production']);

export function validateRegisterDeviceBody(input: unknown): RegisterDeviceRequest {
  if (!isPlainRecord(input)) {
    throw new HTTPError(400, 'Expected a JSON object device registration payload.', 'invalid_device_registration');
  }

  const token = readDeviceToken(input);
  const provider = readPushProvider(input.provider, input.pushToken !== undefined);
  const platform = readDevicePlatform(input.platform, provider);
  const environment = readAPNsEnvironment(input.environment, provider);
  const appVersion = readOptionalStringOrThrow(input.appVersion, 'appVersion');
  const deviceName = readOptionalStringOrThrow(input.deviceName, 'deviceName');
  const includeDeviceCount = readOptionalBoolean(input.includeDeviceCount, 'includeDeviceCount');

  return {
    token,
    platform,
    provider,
    ...(environment ? { environment } : {}),
    ...(appVersion ? { appVersion } : {}),
    ...(deviceName ? { deviceName } : {}),
    ...(includeDeviceCount !== undefined ? { includeDeviceCount } : {}),
  };
}

function readOptionalBoolean(value: unknown, fieldName: string): boolean | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (typeof value === 'boolean') {
    return value;
  }

  throw new HTTPError(400, `${fieldName} must be a boolean when provided.`, `invalid_${fieldName}`);
}

export function readDeviceToken(input: Record<string, unknown>): string {
  const value = input.token ?? input.deviceToken ?? input.pushToken;

  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new HTTPError(400, 'token is required and must be a non-empty string.', 'invalid_device_token');
  }

  return value.trim();
}

export function readPushProvider(value: unknown, inferredExpo: boolean): PushProvider {
  if (value === undefined) {
    if (inferredExpo) {
      return 'expo';
    }

    throw new HTTPError(
      400,
      'provider is required for provider-aware device registrations.',
      'missing_push_provider',
    );
  }

  if (typeof value === 'string' && pushProviders.has(value as PushProvider)) {
    return value as PushProvider;
  }

  throw new HTTPError(400, 'provider must be apns or expo.', 'invalid_push_provider');
}

function readDevicePlatform(value: unknown, provider: PushProvider): DevicePlatform {
  if (value === undefined) {
    return provider === 'apns' ? 'ios' : 'unknown';
  }

  if (typeof value === 'string' && devicePlatforms.has(value as DevicePlatform)) {
    const platform = value as DevicePlatform;

    if (provider === 'apns' && platform !== 'ios') {
      throw new HTTPError(400, 'APNs device registrations must use platform ios.', 'invalid_device_platform');
    }

    return platform;
  }

  throw new HTTPError(400, 'platform must be ios, android, or unknown.', 'invalid_device_platform');
}

export function readAPNsEnvironment(value: unknown, provider: PushProvider): APNsEnvironment | undefined {
  if (provider === 'expo') {
    if (value === undefined) {
      return undefined;
    }

    if (typeof value === 'string' && apnsEnvironments.has(value as APNsEnvironment)) {
      return value as APNsEnvironment;
    }

    throw new HTTPError(400, 'environment must be sandbox or production when provided.', 'invalid_apns_environment');
  }

  if (typeof value === 'string' && apnsEnvironments.has(value as APNsEnvironment)) {
    return value as APNsEnvironment;
  }

  throw new HTTPError(
    400,
    'APNs device registrations require environment sandbox or production.',
    'missing_apns_environment',
  );
}
