import { APNsConfigurationError, type PushSender } from '../../integrations/apple/apnsPushSender.js';
import {
  getEventDisplayMetadata,
  isNotificationPreferenceCategory,
  type APNsSendResult,
  type EventPushStatus,
  type HomeAssistantEventPayload,
  type NotificationPreferenceCategory,
  type PushSendSummary,
  type RegisteredDevice,
  type TestPushPayload,
} from '../../contracts.js';
import type { DeviceRegistry } from './deviceRegistry.js';
import type { NotificationPreferenceStore } from './notificationPreferenceStore.js';

export type PushSendOptions = {
  devices: RegisteredDevice[];
  notificationPreferenceStore: Pick<NotificationPreferenceStore, 'isNotificationEnabled'>;
  pushSender: PushSender;
  payload: TestPushPayload;
  preferenceCategory?: NotificationPreferenceCategory;
};

export type NotificationService = {
  sendEventPush: (payload: HomeAssistantEventPayload) => Promise<EventPushStatus>;
  sendTestPush: (payload: TestPushPayload) => Promise<PushSendSummary>;
};

export function createNotificationService(options: {
  deviceRegistry: Pick<DeviceRegistry, 'listDevices'>;
  notificationPreferenceStore: Pick<NotificationPreferenceStore, 'isNotificationEnabled'>;
  pushSender: PushSender;
}): NotificationService {
  return {
    async sendEventPush(payload) {
      const display = getEventDisplayMetadata(payload.type);
      const preferenceCategory = notificationCategoryForEvent(payload);
      const summary = preferenceCategory
        ? await sendPushToRegisteredDevices({
            devices: options.deviceRegistry.listDevices(),
            notificationPreferenceStore: options.notificationPreferenceStore,
            pushSender: options.pushSender,
            payload: {
              title: payload.title ?? display.title,
              body: payload.message ?? display.body,
            },
            preferenceCategory,
          })
        : undefined;

      return summary
        ? pushStatusFromSummary(summary, preferenceCategory)
        : {
            attempted: false,
            skipped: true,
            reason: 'No APNs notification preference category is configured for this event type.',
          };
    },
    sendTestPush(payload) {
      return sendPushToRegisteredDevices({
        devices: options.deviceRegistry.listDevices(),
        notificationPreferenceStore: options.notificationPreferenceStore,
        pushSender: options.pushSender,
        payload,
        preferenceCategory: undefined,
      });
    },
  };
}

export async function sendPushToRegisteredDevices(options: PushSendOptions): Promise<PushSendSummary> {
  const apnsDevices = options.devices.filter((device) => device.provider === 'apns');
  const preferenceCategory = options.preferenceCategory;
  const enabledDevices = preferenceCategory
    ? apnsDevices.filter((device) =>
        options.notificationPreferenceStore.isNotificationEnabled(device, preferenceCategory),
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
