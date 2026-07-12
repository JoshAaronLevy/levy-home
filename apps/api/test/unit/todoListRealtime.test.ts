import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createServer } from 'node:http';
import { test } from 'node:test';
import { WebSocket } from 'ws';

import type { ListSessionPushPayload } from '../../src/services/notifications/notificationService.js';
import { createToDoListRealtimeHub } from '../../src/todoListRealtime.js';

test('to-do realtime batches list mutations until the viewer session is flushed', async () => {
  const pushes: ListSessionPushPayload[] = [];
  const hub = createToDoListRealtimeHub({
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

  hub.recordItemMutation(todoItem(1, 'Schedule dentist'), 'mutation-1', 'created', 'Josh');
  hub.recordItemMutation(todoItem(2, 'Book camp'), 'mutation-2', 'completed', 'Josh');

  const push = await hub.flushPendingSessionForViewerId('josh');

  assert.equal(push?.attempted, true);
  assert.deepEqual(pushes, [
    {
      listType: 'todo',
      actor: 'Josh',
      items: [
        { itemName: 'Schedule dentist', action: 'created' },
        { itemName: 'Book camp', action: 'completed' },
      ],
    },
  ]);

  const secondFlush = await hub.flushPendingSessionForViewerId('josh');

  assert.equal(secondFlush, undefined);

  hub.close();
});

test('to-do realtime flushes a changed viewer session after its final connection closes', async (t) => {
  const pushes: ListSessionPushPayload[] = [];
  const hub = createToDoListRealtimeHub({
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
  const socket = new WebSocket(`ws://127.0.0.1:${address.port}/api/todo-list/live`);
  t.after(() => {
    socket.terminate();
    hub.close();
    server.close();
  });

  await once(socket, 'open');
  const presenceChanged = waitForMessage(socket, (message) => message.type === 'presence_changed');
  socket.send(JSON.stringify({
    type: 'subscribe',
    viewerId: 'mallory',
    displayName: 'Mallory',
  }));
  await presenceChanged;

  hub.recordItemMutation(todoItem(8, 'Call plumber'), 'mutation-8', 'updated', 'Mallory');
  socket.close();
  await once(socket, 'close');
  await waitForCondition(() => pushes.length === 1);

  assert.deepEqual(pushes, [
    {
      listType: 'todo',
      actor: 'Mallory',
      items: [{ itemName: 'Call plumber', action: 'updated' }],
    },
  ]);
});

test('to-do realtime sends a snapshot request and broadcasts committed item mutations', async (t) => {
  const hub = createToDoListRealtimeHub();
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
  const socket = new WebSocket(`ws://127.0.0.1:${address.port}/api/todo-list/live`);
  const receivedMessages: Record<string, unknown>[] = [];
  socket.on('message', (data) => {
    receivedMessages.push(JSON.parse(data.toString()) as Record<string, unknown>);
  });
  t.after(() => {
    socket.terminate();
    hub.close();
    server.close();
  });

  await once(socket, 'open');
  await waitForCondition(() => receivedMessages.some((message) => message.type === 'snapshot_required'));
  assert.equal(receivedMessages.find((message) => message.type === 'snapshot_required')?.reason, 'connected');

  const created = todoItem(21, 'Call plumber');
  const createdMessage = waitForMessage(socket, (message) => message.type === 'item_created');
  hub.broadcastItemCreated(created, 'mutation-created');
  const receivedCreated = await createdMessage;
  assert.equal(receivedCreated.type, 'item_created');
  assert.deepEqual(receivedCreated.item, created);
  assert.equal(receivedCreated.mutationId, 'mutation-created');
  assert.equal(typeof receivedCreated.serverTime, 'string');

  const updated = { ...created, status: 'completed' as const };
  const updatedMessage = waitForMessage(socket, (message) => message.type === 'item_updated');
  hub.broadcastItemUpdated(updated, 'mutation-updated');
  const receivedUpdated = await updatedMessage;
  assert.equal(receivedUpdated.type, 'item_updated');
  assert.deepEqual(receivedUpdated.item, updated);
  assert.equal(receivedUpdated.mutationId, 'mutation-updated');

  const deletedMessage = waitForMessage(socket, (message) => message.type === 'item_deleted');
  hub.broadcastItemDeleted(updated.id, 'mutation-deleted');
  const receivedDeleted = await deletedMessage;
  assert.equal(receivedDeleted.type, 'item_deleted');
  assert.equal(receivedDeleted.itemId, updated.id);
  assert.equal(receivedDeleted.mutationId, 'mutation-deleted');
});

function todoItem(id: number, name: string) {
  return {
    id,
    name,
    status: 'open' as const,
    locationIds: [],
    locationDisplayText: 'No location',
    alerts: [],
    subtasks: [],
    createdDate: '2026-07-03T12:00:00.000Z',
  };
}

function waitForMessage(
  socket: WebSocket,
  matches: (message: Record<string, unknown>) => boolean,
): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      cleanup();
      reject(new Error('Timed out waiting for a To Do realtime message.'));
    }, 1_000);

    const onMessage = (data: WebSocket.RawData) => {
      const message = JSON.parse(data.toString()) as Record<string, unknown>;

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
      throw new Error('Timed out waiting for the To Do session push.');
    }

    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}
