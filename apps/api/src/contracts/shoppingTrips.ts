export type ShoppingTripResident = 'Josh' | 'Mallory';

export type ShoppingTripStatus = 'active' | 'completed';

export type ShoppingTripItemState = 'remaining' | 'picked_up' | 'removed';

export type ShoppingTripSnapshot = {
  id: string;
  status: ShoppingTripStatus;
  startedBy: ShoppingTripResident;
  startedAt: string;
  endedBy: ShoppingTripResident | null;
  endedAt: string | null;
  pickedUpCount: number;
  remainingCount: number;
  totalItemCount: number;
  estimatedTotalCents: number;
  pricedPickedItemCount: number;
  unpricedPickedItemCount: number;
  currencyCode: string;
  version: number;
};

export type ShoppingTripItemSnapshot = {
  id: string;
  tripId: string;
  shoppingItemId: number | null;
  name: string;
  quantity: number;
  estimatedUnitPriceCents: number | null;
  priceSource: string | null;
  storeId: number | null;
  state: ShoppingTripItemState;
  pickedUpBy: ShoppingTripResident | null;
  pickedUpAt: string | null;
  createdAt: string;
  updatedAt: string;
};

export type StartShoppingTripPersistenceRequest = {
  startedBy: ShoppingTripResident;
  mutationId: string;
  currencyCode?: string;
};

export type CompleteShoppingTripPersistenceRequest = {
  tripId: string;
  endedBy: ShoppingTripResident;
  mutationId: string;
  summaryRecipient?: ShoppingTripResident | null;
};

export type ShoppingItemEstimate = {
  estimatedUnitPriceCents: number | null;
  priceSource: string | null;
  storeId: number | null;
};
