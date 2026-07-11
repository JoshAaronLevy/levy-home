import type {
  CompleteShoppingTripPersistenceRequest,
  ClaimShoppingTripDisplayRequest,
  ShoppingTripDisplayDisposition,
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
import type { ShoppingLiveActivityDeliveryService } from './shoppingLiveActivityDeliveryService.js';
import type { ShoppingTripSummaryDeliveryService } from './shoppingTripSummaryDeliveryService.js';

export type ShoppingTripService = {
  getActiveTrip: () => Promise<ShoppingTripSnapshot | null>;
  startTrip: (request: StartShoppingTripPersistenceRequest) => Promise<ShoppingTripMutationResponse>;
  claimTripDisplay: (request: ClaimShoppingTripDisplayRequest) => Promise<ShoppingTripDisplayDisposition | null>;
  endTrip: (request: CompleteShoppingTripPersistenceRequest) => Promise<ShoppingTripMutationResponse>;
};

export function createShoppingTripService(options: {
  shoppingListRealtime?: ShoppingListRealtimeBroadcaster;
  shoppingLiveActivityDeliveryService?: Pick<ShoppingLiveActivityDeliveryService, 'enqueueEvent'>;
  shoppingTripSummaryDeliveryService?: Pick<ShoppingTripSummaryDeliveryService, 'processPending'>;
  shoppingTripStore: ShoppingTripStore;
}): ShoppingTripService {
  const {
    shoppingListRealtime,
    shoppingLiveActivityDeliveryService,
    shoppingTripSummaryDeliveryService,
    shoppingTripStore,
  } = options;
  const displayForStartRequest = async (
    trip: ShoppingTripSnapshot,
    request: StartShoppingTripPersistenceRequest,
  ): Promise<ShoppingTripDisplayDisposition | undefined> => {
    if (!request.originatingPushDeviceId) {
      return undefined;
    }
    return (await shoppingTripStore.claimDisplay({
      tripId: trip.id,
      resident: request.startedBy,
      pushDeviceId: request.originatingPushDeviceId,
    })) ?? undefined;
  };

  return {
    async getActiveTrip() {
      return shoppingTripStore.fetchActiveTrip();
    },
    async startTrip(request) {
      const replay = await shoppingTripStore.fetchTripByStartMutationId(request.mutationId);

      if (replay) {
        return tripMutationResponse(
          replay,
          request.mutationId,
          replay.status === 'active' ? replay : null,
          await displayForStartRequest(replay, request),
        );
      }

      const activeTrip = await shoppingTripStore.fetchActiveTrip();

      if (activeTrip) {
        return tripMutationResponse(
          activeTrip,
          request.mutationId,
          activeTrip,
          await displayForStartRequest(activeTrip, request),
        );
      }

      try {
        const startResult = request.originatingPushDeviceId
          ? await shoppingTripStore.startTripWithDisplay({
            ...request,
            originatingPushDeviceId: request.originatingPushDeviceId,
          })
          : { trip: await shoppingTripStore.startTrip(request), displayDisposition: undefined };
        const trip = startResult.trip;
        shoppingListRealtime?.broadcastTripStarted(trip, request.mutationId);
        if (startResult.displayDisposition?.remoteStartCount) {
          await shoppingLiveActivityDeliveryService?.enqueueEvent({
            event: 'start',
            trip,
            excludeResident: request.startedBy,
          });
        }
        return tripMutationResponse(trip, request.mutationId, trip, startResult.displayDisposition);
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
              await displayForStartRequest(sameMutationTrip, request),
            );
          }

          const concurrentlyStartedTrip = await shoppingTripStore.fetchActiveTrip();

          if (concurrentlyStartedTrip) {
            return tripMutationResponse(
              concurrentlyStartedTrip,
              request.mutationId,
              concurrentlyStartedTrip,
              await displayForStartRequest(concurrentlyStartedTrip, request),
            );
          }
        }

        throw error;
      }
    },
    async claimTripDisplay(request) {
      return shoppingTripStore.claimDisplay(request);
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
        await shoppingLiveActivityDeliveryService?.enqueueEvent({ event: 'end', trip: completedTrip });
        void shoppingTripSummaryDeliveryService?.processPending();
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
  displayDisposition?: ShoppingTripDisplayDisposition,
): ShoppingTripMutationResponse {
  return {
    ok: true,
    trip,
    activeTrip,
    mutationId,
    ...(displayDisposition ? { displayDisposition } : {}),
    generatedAt: new Date().toISOString(),
  };
}

function isDatabaseUniqueViolation(error: unknown): boolean {
  return typeof error === 'object' && error !== null && (error as { code?: unknown }).code === '23505';
}
