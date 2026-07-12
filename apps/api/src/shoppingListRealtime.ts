import crypto from 'node:crypto';
import type { IncomingMessage } from 'node:http';
import type { Duplex } from 'node:stream';
import { WebSocket, WebSocketServer, type RawData } from 'ws';

import type {
  EventPushStatus,
  ShoppingCategory,
  ShoppingListItem,
  ShoppingStore,
  ShoppingTripSnapshot,
} from './contracts.js';
import { logger } from './observability/logger.js';
import type {
  ListMutationPushAction,
  ListSessionPushPayload,
  NotificationService,
} from './services/notifications/notificationService.js';

export const SHOPPING_LIST_LIVE_PATH = '/api/shopping-list/live';

const HEARTBEAT_INTERVAL_MS = 30_000;
const PRESENCE_TIMEOUT_MS = 75_000;

export type ShoppingListClientLiveMessage =
  | {
      type: 'subscribe';
      viewerId: string;
      displayName: string;
      deviceName?: string;
    }
  | {
      type: 'presence_ping';
      viewerId: string;
    };

export type ShoppingListViewerPresence = {
  viewerId: string;
  displayName: string;
  connectionId: string;
  deviceName?: string;
  lastSeenAt: string;
};

export type ShoppingListLiveMessage =
  | {
      type: 'hello';
      connectionId: string;
      serverTime: string;
    }
  | {
      type: 'presence_changed';
      viewers: ShoppingListViewerPresence[];
      serverTime: string;
    }
  | {
      type: 'snapshot_required';
      reason: 'connected' | 'missed_messages' | 'server_restart';
      serverTime: string;
    }
  | {
      type: 'item_created';
      item: ShoppingListItem;
      mutationId: string;
      serverTime: string;
    }
  | {
      type: 'item_updated';
      item: ShoppingListItem;
      mutationId: string;
      serverTime: string;
    }
  | {
      type: 'item_deleted';
      itemId: number;
      mutationId: string;
      serverTime: string;
    }
  | {
      type: 'stores_changed';
      stores: ShoppingStore[];
      mutationId: string;
      serverTime: string;
    }
  | {
      type: 'categories_changed';
      categories: ShoppingCategory[];
      mutationId: string;
      serverTime: string;
    }
  | {
      type: 'trip_started';
      trip: ShoppingTripSnapshot;
      mutationId: string;
      serverTime: string;
    }
  | {
      type: 'trip_updated';
      trip: ShoppingTripSnapshot;
      mutationId: string;
      serverTime: string;
    }
  | {
      type: 'trip_ended';
      trip: ShoppingTripSnapshot;
      mutationId: string;
      serverTime: string;
    };

export type ShoppingListRealtimeBroadcaster = {
  broadcastItemCreated: (item: ShoppingListItem, mutationId: string) => void;
  broadcastItemUpdated: (item: ShoppingListItem, mutationId: string) => void;
  broadcastItemDeleted: (itemId: number, mutationId: string) => void;
  broadcastStoresChanged: (stores: ShoppingStore[], mutationId: string) => void;
  broadcastCategoriesChanged: (categories: ShoppingCategory[], mutationId: string) => void;
  broadcastTripStarted: (trip: ShoppingTripSnapshot, mutationId: string) => void;
  broadcastTripUpdated: (trip: ShoppingTripSnapshot, mutationId: string) => void;
  broadcastTripEnded: (trip: ShoppingTripSnapshot, mutationId: string) => void;
};

export type ShoppingListRealtimeSessionRecorder = {
  recordItemMutation: (
    item: ShoppingListItem,
    mutationId: string,
    action: ListMutationPushAction,
    actor?: string,
  ) => void;
  flushPendingSessionForViewerId: (viewerId: string) => Promise<EventPushStatus | undefined>;
};

export type ShoppingListRealtimeHub = ShoppingListRealtimeBroadcaster & ShoppingListRealtimeSessionRecorder & {
  handleUpgrade: (request: IncomingMessage, socket: Duplex, head: Buffer) => boolean;
  close: () => void;
  connectionCount: () => number;
};

type ClientState = {
  connectionId: string;
  isAlive: boolean;
  presence?: ShoppingListViewerPresence;
};

type PendingShoppingMutation = {
  itemId: number;
  itemName: string;
  mutationId: string;
  action: ListMutationPushAction;
};

type PendingShoppingMutationSession = {
  actor: string;
  items: PendingShoppingMutation[];
};

export function createShoppingListRealtimeHub(options: {
  notificationService?: Pick<NotificationService, 'sendListSessionPush'>;
} = {}): ShoppingListRealtimeHub {
  const server = new WebSocketServer({ noServer: true });
  const clients = new Map<WebSocket, ClientState>();
  const pendingMutationsByViewerId = new Map<string, PendingShoppingMutationSession>();
  let isClosed = false;
  const heartbeat = setInterval(() => {
    expireStalePresence();

    for (const [socket, state] of clients) {
      if (!state.isAlive) {
        socket.terminate();
        continue;
      }

      state.isAlive = false;
      socket.ping();
    }
  }, HEARTBEAT_INTERVAL_MS);

  heartbeat.unref();

  server.on('connection', (socket) => {
    const state: ClientState = {
      connectionId: crypto.randomUUID(),
      isAlive: true,
    };

    clients.set(socket, state);
    logRealtime('websocket_connected', {
      connectionId: state.connectionId,
      connectionCount: clients.size,
    });

    sendMessage(socket, {
      type: 'hello',
      connectionId: state.connectionId,
      serverTime: now(),
    });
    sendMessage(socket, {
      type: 'snapshot_required',
      reason: 'connected',
      serverTime: now(),
    });

    socket.on('pong', () => {
      state.isAlive = true;
    });

    socket.on('error', (error) => {
      logRealtime('websocket_error', {
        connectionId: state.connectionId,
        viewerId: state.presence?.viewerId,
        error: error.message,
      });
      socket.terminate();
    });

    socket.on('message', (data, isBinary) => {
      if (isBinary) {
        return;
      }

      const message = parseClientMessage(data);

      if (!message) {
        return;
      }

      if (message.type === 'subscribe') {
        state.presence = {
          viewerId: normalizeViewerId(message.viewerId),
          displayName: message.displayName,
          connectionId: state.connectionId,
          ...(message.deviceName ? { deviceName: message.deviceName } : {}),
          lastSeenAt: now(),
        };
        broadcastPresenceChanged();
        logRealtime('presence_subscribed', {
          connectionId: state.connectionId,
          viewerId: state.presence.viewerId,
          activeViewerCount: currentViewers().length,
        });
        return;
      }

      if (state.presence?.viewerId === normalizeViewerId(message.viewerId)) {
        state.presence = {
          ...state.presence,
          lastSeenAt: now(),
        };
      }
    });

    socket.on('close', (code) => {
      const hadPresence = state.presence !== undefined;
      const viewerId = state.presence?.viewerId;

      clients.delete(socket);

      if (hadPresence && viewerId) {
        broadcastPresenceChanged();
        void flushIfViewerInactive(viewerId);
        logRealtime('presence_disconnected', {
          connectionId: state.connectionId,
          viewerId,
          activeViewerCount: currentViewers().length,
        });
      }

      logRealtime('websocket_disconnected', {
        connectionId: state.connectionId,
        viewerId,
        connectionCount: clients.size,
        code,
      });
    });
  });

  const hub: ShoppingListRealtimeHub = {
    handleUpgrade(request, socket, head) {
      if (!isShoppingListLiveRequest(request)) {
        return false;
      }

      server.handleUpgrade(request, socket, head, (webSocket) => {
        server.emit('connection', webSocket, request);
      });
      return true;
    },
    close() {
      if (isClosed) {
        return;
      }

      isClosed = true;
      clearInterval(heartbeat);

      for (const socket of clients.keys()) {
        socket.close(1001, 'Server shutting down.');
      }

      clients.clear();
      server.close();
    },
    connectionCount() {
      return clients.size;
    },
    recordItemMutation(item, mutationId, action, actor) {
      const normalizedActor = readActor(actor);
      const viewerId = viewerIdForActor(normalizedActor);

      if (!normalizedActor || !viewerId) {
        logRealtime('shopping_session_push_skipped', {
          reason: 'missing_actor',
          itemId: item.id,
          mutationId,
          action,
        });
        return;
      }

      const session = pendingMutationsByViewerId.get(viewerId) ?? {
        actor: normalizedActor,
        items: [],
      };

      session.actor = normalizedActor;
      session.items.push({
        itemId: item.id,
        itemName: item.name,
        mutationId,
        action,
      });
      pendingMutationsByViewerId.set(viewerId, session);

      logRealtime('shopping_mutation_recorded', {
        viewerId,
        itemId: item.id,
        action,
        pendingItemCount: session.items.length,
      });

    },
    async flushPendingSessionForViewerId(viewerId) {
      const normalizedViewerId = normalizeViewerId(viewerId);
      const session = pendingMutationsByViewerId.get(normalizedViewerId);

      if (!session || session.items.length === 0) {
        return undefined;
      }

      pendingMutationsByViewerId.delete(normalizedViewerId);

      if (!options.notificationService) {
        return undefined;
      }

      try {
        const payload: ListSessionPushPayload = {
          listType: 'shopping',
          actor: session.actor,
          items: session.items.map((item) => ({
            itemName: item.itemName,
            action: item.action,
          })),
        };
        const push = await options.notificationService.sendListSessionPush(payload);

        logRealtime('shopping_session_push_sent', {
          viewerId: normalizedViewerId,
          itemCount: session.items.length,
          attempted: push.attempted,
          skipped: push.skipped,
          sentNotificationCount: push.sentNotificationCount,
          reason: push.reason,
        });

        return push;
      } catch (error) {
        const push: EventPushStatus = {
          attempted: false,
          skipped: true,
          reason: error instanceof Error ? error.message : String(error),
        };

        logRealtime('shopping_session_push_failed', {
          viewerId: normalizedViewerId,
          itemCount: session.items.length,
          reason: push.reason,
        });

        return push;
      }
    },
    broadcastItemCreated(item, mutationId) {
      logRealtime('mutation_broadcast', {
        mutationType: 'item_created',
        itemId: item.id,
        mutationId,
        connectionCount: clients.size,
      });
      broadcast({
        type: 'item_created',
        item,
        mutationId,
        serverTime: now(),
      });
    },
    broadcastItemUpdated(item, mutationId) {
      logRealtime('mutation_broadcast', {
        mutationType: 'item_updated',
        itemId: item.id,
        mutationId,
        connectionCount: clients.size,
      });
      broadcast({
        type: 'item_updated',
        item,
        mutationId,
        serverTime: now(),
      });
    },
    broadcastItemDeleted(itemId, mutationId) {
      logRealtime('mutation_broadcast', {
        mutationType: 'item_deleted',
        itemId,
        mutationId,
        connectionCount: clients.size,
      });
      broadcast({
        type: 'item_deleted',
        itemId,
        mutationId,
        serverTime: now(),
      });
    },
    broadcastStoresChanged(stores, mutationId) {
      broadcast({
        type: 'stores_changed',
        stores,
        mutationId,
        serverTime: now(),
      });
    },
    broadcastCategoriesChanged(categories, mutationId) {
      broadcast({
        type: 'categories_changed',
        categories,
        mutationId,
        serverTime: now(),
      });
    },
    broadcastTripStarted(trip, mutationId) {
      broadcastTripMessage('trip_started', trip, mutationId);
    },
    broadcastTripUpdated(trip, mutationId) {
      broadcastTripMessage('trip_updated', trip, mutationId);
    },
    broadcastTripEnded(trip, mutationId) {
      broadcastTripMessage('trip_ended', trip, mutationId);
    },
  };

  function broadcastTripMessage(
    type: 'trip_started' | 'trip_updated' | 'trip_ended',
    trip: ShoppingTripSnapshot,
    mutationId: string,
  ): void {
    logRealtime('trip_broadcast', {
      mutationType: type,
      tripId: trip.id,
      mutationId,
      version: trip.version,
      connectionCount: clients.size,
    });
    broadcast({ type, trip, mutationId, serverTime: now() });
  }

  function expireStalePresence(): void {
    const cutoff = Date.now() - PRESENCE_TIMEOUT_MS;
    const expiredViewerIds = new Set<string>();
    let didChange = false;

    for (const state of clients.values()) {
      if (!state.presence) {
        continue;
      }

      if (Date.parse(state.presence.lastSeenAt) < cutoff) {
        logRealtime('presence_expired', {
          connectionId: state.connectionId,
          viewerId: state.presence.viewerId,
        });
        expiredViewerIds.add(state.presence.viewerId);
        state.presence = undefined;
        didChange = true;
      }
    }

    if (didChange) {
      broadcastPresenceChanged();
    }

    for (const viewerId of expiredViewerIds) {
      void flushIfViewerInactive(viewerId);
    }
  }

  function broadcastPresenceChanged(): void {
    broadcast({
      type: 'presence_changed',
      viewers: currentViewers(),
      serverTime: now(),
    });
  }

  function currentViewers(): ShoppingListViewerPresence[] {
    const viewersById = new Map<string, ShoppingListViewerPresence>();

    for (const state of clients.values()) {
      if (!state.presence) {
        continue;
      }

      const existingViewer = viewersById.get(state.presence.viewerId);

      if (
        !existingViewer ||
        Date.parse(state.presence.lastSeenAt) > Date.parse(existingViewer.lastSeenAt)
      ) {
        viewersById.set(state.presence.viewerId, state.presence);
      }
    }

    return Array.from(viewersById.values()).sort((left, right) =>
      left.displayName.localeCompare(right.displayName),
    );
  }

  function hasActiveViewer(viewerId: string): boolean {
    const normalizedViewerId = normalizeViewerId(viewerId);

    return Array.from(clients.values()).some((state) => state.presence?.viewerId === normalizedViewerId);
  }

  async function flushIfViewerInactive(viewerId: string): Promise<EventPushStatus | undefined> {
    if (hasActiveViewer(viewerId)) {
      return undefined;
    }

    return hub.flushPendingSessionForViewerId(viewerId);
  }

  function broadcast(message: ShoppingListLiveMessage): void {
    for (const socket of clients.keys()) {
      sendMessage(socket, message);
    }
  }

  return hub;
}

function isShoppingListLiveRequest(request: IncomingMessage): boolean {
  const url = new URL(request.url ?? '/', 'http://localhost');

  return url.pathname === SHOPPING_LIST_LIVE_PATH;
}

function parseClientMessage(data: RawData): ShoppingListClientLiveMessage | undefined {
  const text = rawDataToString(data);

  if (!text) {
    return undefined;
  }

  try {
    const value = JSON.parse(text) as unknown;

    if (!isRecord(value)) {
      return undefined;
    }

    if (value.type === 'subscribe') {
      const viewerId = readNonEmptyString(value.viewerId);
      const displayName = readNonEmptyString(value.displayName);
      const deviceName = readOptionalString(value.deviceName);

      if (!viewerId || !displayName) {
        return undefined;
      }

      return {
        type: 'subscribe',
        viewerId,
        displayName,
        ...(deviceName ? { deviceName } : {}),
      };
    }

    if (value.type === 'presence_ping') {
      const viewerId = readNonEmptyString(value.viewerId);

      return viewerId ? { type: 'presence_ping', viewerId } : undefined;
    }

    return undefined;
  } catch {
    return undefined;
  }
}

function sendMessage(socket: WebSocket, message: ShoppingListLiveMessage): void {
  if (socket.readyState !== WebSocket.OPEN) {
    return;
  }

  try {
    socket.send(JSON.stringify(message));
  } catch {
    socket.terminate();
  }
}

function rawDataToString(data: RawData): string | undefined {
  if (typeof data === 'string') {
    return data;
  }

  if (Buffer.isBuffer(data)) {
    return data.toString('utf8');
  }

  if (Array.isArray(data)) {
    return Buffer.concat(data).toString('utf8');
  }

  if (data instanceof ArrayBuffer) {
    return Buffer.from(data).toString('utf8');
  }

  return undefined;
}

function readNonEmptyString(value: unknown): string | undefined {
  if (typeof value !== 'string') {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function readOptionalString(value: unknown): string | undefined {
  return value === undefined ? undefined : readNonEmptyString(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function readActor(actor: unknown): string | undefined {
  return typeof actor === 'string' && actor.trim().length > 0 ? actor.trim() : undefined;
}

function viewerIdForActor(actor: string | undefined): string | undefined {
  const normalizedActor = normalizeViewerId(actor);

  if (normalizedActor.includes('josh')) {
    return 'josh';
  }

  if (normalizedActor.includes('mallory')) {
    return 'mallory';
  }

  return undefined;
}

function normalizeViewerId(value: unknown): string {
  return typeof value === 'string'
    ? value.toLowerCase().replace(/[^a-z0-9]+/g, '')
    : '';
}

function now(): string {
  return new Date().toISOString();
}

function logRealtime(event: string, details: Record<string, unknown>): void {
  logger.info(`[shopping-list-live] ${event}`, details);
}
