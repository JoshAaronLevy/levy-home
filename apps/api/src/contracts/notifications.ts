export type DevicePlatform = 'ios' | 'android' | 'unknown';
export type PushProvider = 'apns' | 'expo';
export type APNsEnvironment = 'sandbox' | 'production';

export type RegisteredDevice = {
  id: string;
  token: string;
  platform: DevicePlatform;
  provider: PushProvider;
  environment?: APNsEnvironment;
  appVersion?: string;
  deviceName?: string;
  registeredAt: string;
  lastSeenAt: string;
};

export type TestPushPayload = {
  title: string;
  body: string;
};

export type APNsSendRequest = {
  device: RegisteredDevice;
  title: string;
  body: string;
  data?: Record<string, string>;
};

export type APNsSendResult = {
  provider: 'apns';
  deviceId: string;
  success: boolean;
  statusCode?: number;
  apnsId?: string;
  reason?: string;
  isInvalidToken: boolean;
};

export type PushSendSummary = {
  provider: 'apns';
  registeredDeviceCount: number;
  eligibleDeviceCount: number;
  sentNotificationCount: number;
  failedNotificationCount: number;
  invalidTokenCount: number;
  skippedDeviceCount: number;
  configurationError?: string;
  results: APNsSendResult[];
};

export type RegisterDeviceRequest = {
  token: string;
  platform: DevicePlatform;
  provider: PushProvider;
  environment?: APNsEnvironment;
  appVersion?: string;
  deviceName?: string;
};

export type NotificationPreferenceCategory =
  | 'garage_opened'
  | 'garage_closed'
  | 'garage_left_open'
  | 'garage_after_hours'
  | 'garage_still_open_at_10pm'
  | 'partner_presence'
  | 'lighting_automation'
  | 'shopping_list'
  | 'todo_list';

export type NotificationPreference = {
  category: NotificationPreferenceCategory;
  isEnabled: boolean;
  title: string;
  detail: string;
};

export type NotificationPreferenceUpdate = {
  category: NotificationPreferenceCategory;
  isEnabled: boolean;
};

export type DevicePreferenceLocator =
  | { deviceId: string }
  | {
      token: string;
      provider: PushProvider;
      environment?: APNsEnvironment;
    };

export type NotificationPreferencesUpdateRequest = {
  preferences: NotificationPreferenceUpdate[];
  locator: DevicePreferenceLocator;
};

export const DEFAULT_NOTIFICATION_PREFERENCES: NotificationPreference[] = [
  {
    category: 'garage_opened',
    isEnabled: true,
    title: 'Garage opened',
    detail: 'Notify when the garage opens.',
  },
  {
    category: 'garage_closed',
    isEnabled: true,
    title: 'Garage closed',
    detail: 'Notify when the garage closes.',
  },
  {
    category: 'garage_left_open',
    isEnabled: true,
    title: 'Garage left open',
    detail: 'Notify when the garage has been open for a while.',
  },
  {
    category: 'garage_after_hours',
    isEnabled: true,
    title: 'Garage after-hours',
    detail: 'Notify when the garage opens late at night.',
  },
  {
    category: 'garage_still_open_at_10pm',
    isEnabled: true,
    title: 'Garage still open at 10 PM',
    detail: 'Notify at bedtime if the garage is still open.',
  },
  {
    category: 'partner_presence',
    isEnabled: true,
    title: 'Partner presence',
    detail: 'Notify when your partner leaves or arrives home.',
  },
  {
    category: 'lighting_automation',
    isEnabled: true,
    title: 'Lighting automations',
    detail: 'Notify when selected lighting automations finish.',
  },
  {
    category: 'shopping_list',
    isEnabled: true,
    title: 'Shopping list',
    detail: 'Notify when someone else updates the shopping list.',
  },
  {
    category: 'todo_list',
    isEnabled: true,
    title: 'To-do list',
    detail: 'Notify when someone else updates the to-do list.',
  },
];

const notificationPreferenceCategorySet = new Set<string>(
  DEFAULT_NOTIFICATION_PREFERENCES.map((preference) => preference.category),
);

export function isNotificationPreferenceCategory(value: unknown): value is NotificationPreferenceCategory {
  return typeof value === 'string' && notificationPreferenceCategorySet.has(value);
}
