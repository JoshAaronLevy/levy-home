import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createServer } from 'node:http';
import { test } from 'node:test';
import { WebSocket } from 'ws';

import type { ListSessionPushPayload } from '../../src/services/notifications/notificationService.js';
import { createShoppingListRealtimeHub } from '../../src/shoppingListRealtime.js';

test('shopping realtime sends one session summary only after recorded mutations are flushed', async () => {
  const pushes: ListSessionPushPayload[] = [];
  const hub = createShoppingListRealtimeHub({
    notificationService: {
      async sendListSessionPush(payload) {
        pushes.push(payload);

        return {
          attempted: true,
          skipped: false,
          sentNotificationCount: 1,
        };
      },
    },
  });

  const viewOnlyFlush = await hub.flushPendingSessionForViewerId('josh');
  assert.equal(viewOnlyFlush, undefined);
  assert.deepEqual(pushes, []);

  hub.recordItemMutation(shoppingItem(1, 'Whole milk'), 'mutation-1', 'created', 'Josh');
  hub.recordItemMutation(shoppingItem(2, 'Eggs'), 'mutation-2', 'updated', 'Josh');

  const push = await hub.flushPendingSessionForViewerId('josh');

  assert.equal(push?.attempted, true);
  assert.deepEqual(pushes, [
    {
      listType: 'shopping',
      actor: 'Josh',
      items: [
        { itemName: 'Whole milk', action: 'created' },
        { itemName: 'Eggs', action: 'updated' },
      ],
    },
  ]);
  assert.equal(await hub.flushPendingSessionForViewerId('josh'), undefined);

  hub.close();
});

test('shopping realtime flushes a changed viewer session after its final connection closes', async (t) => {
  const pushes: ListSessionPushPayload[] = [];
  const hub = createShoppingListRealtimeHub({
    notificationService: {
      async sendListSessionPush(payload) {
        pushes.push(payload);

        return {
          attempted: true,
          skipped: false,
          sentNotificationCount: 1,
        };
      },
    },
  });
  const server = createServer();
  server.on('upgrade', (request, socket, head) => {
    if (!hub.handleUpgrade(request, socket, head)) {
      socket.destroy();
    }
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  assert.ok(address && typeof address !== 'string');
  const socket = new WebSocket(`ws://127.0.0.1:${address.port}/api/shopping-list/live`);
  t.after(() => {
    socket.terminate();
    hub.close();
    server.close();
  });

  await once(socket, 'open');
  const presenceChanged = waitForMessage(socket, (message) => message.type === 'presence_changed');
  socket.send(JSON.stringify({
    type: 'subscribe',
    viewerId: 'josh',
    displayName: 'Josh',
  }));
  await presenceChanged;

  hub.recordItemMutation(shoppingItem(7, 'Pasta'), 'mutation-7', 'created', 'Josh');
  socket.close();
  await once(socket, 'close');
  await waitForCondition(() => pushes.length === 1);

  assert.deepEqual(pushes, [
    {
      listType: 'shopping',
      actor: 'Josh',
      items: [{ itemName: 'Pasta', action: 'created' }],
    },
  ]);
});

function shoppingItem(id: number, name: string) {
  return {
    id,
    name,
    quantity: 1,
    purchased: false,
    created: '2026-07-11T12:00:00.000Z',
    updated: '2026-07-11T12:00:00.000Z',
    categoryId: null,
    storeListings: [],
  };
}

function waitForMessage(
  socket: WebSocket,
  matches: (message: { type?: unknown }) => boolean,
): Promise<{ type?: unknown }> {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      cleanup();
      reject(new Error('Timed out waiting for a Shopping realtime message.'));
    }, 1_000);

    const onMessage = (data: WebSocket.RawData) => {
      const message = JSON.parse(data.toString()) as { type?: unknown };

      if (matches(message)) {
        cleanup();
        resolve(message);
      }
    };
    const onError = (error: Error) => {
      cleanup();
      reject(error);
    };
    const cleanup = () => {
      clearTimeout(timeout);
      socket.off('message', onMessage);
      socket.off('error', onError);
    };

    socket.on('message', onMessage);
    socket.once('error', onError);
  });
}

async function waitForCondition(condition: () => boolean): Promise<void> {
  const deadline = Date.now() + 1_000;

  while (!condition()) {
    if (Date.now() >= deadline) {
      throw new Error('Timed out waiting for the Shopping session push.');
    }

    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}
