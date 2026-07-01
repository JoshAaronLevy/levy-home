import { APNsConfigurationError, type PushSender } from '../apnsService.js';
import {
  GARAGE_NOTIFICATION_PREFERENCES,
  isNotificationPreferenceCategory,
  type APNsSendResult,
  type EventPushStatus,
  type HomeAssistantEventPayload,
  type NotificationPreference,
  type NotificationPreferenceCategory,
  type PushSendSummary,
  type RegisteredDevice,
  type TestPushPayload,
} from '../contracts.js';
import { preferenceKeyForLocator } from './routeState.js';

export type PushSendOptions = {
  devices: RegisteredDevice[];
  preferencesByDeviceKey: Map<string, NotificationPreference[]>;
  pushSender: PushSender;
  payload: TestPushPayload;
  preferenceCategory?: NotificationPreferenceCategory;
};

export async function sendPushToRegisteredDevices(options: PushSendOptions): Promise<PushSendSummary> {
  const apnsDevices = options.devices.filter((device) => device.provider === 'apns');
  const preferenceCategory = options.preferenceCategory;
  const enabledDevices = preferenceCategory
    ? apnsDevices.filter((device) =>
        isNotificationPreferenceEnabled(device, preferenceCategory, options.preferencesByDeviceKey),
      )
    : apnsDevices;
  const results: APNsSendResult[] = [];
  let configurationError: string | undefined;

  for (const device of enabledDevices) {
    try {
      results.push(
        await options.pushSender.send({
          device,
          title: options.payload.title,
          body: options.payload.body,
          data: options.preferenceCategory ? { category: options.preferenceCategory } : { debug: 'true' },
        }),
      );
    } catch (error) {
      if (error instanceof APNsConfigurationError) {
        configurationError = error.message;
        break;
      }

      results.push({
        provider: 'apns',
        deviceId: device.id,
        success: false,
        reason: error instanceof Error ? error.message : String(error),
        isInvalidToken: false,
      });
    }
  }

  const invalidTokenCount = results.filter((result) => result.isInvalidToken).length;

  return {
    provider: 'apns',
    registeredDeviceCount: options.devices.length,
    eligibleDeviceCount: enabledDevices.length,
    sentNotificationCount: results.filter((result) => result.success).length,
    failedNotificationCount: results.filter((result) => !result.success).length,
    invalidTokenCount,
    skippedDeviceCount: apnsDevices.length - enabledDevices.length,
    ...(configurationError ? { configurationError } : {}),
    results,
  };
}

export function testPushMessage(summary: PushSendSummary): string {
  if (summary.registeredDeviceCount === 0) {
    return 'No registered devices are available for test push.';
  }

  if (summary.eligibleDeviceCount === 0) {
    return 'No registered APNs devices are available for test push.';
  }

  return `Sent ${summary.sentNotificationCount} APNs test notification(s).`;
}

export function pushStatusFromSummary(
  summary: PushSendSummary,
  preferenceCategory?: NotificationPreferenceCategory,
): EventPushStatus {
  if (summary.configurationError) {
    return {
      attempted: false,
      skipped: true,
      reason: summary.configurationError,
    };
  }

  if (summary.registeredDeviceCount === 0 || summary.eligibleDeviceCount === 0) {
    return {
      attempted: false,
      skipped: true,
      reason:
        preferenceCategory && summary.skippedDeviceCount > 0
          ? 'All registered APNs devices have this notification disabled.'
          : 'No registered APNs devices are available for push delivery.',
    };
  }

  return {
    attempted: true,
    skipped: false,
    ticketCount: summary.sentNotificationCount,
    sentNotificationCount: summary.sentNotificationCount,
    failedNotificationCount: summary.failedNotificationCount,
    invalidTokenCount: summary.invalidTokenCount,
    ...(summary.failedNotificationCount > 0
      ? { reason: `${summary.failedNotificationCount} APNs notification(s) failed to send.` }
      : {}),
  };
}

export function notificationCategoryForEvent(
  payload: HomeAssistantEventPayload,
): NotificationPreferenceCategory | undefined {
  const categoryByEventType: Partial<Record<HomeAssistantEventPayload['type'], NotificationPreferenceCategory>> = {
    garage_opened: 'garage_opened',
    garage_closed: 'garage_closed',
    garage_left_open_10_min: 'garage_left_open',
    garage_opened_after_hours: 'garage_after_hours',
    garage_still_open_at_10pm: 'garage_still_open_at_10pm',
  };
  const category = categoryByEventType[payload.type];

  return isNotificationPreferenceCategory(category) ? category : undefined;
}

function isNotificationPreferenceEnabled(
  device: RegisteredDevice,
  category: NotificationPreferenceCategory,
  preferencesByDeviceKey: Map<string, NotificationPreference[]>,
): boolean {
  const preferences =
    preferencesByDeviceKey.get(
      preferenceKeyForLocator(
        { token: device.token, provider: device.provider, environment: device.environment },
        new Map(),
      ),
    ) ?? GARAGE_NOTIFICATION_PREFERENCES;
  const preference = preferences.find((entry) => entry.category === category);

  return preference?.isEnabled ?? true;
}
