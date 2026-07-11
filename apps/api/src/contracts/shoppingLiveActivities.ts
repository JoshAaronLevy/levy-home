import type { APNsEnvironment } from './notifications.js';
import type { ShoppingTripResident, ShoppingTripSnapshot } from './shoppingTrips.js';

export type ShoppingLiveActivityTokenType = 'push_to_start' | 'activity_update';
export type ShoppingLiveActivityDeliveryEvent = 'start' | 'update' | 'end';
export type ShoppingLiveActivityDeliveryStatus = 'pending' | 'sending' | 'sent' | 'failed' | 'ambiguous';

export type ShoppingLiveActivityRegistrationRequest = {
  pushDeviceId: string;
  resident: ShoppingTripResident;
  environment: APNsEnvironment;
  tokenType: ShoppingLiveActivityTokenType;
  token: string;
  tripId?: string;
};

export type ShoppingLiveActivityRegistration = {
  id: string;
  pushDeviceId: string;
  resident: ShoppingTripResident;
  environment: APNsEnvironment;
  tokenType: ShoppingLiveActivityTokenType;
  tripId: string | null;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
};

export type ShoppingLiveActivityRegistrationResponse = {
  ok: true;
  registration: ShoppingLiveActivityRegistration;
  generatedAt: string;
};

export type ShoppingLiveActivityContentState = {
  status: string;
  pickedUpCount: number;
  remainingCount: number;
  totalItemCount: number;
  estimatedTotalCents: number;
  pricedPickedItemCount: number;
  unpricedPickedItemCount: number;
  currencyCode: string;
  stateVersion: number;
  updatedAtEpochSeconds: number;
};

export type ShoppingLiveActivityAttributes = {
  tripID: string;
  startedByName: string;
  startedAtEpochSeconds: number;
};

export type ShoppingLiveActivityPayload = {
  aps: {
    timestamp: number;
    event: ShoppingLiveActivityDeliveryEvent;
    'content-state': ShoppingLiveActivityContentState;
    'attributes-type'?: 'ShoppingTripActivityAttributes';
    attributes?: ShoppingLiveActivityAttributes;
    'input-push-token'?: 1;
    'dismissal-date'?: number;
    alert?: { title: string; body: string };
  };
};

export type ShoppingLiveActivityDelivery = {
  id: string;
  tripId: string;
  registrationId: string;
  eventType: ShoppingLiveActivityDeliveryEvent;
  stateVersion: number;
  status: ShoppingLiveActivityDeliveryStatus;
  attemptCount: number;
  apnsId: string | null;
  lastErrorReason: string | null;
  createdAt: string;
  sentAt: string | null;
};

export type ShoppingLiveActivityDebugDeliveryResponse = {
  ok: true;
  trip: ShoppingTripSnapshot;
  queuedDeliveryCount: number;
  deliveryIds: string[];
  generatedAt: string;
};
