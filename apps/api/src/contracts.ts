export const LEVY_HOME_EVENT_TYPES = [
  'garage_opened',
  'garage_closed',
  'garage_left_open_10_min',
  'garage_opened_after_hours',
  'garage_still_open_at_10pm',
  'doorbell_pressed',
  'doorbell_person_detected',
  'doorbell_motion_detected',
  'phone_state_changed',
] as const;

export type LevyHomeEventType = (typeof LEVY_HOME_EVENT_TYPES)[number];

export type DisplaySeverity = 'info' | 'warning' | 'critical';
export type HomeAssistantEventCategory = 'garage' | 'doorbell' | 'phone';
export type HomeAssistantEventSeverity = 'normal' | 'high';

export type HomeAssistantEntityDiscoveryCandidate = {
  entityId: string;
  domain: string;
  friendlyName?: string;
  stateSummary: string;
  lastChangedAt?: string;
  lastUpdatedAt?: string;
  matchedTerms: string[];
};

export type EventDisplayMetadata = {
  title: string;
  body: string;
  severity: DisplaySeverity;
};

export type HomeAssistantEventPayload = {
  type: LevyHomeEventType;
  entityId: string;
  category?: HomeAssistantEventCategory;
  severity?: HomeAssistantEventSeverity;
  source?: string;
  occurredAt?: string;
  title?: string;
  message?: string;
  metadata?: Record<string, unknown>;
};

export type EventPushStatus = {
  attempted: boolean;
  skipped: boolean;
  reason?: string;
  ticketCount?: number;
  sentNotificationCount?: number;
  failedNotificationCount?: number;
  invalidTokenCount?: number;
};

export type LevyHomeEvent = HomeAssistantEventPayload & {
  id: string;
  receivedAt: string;
  display: EventDisplayMetadata;
  push?: EventPushStatus;
};

export type GarageState = 'open' | 'closed' | 'opening' | 'closing' | 'unknown';
export type LightState = 'off' | 'on' | 'partially_on' | 'unknown';
export type PresenceState = 'home' | 'away' | 'unknown';

export type GarageStatus = {
  state: GarageState;
  displayName?: string;
  lastUpdatedAt?: string;
  isStale?: boolean;
};

export type PersonPresenceStatus = {
  person: string;
  state: PresenceState;
  entityId: string;
  deviceName?: string;
  lastUpdatedAt?: string;
  isStale?: boolean;
};

export type LightGroupStatus = {
  id: string;
  name: string;
  state: LightState;
  lightsOnCount?: number;
  totalLightCount?: number;
};

export type LightSummary = {
  state: LightState;
  lightsOnCount?: number;
  totalLightCount?: number;
  groups: LightGroupStatus[];
};

export type HomeOverview = {
  garageStatus: GarageStatus;
  lightSummary: LightSummary;
  presence: PersonPresenceStatus[];
  recentImportantEvent: LevyHomeEvent | null;
  generatedAt: string;
  isPartial: boolean;
};

export type QuickActionId = 'open_garage' | 'close_garage' | 'turn_off_all_lights' | 'turn_off_light_group';

export type QuickAction = {
  id: QuickActionId;
  title: string;
  subtitle?: string;
  isEnabled: boolean;
  requiresConfirmation: boolean;
  targetName?: string;
};

export type QuickActionResult = {
  actionId: QuickActionId;
  status: 'success' | 'failure';
  message: string;
  refreshedHomeOverview: HomeOverview | null;
};

export type LevyHomeUser = {
  id: number;
  firstName: string;
  lastName: string;
  email: string;
  mobileDevice?: string;
  lastLogin?: string;
};

export type UsersResponse = {
  ok: true;
  users: LevyHomeUser[];
  generatedAt: string;
};

export type ToDoLocation = {
  id: number;
  name: string;
  address?: string;
  mapkitTitle?: string;
  mapkitSubtitle?: string;
  latitude?: number;
  longitude?: number;
  createdBy?: number;
  createdDate: string;
  lastUsedDate?: string;
  useCount: number;
  isActive: boolean;
  favoritedBy: number[];
};

export type ToDoLocationsResponse = {
  ok: true;
  locations: ToDoLocation[];
  generatedAt: string;
};

export type CreateToDoLocationRequest = {
  name: string;
  address?: string | null;
  mapkitTitle?: string | null;
  mapkitSubtitle?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  createdBy?: number | null;
  favoritedBy?: number[];
};

export type ToDoLocationMutationResponse = {
  ok: true;
  location: ToDoLocation;
  generatedAt: string;
};

export type ShoppingListItem = {
  id: number;
  name: string;
  brand?: string;
  quantity: number;
  notes?: string;
  purchased: boolean;
  created?: string;
  updated?: string;
  version?: number;
  categoryId: number | null;
  image?: string;
  storeListings: ShoppingItemStoreListing[];
};

export type ShoppingItemStoreListingProduct = {
  productId?: string;
  upc?: string;
  productPageURI?: string;
  brand?: string;
  name?: string;
  description?: string;
  image?: string;
};

export type ShoppingItemStoreListingAisle = {
  display?: string;
  description?: string;
  number?: string;
  shelfNumber?: string;
  raw?: Record<string, unknown>;
};

export type ShoppingItemStoreListingPrice = {
  regular?: number;
  promo?: number;
};

export type ShoppingItemStoreListingAvailability = {
  status?: string;
  checkedAt?: string;
};

export type ShoppingItemStoreListing = {
  storeId?: number;
  storeName?: string;
  source?: string;
  krogerLocationId?: string;
  product?: ShoppingItemStoreListingProduct;
  aisle?: ShoppingItemStoreListingAisle;
  price?: ShoppingItemStoreListingPrice;
  inventory?: Record<string, unknown>;
  fulfillment?: Record<string, unknown>;
  availability?: ShoppingItemStoreListingAvailability;
  checkedAt?: string;
};

export type ShoppingStore = {
  id: number;
  name: string;
  logo?: string;
};

export type ShoppingCategory = {
  id: number;
  name: string;
};

export type ShoppingListData = {
  items: ShoppingListItem[];
  stores: ShoppingStore[];
  categories: ShoppingCategory[];
};

export type CreateShoppingListItemRequest = {
  name: string;
  brand?: string | null;
  quantity?: number;
  notes?: string | null;
  purchased?: boolean;
  categoryId?: number | null;
  image?: string | null;
  storeListings?: ShoppingItemStoreListing[];
  mutationId?: string;
};

export type UpdateShoppingListItemRequest = {
  name?: string;
  brand?: string | null;
  quantity?: number;
  notes?: string | null;
  purchased?: boolean;
  categoryId?: number | null;
  image?: string | null;
  storeListings?: ShoppingItemStoreListing[];
  mutationId?: string;
};

export type ShoppingListItemLookupResponse = {
  ok: true;
  query: string;
  match: ShoppingListItem | null;
};

export type KrogerProductSearchResponse = {
  ok: boolean;
  query: string;
  generatedAt: string;
  productStatusCode?: number;
  products: KrogerProductSearchResult[];
  error?: string;
};

export type KrogerProductSearchResult = {
  productId: string | null;
  upc: string | null;
  productPageURI: string | null;
  aisles: unknown[];
  brand: string | null;
  name: string | null;
  description: string | null;
  image: string | null;
  storeListings: ShoppingItemStoreListing[];
};

export type ShoppingListMutationResponse = {
  ok: true;
  item: ShoppingListItem;
  mutationId: string;
  generatedAt: string;
};

export type DeleteShoppingListItemResponse = {
  ok: true;
  itemId: number;
  item: ShoppingListItem;
  mutationId: string;
  generatedAt: string;
};

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
  | 'garage_still_open_at_10pm';

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

export const GARAGE_NOTIFICATION_PREFERENCES: NotificationPreference[] = [
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
];

export const EVENT_DISPLAY_METADATA: Record<LevyHomeEventType, EventDisplayMetadata> = {
  garage_opened: {
    title: 'Garage opened',
    body: 'The garage door opened.',
    severity: 'info',
  },
  garage_closed: {
    title: 'Garage closed',
    body: 'The garage door closed.',
    severity: 'info',
  },
  garage_left_open_10_min: {
    title: 'Garage left open',
    body: 'The garage has been open for 10 minutes.',
    severity: 'warning',
  },
  garage_opened_after_hours: {
    title: 'Garage opened after hours',
    body: 'The garage opened between 10 PM and 7 AM.',
    severity: 'warning',
  },
  garage_still_open_at_10pm: {
    title: 'Garage still open',
    body: 'The garage is still open at 10 PM.',
    severity: 'critical',
  },
  doorbell_pressed: {
    title: 'Doorbell pressed',
    body: 'Someone pressed the doorbell.',
    severity: 'info',
  },
  doorbell_person_detected: {
    title: 'Person detected',
    body: 'The doorbell detected a person.',
    severity: 'warning',
  },
  doorbell_motion_detected: {
    title: 'Motion detected',
    body: 'The doorbell detected motion.',
    severity: 'info',
  },
  phone_state_changed: {
    title: 'Phone changed',
    body: 'A tracked phone entity changed state.',
    severity: 'info',
  },
};

const eventTypeSet = new Set<string>(LEVY_HOME_EVENT_TYPES);
const garageNotificationPreferenceCategorySet = new Set<string>(
  GARAGE_NOTIFICATION_PREFERENCES.map((preference) => preference.category),
);

export function isLevyHomeEventType(value: unknown): value is LevyHomeEventType {
  return typeof value === 'string' && eventTypeSet.has(value);
}

export function getEventDisplayMetadata(type: LevyHomeEventType): EventDisplayMetadata {
  return EVENT_DISPLAY_METADATA[type];
}

export function buildEventDedupeKey(event: Pick<HomeAssistantEventPayload, 'type' | 'entityId'>): string {
  return `${event.type}:${event.entityId}`;
}

export function isNotificationPreferenceCategory(value: unknown): value is NotificationPreferenceCategory {
  return typeof value === 'string' && garageNotificationPreferenceCategorySet.has(value);
}
