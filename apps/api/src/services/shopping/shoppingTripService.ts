import type {
  CompleteShoppingTripPersistenceRequest,
  ShoppingTripMutationResponse,
  ShoppingTripSnapshot,
  StartShoppingTripPersistenceRequest,
} from '../../contracts.js';
import { HTTPError } from '../../http/errors.js';
import {
  ShoppingTripHasNoNeededItemsError,
  type ShoppingTripStore,
} from '../../repositories/shoppingTripRepository.js';
import type { ShoppingListRealtimeBroadcaster } from '../../shoppingListRealtime.js';

export type ShoppingTripService = {
  getActiveTrip: () => Promise<ShoppingTripSnapshot | null>;
  startTrip: (request: StartShoppingTripPersistenceRequest) => Promise<ShoppingTripMutationResponse>;
  endTrip: (request: CompleteShoppingTripPersistenceRequest) => Promise<ShoppingTripMutationResponse>;
};

export function createShoppingTripService(options: {
  shoppingListRealtime?: ShoppingListRealtimeBroadcaster;
  shoppingTripStore: ShoppingTripStore;
}): ShoppingTripService {
  const { shoppingListRealtime, shoppingTripStore } = options;

  return {
    async getActiveTrip() {
      return shoppingTripStore.fetchActiveTrip();
    },
    async startTrip(request) {
      const replay = await shoppingTripStore.fetchTripByStartMutationId(request.mutationId);

      if (replay) {
        return tripMutationResponse(replay, request.mutationId, replay.status === 'active' ? replay : null);
      }

      const activeTrip = await shoppingTripStore.fetchActiveTrip();

      if (activeTrip) {
        return tripMutationResponse(activeTrip, request.mutationId, activeTrip);
      }

      try {
        const trip = await shoppingTripStore.startTrip(request);
        shoppingListRealtime?.broadcastTripStarted(trip, request.mutationId);
        return tripMutationResponse(trip, request.mutationId, trip);
      } catch (error) {
        if (error instanceof ShoppingTripHasNoNeededItemsError) {
          throw new HTTPError(409, error.message, 'shopping_trip_has_no_needed_items');
        }

        if (isDatabaseUniqueViolation(error)) {
          const sameMutationTrip = await shoppingTripStore.fetchTripByStartMutationId(request.mutationId);

          if (sameMutationTrip) {
            return tripMutationResponse(
              sameMutationTrip,
              request.mutationId,
              sameMutationTrip.status === 'active' ? sameMutationTrip : null,
            );
          }

          const concurrentlyStartedTrip = await shoppingTripStore.fetchActiveTrip();

          if (concurrentlyStartedTrip) {
            return tripMutationResponse(concurrentlyStartedTrip, request.mutationId, concurrentlyStartedTrip);
          }
        }

        throw error;
      }
    },
    async endTrip(request) {
      const replay = await shoppingTripStore.fetchTripByEndMutationId(request.mutationId);

      if (replay) {
        return tripMutationResponse(replay, request.mutationId, replay.status === 'active' ? replay : null);
      }

      const requestedTrip = await shoppingTripStore.fetchTrip(request.tripId);

      if (!requestedTrip) {
        throw new HTTPError(404, 'Shopping trip was not found.', 'shopping_trip_not_found');
      }

      if (requestedTrip.status !== 'active') {
        throw new HTTPError(409, 'Shopping trip is no longer active.', 'shopping_trip_not_active');
      }

      const completedTrip = await shoppingTripStore.completeTrip(request);

      if (completedTrip) {
        shoppingListRealtime?.broadcastTripEnded(completedTrip, request.mutationId);
        return tripMutationResponse(completedTrip, request.mutationId, null);
      }

      const concurrentReplay = await shoppingTripStore.fetchTripByEndMutationId(request.mutationId);

      if (concurrentReplay) {
        return tripMutationResponse(concurrentReplay, request.mutationId, null);
      }

      const currentTrip = await shoppingTripStore.fetchTrip(request.tripId);

      if (!currentTrip) {
        throw new HTTPError(404, 'Shopping trip was not found.', 'shopping_trip_not_found');
      }

      throw new HTTPError(409, 'Shopping trip is no longer active.', 'shopping_trip_not_active');
    },
  };
}

function tripMutationResponse(
  trip: ShoppingTripSnapshot,
  mutationId: string,
  activeTrip: ShoppingTripSnapshot | null,
): ShoppingTripMutationResponse {
  return {
    ok: true,
    trip,
    activeTrip,
    mutationId,
    generatedAt: new Date().toISOString(),
  };
}

function isDatabaseUniqueViolation(error: unknown): boolean {
  return typeof error === 'object' && error !== null && (error as { code?: unknown }).code === '23505';
}
