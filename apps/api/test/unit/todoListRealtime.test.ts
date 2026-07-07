import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { ListSessionPushPayload } from '../../src/services/notifications/notificationService.js';
import { createToDoListRealtimeHub } from '../../src/todoListRealtime.js';

test('to-do realtime batches created items until the viewer session is flushed', async () => {
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

  hub.recordItemCreated(todoItem(1, 'Schedule dentist'), 'mutation-1', 'Josh');
  hub.recordItemCreated(todoItem(2, 'Book camp'), 'mutation-2', 'Josh');

  const push = await hub.flushPendingSessionForViewerId('josh');

  assert.equal(push?.attempted, true);
  assert.deepEqual(pushes, [
    {
      listType: 'todo',
      action: 'created',
      actor: 'Josh',
      itemNames: ['Schedule dentist', 'Book camp'],
    },
  ]);

  const secondFlush = await hub.flushPendingSessionForViewerId('josh');

  assert.equal(secondFlush, undefined);

  hub.close();
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
