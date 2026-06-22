import crypto from 'node:crypto';
import type { IncomingMessage } from 'node:http';
import type { Duplex } from 'node:stream';
import { WebSocket, WebSocketServer, type RawData } from 'ws';

import type { ShoppingCategory, ShoppingListItem, ShoppingStore } from './contracts.js';

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
    };

export type ShoppingListRealtimeBroadcaster = {
  broadcastItemCreated: (item: ShoppingListItem, mutationId: string) => void;
  broadcastItemUpdated: (item: ShoppingListItem, mutationId: string) => void;
  broadcastItemDeleted: (itemId: number, mutationId: string) => void;
  broadcastStoresChanged: (stores: ShoppingStore[], mutationId: string) => void;
  broadcastCategoriesChanged: (categories: ShoppingCategory[], mutationId: string) => void;
};

export type ShoppingListRealtimeHub = ShoppingListRealtimeBroadcaster & {
  handleUpgrade: (request: IncomingMessage, socket: Duplex, head: Buffer) => boolean;
  close: () => void;
  connectionCount: () => number;
};

type ClientState = {
  connectionId: string;
  isAlive: boolean;
  presence?: ShoppingListViewerPresence;
};

export function createShoppingListRealtimeHub(): ShoppingListRealtimeHub {
  const server = new WebSocketServer({ noServer: true });
  const clients = new Map<WebSocket, ClientState>();
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

    socket.on('error', () => {
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
          viewerId: message.viewerId,
          displayName: message.displayName,
          connectionId: state.connectionId,
          ...(message.deviceName ? { deviceName: message.deviceName } : {}),
          lastSeenAt: now(),
        };
        broadcastPresenceChanged();
        return;
      }

      if (state.presence?.viewerId === message.viewerId) {
        state.presence = {
          ...state.presence,
          lastSeenAt: now(),
        };
      }
    });

    socket.on('close', () => {
      const hadPresence = state.presence !== undefined;

      clients.delete(socket);

      if (hadPresence) {
        broadcastPresenceChanged();
      }
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
    broadcastItemCreated(item, mutationId) {
      broadcast({
        type: 'item_created',
        item,
        mutationId,
        serverTime: now(),
      });
    },
    broadcastItemUpdated(item, mutationId) {
      broadcast({
        type: 'item_updated',
        item,
        mutationId,
        serverTime: now(),
      });
    },
    broadcastItemDeleted(itemId, mutationId) {
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
  };

  function expireStalePresence(): void {
    const cutoff = Date.now() - PRESENCE_TIMEOUT_MS;
    let didChange = false;

    for (const state of clients.values()) {
      if (!state.presence) {
        continue;
      }

      if (Date.parse(state.presence.lastSeenAt) < cutoff) {
        state.presence = undefined;
        didChange = true;
      }
    }

    if (didChange) {
      broadcastPresenceChanged();
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

function now(): string {
  return new Date().toISOString();
}
