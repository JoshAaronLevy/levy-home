import {
  isNotificationPreferenceCategory,
  type DevicePreferenceLocator,
  type NotificationPreferencesUpdateRequest,
  type NotificationPreferenceUpdate,
  type TestPushPayload,
} from '../contracts/notifications.js';
import { HTTPError } from '../http/errors.js';
import { readAPNsEnvironment, readDeviceToken, readPushProvider } from './deviceValidation.js';
import { isPlainRecord, readOptionalStringOrThrow } from './shared.js';

export function validateTestPushBody(input: unknown): TestPushPayload {
  if (input === undefined || input === null) {
    return defaultTestPushPayload();
  }

  if (!isPlainRecord(input)) {
    throw new HTTPError(400, 'Expected a JSON object test-push payload.', 'invalid_test_push_payload');
  }

  const title = readOptionalStringOrThrow(input.title, 'title') ?? 'Levy Home test';
  const body =
    readOptionalStringOrThrow(input.body, 'body') ?? 'This is a test notification from Levy Home.';

  return { title, body };
}

export function validateNotificationPreferencesBody(input: unknown): NotificationPreferencesUpdateRequest {
  if (!isPlainRecord(input)) {
    throw new HTTPError(
      400,
      'Expected a JSON object notification-preferences payload.',
      'invalid_notification_preferences_payload',
    );
  }

  if (!Array.isArray(input.preferences)) {
    throw new HTTPError(400, 'preferences must be an array.', 'invalid_notification_preferences');
  }

  const preferences = input.preferences.map((preference, index) => {
    if (!isPlainRecord(preference)) {
      throw new HTTPError(
        400,
        `preferences[${index}] must be a JSON object.`,
        'invalid_notification_preference',
      );
    }

    if (!isNotificationPreferenceCategory(preference.category)) {
      throw new HTTPError(
        400,
        `Unsupported notification preference category at preferences[${index}].`,
        'unsupported_notification_preference',
      );
    }

    if (typeof preference.isEnabled !== 'boolean') {
      throw new HTTPError(
        400,
        `preferences[${index}].isEnabled must be a boolean.`,
        'invalid_notification_preference',
      );
    }

    return {
      category: preference.category,
      isEnabled: preference.isEnabled,
    } satisfies NotificationPreferenceUpdate;
  });

  return {
    preferences,
    locator: readDevicePreferenceLocator(input),
  };
}

export function validateNotificationPreferencesQuery(
  input: Record<string, unknown>,
): DevicePreferenceLocator | undefined {
  if (typeof input.deviceId === 'string' && input.deviceId.trim()) {
    return { deviceId: input.deviceId.trim() };
  }

  const tokenValue = typeof input.deviceToken === 'string' ? input.deviceToken : input.token;
  if (typeof tokenValue !== 'string' || tokenValue.trim().length === 0) {
    return undefined;
  }

  const provider = readPushProvider(input.provider, false);
  const environment = readAPNsEnvironment(input.environment, provider);

  return {
    token: tokenValue.trim(),
    provider,
    ...(environment ? { environment } : {}),
  };
}

function defaultTestPushPayload(): TestPushPayload {
  return {
    title: 'Levy Home test',
    body: 'This is a test notification from Levy Home.',
  };
}

function readDevicePreferenceLocator(input: Record<string, unknown>): DevicePreferenceLocator {
  if (typeof input.deviceId === 'string' && input.deviceId.trim()) {
    return { deviceId: input.deviceId.trim() };
  }

  const token = readDeviceToken(input);
  const provider = readPushProvider(input.provider, input.pushToken !== undefined);
  const environment = readAPNsEnvironment(input.environment, provider);

  return {
    token,
    provider,
    ...(environment ? { environment } : {}),
  };
}
