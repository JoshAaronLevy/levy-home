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
  data?: Record<string, string>;
};

export type ListMutationPushAction = 'created' | 'updated' | 'deleted' | 'completed';

export type ListMutationPushPayload = {
  listType: 'shopping' | 'todo';
  action: ListMutationPushAction;
  itemName: string;
  actor?: string;
};

export type ListSessionPushAction = 'created';

export type ListSessionPushPayload = {
  listType: 'todo';
  action: ListSessionPushAction;
  itemNames: string[];
  actor?: string;
};

export type WeatherAlertPushPayload = {
  title: string;
  body: string;
  kind: string;
  startsAt: string;
  endsAt?: string;
  chance: number;
};

export type NotificationService = {
  sendEventPush: (payload: HomeAssistantEventPayload) => Promise<EventPushStatus>;
  sendListMutationPush: (payload: ListMutationPushPayload) => Promise<EventPushStatus>;
  sendListSessionPush: (payload: ListSessionPushPayload) => Promise<EventPushStatus>;
  sendWeatherAlertPush: (payload: WeatherAlertPushPayload) => Promise<EventPushStatus>;
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
      const devices = await options.deviceRegistry.listDevices();
      const recipientTarget = notificationRecipientTargetForEvent(payload);
      const targetDevices = recipientTarget
        ? filterDevicesForRecipient(devices, recipientTarget)
        : devices;

      if (recipientTarget && targetDevices.length === 0) {
        return {
          attempted: false,
          skipped: true,
          reason: `No registered APNs devices match recipient "${recipientTarget}".`,
        };
      }

      const summary = preferenceCategory
        ? await sendPushToRegisteredDevices({
            devices: targetDevices,
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
    async sendListMutationPush(payload) {
      const actor = readNotificationActor(payload.actor);

      if (!actor) {
        return {
          attempted: false,
          skipped: true,
          reason: 'No list mutation actor was provided for push delivery.',
        };
      }

      const devices = await options.deviceRegistry.listDevices();
      const recipient = counterpartRecipientForActor(actor);
      const targetDevices = recipient
        ? filterDevicesForRecipient(devices, recipient)
        : filterDevicesExcludingActor(devices, actor);

      if (targetDevices.length === 0) {
        return {
          attempted: false,
          skipped: true,
          reason: recipient
            ? `No registered APNs devices match recipient "${recipient}".`
            : `No registered APNs devices match someone other than "${actor}".`,
        };
      }

      const preferenceCategory = notificationCategoryForList(payload.listType);
      const summary = await sendPushToRegisteredDevices({
        devices: targetDevices,
        notificationPreferenceStore: options.notificationPreferenceStore,
        pushSender: options.pushSender,
        payload: {
          title: titleForListMutation(payload.listType),
          body: bodyForListMutation({
            ...payload,
            actor,
          }),
        },
        preferenceCategory,
        data: {
          category: preferenceCategory,
          listType: payload.listType,
          action: payload.action,
          actor,
          itemName: payload.itemName,
        },
      });

      return pushStatusFromSummary(summary, preferenceCategory);
    },
    async sendListSessionPush(payload) {
      const actor = readNotificationActor(payload.actor);
      const itemNames = normalizeListSessionItemNames(payload.itemNames);

      if (!actor) {
        return {
          attempted: false,
          skipped: true,
          reason: 'No list session actor was provided for push delivery.',
        };
      }

      if (itemNames.length === 0) {
        return {
          attempted: false,
          skipped: true,
          reason: 'No list session items were provided for push delivery.',
        };
      }

      const devices = await options.deviceRegistry.listDevices();
      const recipient = counterpartRecipientForActor(actor);
      const targetDevices = recipient
        ? filterDevicesForRecipient(devices, recipient)
        : filterDevicesExcludingActor(devices, actor);

      if (targetDevices.length === 0) {
        return {
          attempted: false,
          skipped: true,
          reason: recipient
            ? `No registered APNs devices match recipient "${recipient}".`
            : `No registered APNs devices match someone other than "${actor}".`,
        };
      }

      const preferenceCategory = notificationCategoryForList(payload.listType);
      const summary = await sendPushToRegisteredDevices({
        devices: targetDevices,
        notificationPreferenceStore: options.notificationPreferenceStore,
        pushSender: options.pushSender,
        payload: {
          title: titleForListMutation(payload.listType),
          body: bodyForListSession({
            ...payload,
            actor,
            itemNames,
          }),
        },
        preferenceCategory,
        data: {
          category: preferenceCategory,
          listType: payload.listType,
          action: payload.action,
          actor,
          itemCount: String(itemNames.length),
        },
      });

      return pushStatusFromSummary(summary, preferenceCategory);
    },
    async sendWeatherAlertPush(payload) {
      const devices = await options.deviceRegistry.listDevices();
      const preferenceCategory: NotificationPreferenceCategory = 'weather_alerts';
      const summary = await sendPushToRegisteredDevices({
        devices,
        notificationPreferenceStore: options.notificationPreferenceStore,
        pushSender: options.pushSender,
        payload: {
          title: payload.title,
          body: payload.body,
        },
        preferenceCategory,
        data: {
          category: preferenceCategory,
          weatherKind: payload.kind,
          startsAt: payload.startsAt,
          ...(payload.endsAt ? { endsAt: payload.endsAt } : {}),
          chance: String(payload.chance),
        },
      });

      return pushStatusFromSummary(summary, preferenceCategory);
    },
    async sendTestPush(payload) {
      const devices = await options.deviceRegistry.listDevices();

      return sendPushToRegisteredDevices({
        devices,
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
    ? await filterPreferenceEnabledDevices(
        apnsDevices,
        options.notificationPreferenceStore,
        preferenceCategory,
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
          data: options.data ?? (options.preferenceCategory ? { category: options.preferenceCategory } : { debug: 'true' }),
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

async function filterPreferenceEnabledDevices(
  devices: RegisteredDevice[],
  notificationPreferenceStore: Pick<NotificationPreferenceStore, 'isNotificationEnabled'>,
  preferenceCategory: NotificationPreferenceCategory,
): Promise<RegisteredDevice[]> {
  const devicePreferencePairs = await Promise.all(
    devices.map(async (device) => ({
      device,
      isEnabled: await notificationPreferenceStore.isNotificationEnabled(device, preferenceCategory),
    })),
  );

  return devicePreferencePairs
    .filter(({ isEnabled }) => isEnabled)
    .map(({ device }) => device);
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
    partner_left_home: 'partner_presence',
    partner_arrived_home: 'partner_presence',
    study_lights_on: 'lighting_automation',
  };
  const category = categoryByEventType[payload.type];

  return isNotificationPreferenceCategory(category) ? category : undefined;
}

function notificationRecipientTargetForEvent(payload: HomeAssistantEventPayload): string | undefined {
  if (payload.type !== 'partner_left_home' && payload.type !== 'partner_arrived_home') {
    return undefined;
  }

  const recipient = payload.metadata?.recipient;

  return typeof recipient === 'string' && recipient.trim().length > 0
    ? recipient.trim()
    : undefined;
}

function filterDevicesForRecipient(
  devices: RegisteredDevice[],
  recipient: string,
): RegisteredDevice[] {
  const normalizedRecipient = normalizeRecipientText(recipient);

  if (!normalizedRecipient) {
    return devices;
  }

  return devices.filter((device) => {
    const normalizedDeviceName = normalizeRecipientText(device.deviceName);

    return normalizedDeviceName.includes(normalizedRecipient);
  });
}

function filterDevicesExcludingActor(
  devices: RegisteredDevice[],
  actor: string,
): RegisteredDevice[] {
  const normalizedActor = normalizeRecipientText(actor);

  if (!normalizedActor) {
    return [];
  }

  return devices.filter((device) => {
    const normalizedDeviceName = normalizeRecipientText(device.deviceName);

    return normalizedDeviceName.length > 0 && !normalizedDeviceName.includes(normalizedActor);
  });
}

function notificationCategoryForList(listType: ListMutationPushPayload['listType']): NotificationPreferenceCategory {
  return listType === 'shopping' ? 'shopping_list' : 'todo_list';
}

function readNotificationActor(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : undefined;
}

function counterpartRecipientForActor(actor: string): string | undefined {
  const normalizedActor = normalizeRecipientText(actor);

  if (normalizedActor.includes('josh')) {
    return 'Mallory';
  }

  if (normalizedActor.includes('mallory')) {
    return 'Josh';
  }

  return undefined;
}

function titleForListMutation(listType: ListMutationPushPayload['listType']): string {
  return listType === 'shopping' ? 'Shopping list updated' : 'To-do list updated';
}

function bodyForListMutation(payload: ListMutationPushPayload & { actor: string }): string {
  const itemName = payload.itemName.trim().length > 0 ? payload.itemName.trim() : 'an item';

  switch (payload.action) {
    case 'created':
      return `${payload.actor} added ${itemName}.`;
    case 'deleted':
      return `${payload.actor} removed ${itemName}.`;
    case 'completed':
      return payload.listType === 'shopping'
        ? `${payload.actor} checked off ${itemName}.`
        : `${payload.actor} completed ${itemName}.`;
    case 'updated':
      return `${payload.actor} updated ${itemName}.`;
  }
}

function bodyForListSession(payload: ListSessionPushPayload & { actor: string; itemNames: string[] }): string {
  if (payload.itemNames.length === 1) {
    return `${payload.actor} added ${payload.itemNames[0]}.`;
  }

  return `${payload.actor} added ${payload.itemNames.length} to-do items: ${formatListItemNames(payload.itemNames)}.`;
}

function normalizeListSessionItemNames(itemNames: unknown[]): string[] {
  return itemNames
    .map((itemName) => (typeof itemName === 'string' ? itemName.trim() : ''))
    .filter((itemName) => itemName.length > 0);
}

function formatListItemNames(itemNames: string[]): string {
  const displayNames = itemNames.slice(0, 3);
  const remainingCount = itemNames.length - displayNames.length;

  if (displayNames.length === 1) {
    return remainingCount > 0 ? `${displayNames[0]} and ${remainingCount} more` : displayNames[0];
  }

  if (displayNames.length === 2) {
    return remainingCount > 0
      ? `${displayNames[0]}, ${displayNames[1]}, and ${remainingCount} more`
      : `${displayNames[0]} and ${displayNames[1]}`;
  }

  const [first, second, third] = displayNames;

  return remainingCount > 0
    ? `${first}, ${second}, ${third}, and ${remainingCount} more`
    : `${first}, ${second}, and ${third}`;
}

function normalizeRecipientText(value: unknown): string {
  return typeof value === 'string'
    ? value.toLowerCase().replace(/[^a-z0-9]+/g, '')
    : '';
}
