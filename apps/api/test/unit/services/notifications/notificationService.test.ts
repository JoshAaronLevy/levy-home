import assert from 'node:assert/strict';
import { test } from 'node:test';

import { createInMemoryDeviceRegistry } from '../../../../src/services/notifications/deviceRegistry.js';
import { createInMemoryNotificationPreferenceStore } from '../../../../src/services/notifications/notificationPreferenceStore.js';
import {
  createNotificationService,
  doorbellPushExpirationSeconds,
} from '../../../../src/services/notifications/notificationService.js';
import { FakePushSender } from '../../../support/fakePushSender.js';

test('notification service honors per-device garage preferences for event pushes', async () => {
  const deviceRegistry = createInMemoryDeviceRegistry();
  const notificationPreferenceStore = createInMemoryNotificationPreferenceStore(deviceRegistry);
  const pushSender = new FakePushSender();
  const notificationService = createNotificationService({
    deviceRegistry,
    notificationPreferenceStore,
    pushSender,
  });

  await deviceRegistry.registerDevice({
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
  });
  await notificationPreferenceStore.updatePreferences({
    locator: {
      token: 'sample-apns-token',
      provider: 'apns',
      environment: 'sandbox',
    },
    preferences: [{ category: 'garage_opened', isEnabled: false }],
  });

  const disabledPush = await notificationService.sendEventPush({
    type: 'garage_opened',
    entityId: 'cover.test_garage',
    category: 'garage',
    severity: 'normal',
    source: 'home_assistant',
  });
  const enabledPush = await notificationService.sendEventPush({
    type: 'garage_closed',
    entityId: 'cover.test_garage',
    category: 'garage',
    severity: 'normal',
    source: 'home_assistant',
  });

  assert.equal(disabledPush.attempted, false);
  assert.equal(disabledPush.skipped, true);
  assert.equal(disabledPush.reason, 'All registered APNs devices have this notification disabled.');
  assert.equal(enabledPush.attempted, true);
  assert.equal(enabledPush.sentNotificationCount, 1);
  assert.equal(pushSender.requests.length, 1);
  assert.equal(pushSender.requests[0].title, 'Garage closed');
});

test('notification service sends partner presence event pushes through partner preference', async () => {
  const deviceRegistry = createInMemoryDeviceRegistry();
  const notificationPreferenceStore = createInMemoryNotificationPreferenceStore(deviceRegistry);
  const pushSender = new FakePushSender();
  const notificationService = createNotificationService({
    deviceRegistry,
    notificationPreferenceStore,
    pushSender,
  });

  await deviceRegistry.registerDevice({
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
  });

  const push = await notificationService.sendEventPush({
    type: 'partner_left_home',
    entityId: 'device_tracker.mallorys_iphone',
    category: 'presence',
    severity: 'normal',
    source: 'home_assistant',
    title: 'Mallory left home',
    message: 'Mallory left home.',
  });

  assert.equal(push.attempted, true);
  assert.equal(push.sentNotificationCount, 1);
  assert.equal(pushSender.requests.length, 1);
  assert.equal(pushSender.requests[0].title, 'Mallory left home');
  assert.equal(pushSender.requests[0].body, 'Mallory left home.');
  assert.deepEqual(pushSender.requests[0].data, { category: 'partner_presence' });
});

test('notification service sends doorbell event pushes through the doorbell preference', async () => {
  const deviceRegistry = createInMemoryDeviceRegistry();
  const notificationPreferenceStore = createInMemoryNotificationPreferenceStore(deviceRegistry);
  const pushSender = new FakePushSender();
  const notificationService = createNotificationService({
    deviceRegistry,
    notificationPreferenceStore,
    pushSender,
  });

  await deviceRegistry.registerDevice({
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
  });

  const beforeSend = Math.floor(Date.now() / 1_000);
  const push = await notificationService.sendEventPush({
    type: 'doorbell_person_detected',
    entityId: 'binary_sensor.doorbell_person_detected',
    category: 'doorbell',
    severity: 'high',
    source: 'home_assistant',
  });

  assert.equal(push.attempted, true);
  assert.equal(push.sentNotificationCount, 1);
  assert.equal(pushSender.requests.length, 1);
  const request = pushSender.requests[0];
  assert.ok(request);
  assert.equal(request.title, 'Person detected');
  assert.deepEqual(request.data, { category: 'doorbell' });
  assert.equal(request.collapseId, 'doorbell-current');
  assert.ok(request.expiration !== undefined);
  assert.ok(request.expiration >= beforeSend + doorbellPushExpirationSeconds);
  assert.ok(request.expiration <= Math.floor(Date.now() / 1_000) + doorbellPushExpirationSeconds);
});

test('notification service sends washer and dryer completion pushes through the laundry preference', async () => {
  const deviceRegistry = createInMemoryDeviceRegistry();
  const notificationPreferenceStore = createInMemoryNotificationPreferenceStore(deviceRegistry);
  const pushSender = new FakePushSender();
  const notificationService = createNotificationService({
    deviceRegistry,
    notificationPreferenceStore,
    pushSender,
  });

  await deviceRegistry.registerDevice({
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
  });

  for (const event of [
    {
      type: 'washer_cycle_finished' as const,
      entityId: 'sensor.washer_job_state',
      title: 'Washer cycle complete',
      message: 'The washer cycle has finished.',
    },
    {
      type: 'dryer_cycle_finished' as const,
      entityId: 'sensor.dryer_job_state',
      title: 'Dryer cycle complete',
      message: 'The dryer cycle has finished.',
    },
  ]) {
    const push = await notificationService.sendEventPush({
      ...event,
      category: 'laundry',
      severity: 'normal',
      source: 'home_assistant',
    });

    assert.equal(push.attempted, true);
    assert.equal(push.sentNotificationCount, 1);
  }

  assert.deepEqual(
    pushSender.requests.map(({ title, body, data }) => ({ title, body, data })),
    [
      {
        title: 'Washer cycle complete',
        body: 'The washer cycle has finished.',
        data: { category: 'laundry' },
      },
      {
        title: 'Dryer cycle complete',
        body: 'The dryer cycle has finished.',
        data: { category: 'laundry' },
      },
    ],
  );
});

test('notification service sends refrigerator and freezer door reminders through their preferences', async () => {
  const deviceRegistry = createInMemoryDeviceRegistry();
  const notificationPreferenceStore = createInMemoryNotificationPreferenceStore(deviceRegistry);
  const pushSender = new FakePushSender();
  const notificationService = createNotificationService({
    deviceRegistry,
    notificationPreferenceStore,
    pushSender,
  });

  await deviceRegistry.registerDevice({
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
  });

  for (const event of [
    {
      type: 'freezer_door_left_open_5_min' as const,
      category: 'freezer' as const,
      entityId: 'binary_sensor.refrigerator_freezer_door',
      title: 'Freezer door left open',
      message: 'The freezer door has been open for 5 minutes.',
    },
    {
      type: 'refrigerator_door_left_open_5_min' as const,
      category: 'refrigerator' as const,
      entityId: 'binary_sensor.refrigerator_fridge_door',
      title: 'Refrigerator door left open',
      message: 'The refrigerator door has been open for 5 minutes.',
    },
  ]) {
    const push = await notificationService.sendEventPush({
      ...event,
      severity: 'normal',
      source: 'home_assistant',
    });

    assert.equal(push.attempted, true);
    assert.equal(push.sentNotificationCount, 1);
  }

  assert.deepEqual(
    pushSender.requests.map(({ title, body, data }) => ({ title, body, data })),
    [
      {
        title: 'Freezer door left open',
        body: 'The freezer door has been open for 5 minutes.',
        data: { category: 'freezer' },
      },
      {
        title: 'Refrigerator door left open',
        body: 'The refrigerator door has been open for 5 minutes.',
        data: { category: 'refrigerator' },
      },
    ],
  );
});

test('notification service removes an invalid device token after a doorbell push', async () => {
  const deviceRegistry = createInMemoryDeviceRegistry();
  const notificationPreferenceStore = createInMemoryNotificationPreferenceStore(deviceRegistry);
  const pushSender = new FakePushSender([{
    success: false,
    reason: 'Unregistered',
    isInvalidToken: true,
  }]);
  const notificationService = createNotificationService({
    deviceRegistry,
    notificationPreferenceStore,
    pushSender,
  });

  await deviceRegistry.registerDevice({
    token: 'stale-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
  });

  const push = await notificationService.sendEventPush({
    type: 'doorbell_person_detected',
    entityId: 'binary_sensor.doorbell_person_detected',
    category: 'doorbell',
    severity: 'high',
    source: 'home_assistant',
  });

  assert.equal(push.invalidTokenCount, 1);
  assert.equal((await deviceRegistry.listDevices()).length, 0);
});

test('notification service sends partner presence pushes only to the metadata recipient', async () => {
  const deviceRegistry = createInMemoryDeviceRegistry();
  const notificationPreferenceStore = createInMemoryNotificationPreferenceStore(deviceRegistry);
  const pushSender = new FakePushSender();
  const notificationService = createNotificationService({
    deviceRegistry,
    notificationPreferenceStore,
    pushSender,
  });

  await deviceRegistry.registerDevice({
    token: 'josh-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
    deviceName: 'Josh',
  });
  await deviceRegistry.registerDevice({
    token: 'mallory-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
    deviceName: 'Mallory',
  });

  const push = await notificationService.sendEventPush({
    type: 'partner_left_home',
    entityId: 'device_tracker.josh_iphone',
    category: 'presence',
    severity: 'normal',
    source: 'home_assistant',
    title: 'Josh left home',
    message: "Josh left. But don't worry. He loves you too much to be gone for long",
    metadata: {
      actor: 'Josh',
      recipient: 'Mallory',
    },
  });

  assert.equal(push.attempted, true);
  assert.equal(push.sentNotificationCount, 1);
  assert.equal(pushSender.requests.length, 1);
  assert.equal(pushSender.requests[0].device.token, 'mallory-apns-token');
  assert.equal(pushSender.requests[0].title, 'Josh left home');
  assert.equal(pushSender.requests[0].body, "Josh left. But don't worry. He loves you too much to be gone for long");
});

test('notification service sends list mutation pushes only to the other resident', async () => {
  const deviceRegistry = createInMemoryDeviceRegistry();
  const notificationPreferenceStore = createInMemoryNotificationPreferenceStore(deviceRegistry);
  const pushSender = new FakePushSender();
  const notificationService = createNotificationService({
    deviceRegistry,
    notificationPreferenceStore,
    pushSender,
  });

  await deviceRegistry.registerDevice({
    token: 'josh-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
    deviceName: 'Josh',
  });
  await deviceRegistry.registerDevice({
    token: 'mallory-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
    deviceName: 'Mallory',
  });

  const push = await notificationService.sendListMutationPush({
    listType: 'shopping',
    action: 'created',
    itemName: 'Whole milk',
    actor: 'Josh',
  });

  assert.equal(push.attempted, true);
  assert.equal(push.sentNotificationCount, 1);
  assert.equal(pushSender.requests.length, 1);
  assert.equal(pushSender.requests[0].device.token, 'mallory-apns-token');
  assert.equal(pushSender.requests[0].title, 'Shopping list updated');
  assert.equal(pushSender.requests[0].body, 'Josh added Whole milk.');
  assert.deepEqual(pushSender.requests[0].data, {
    category: 'shopping_list',
    listType: 'shopping',
    action: 'created',
    actor: 'Josh',
    itemName: 'Whole milk',
  });
});

test('notification service sends To Do add session summaries only to the other resident', async () => {
  const deviceRegistry = createInMemoryDeviceRegistry();
  const notificationPreferenceStore = createInMemoryNotificationPreferenceStore(deviceRegistry);
  const pushSender = new FakePushSender();
  const notificationService = createNotificationService({
    deviceRegistry,
    notificationPreferenceStore,
    pushSender,
  });

  await deviceRegistry.registerDevice({
    token: 'josh-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
    deviceName: 'Josh',
  });
  await deviceRegistry.registerDevice({
    token: 'mallory-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
    deviceName: 'Mallory',
  });

  const push = await notificationService.sendListSessionPush({
    listType: 'todo',
    actor: 'Josh',
    items: [
      { itemName: 'Schedule dentist', action: 'created' },
      { itemName: 'Book summer camp', action: 'created' },
    ],
  });

  assert.equal(push.attempted, true);
  assert.equal(push.sentNotificationCount, 1);
  assert.equal(pushSender.requests.length, 1);
  assert.equal(pushSender.requests[0].device.token, 'mallory-apns-token');
  assert.equal(pushSender.requests[0].title, 'To-do list updated');
  assert.equal(pushSender.requests[0].body, 'Josh added 2 to-do items: Schedule dentist and Book summer camp.');
  assert.deepEqual(pushSender.requests[0].data, {
    category: 'todo_list',
    listType: 'todo',
    action: 'created',
    actor: 'Josh',
    itemCount: '2',
  });
});

test('notification service sends due reminders only to the visible To Do recipient', async () => {
  const deviceRegistry = createInMemoryDeviceRegistry();
  const notificationPreferenceStore = createInMemoryNotificationPreferenceStore(deviceRegistry);
  const pushSender = new FakePushSender();
  const notificationService = createNotificationService({
    deviceRegistry,
    notificationPreferenceStore,
    pushSender,
  });

  await deviceRegistry.registerDevice({
    token: 'josh-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
    deviceName: 'Josh iPhone',
  });
  await deviceRegistry.registerDevice({
    token: 'mallory-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
    deviceName: 'Mallory iPhone',
  });

  const push = await notificationService.sendToDoDueReminderPush({
    itemId: 42,
    itemName: 'Schedule dentist',
    dueDate: '2026-01-15',
    reminderKind: 'morning',
    recipientUserId: 1,
  });

  assert.equal(push.attempted, true);
  assert.equal(push.sentNotificationCount, 1);
  assert.equal(pushSender.requests.length, 1);
  assert.equal(pushSender.requests[0].device.token, 'josh-apns-token');
  assert.equal(pushSender.requests[0].title, 'To-do due today');
  assert.equal(pushSender.requests[0].body, 'Schedule dentist is due today.');
  assert.equal(pushSender.requests[0].collapseId, 'todo-due-42-morning');
  assert.deepEqual(pushSender.requests[0].data, {
    category: 'todo_list',
    listType: 'todo',
    action: 'due_reminder',
    reminder: 'morning',
    todoItemId: '42',
    dueDate: '2026-01-15',
  });
});

test('notification service skips recipient-targeted partner presence pushes without a matching device', async () => {
  const deviceRegistry = createInMemoryDeviceRegistry();
  const notificationPreferenceStore = createInMemoryNotificationPreferenceStore(deviceRegistry);
  const pushSender = new FakePushSender();
  const notificationService = createNotificationService({
    deviceRegistry,
    notificationPreferenceStore,
    pushSender,
  });

  await deviceRegistry.registerDevice({
    token: 'josh-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
    deviceName: 'Josh',
  });

  const push = await notificationService.sendEventPush({
    type: 'partner_left_home',
    entityId: 'device_tracker.josh_iphone',
    category: 'presence',
    severity: 'normal',
    source: 'home_assistant',
    title: 'Josh left home',
    message: "Josh left. But don't worry. He loves you too much to be gone for long",
    metadata: {
      actor: 'Josh',
      recipient: 'Mallory',
    },
  });

  assert.equal(push.attempted, false);
  assert.equal(push.skipped, true);
  assert.equal(push.reason, 'No registered APNs devices match recipient "Mallory".');
  assert.equal(pushSender.requests.length, 0);
});

test('notification service sends lighting automation pushes through lighting preference', async () => {
  const deviceRegistry = createInMemoryDeviceRegistry();
  const notificationPreferenceStore = createInMemoryNotificationPreferenceStore(deviceRegistry);
  const pushSender = new FakePushSender();
  const notificationService = createNotificationService({
    deviceRegistry,
    notificationPreferenceStore,
    pushSender,
  });

  await deviceRegistry.registerDevice({
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
  });

  const push = await notificationService.sendEventPush({
    type: 'study_lights_on',
    entityId: 'automation.study_on_bright',
    category: 'lighting',
    severity: 'normal',
    source: 'home_assistant',
    message: 'Study: Let there be light!',
  });

  assert.equal(push.attempted, true);
  assert.equal(push.sentNotificationCount, 1);
  assert.equal(pushSender.requests.length, 1);
  assert.equal(pushSender.requests[0].title, 'Study lights on');
  assert.equal(pushSender.requests[0].body, 'Study: Let there be light!');
  assert.deepEqual(pushSender.requests[0].data, { category: 'lighting_automation' });
});

test('notification service sends weather alerts to all registered devices through weather preference', async () => {
  const deviceRegistry = createInMemoryDeviceRegistry();
  const notificationPreferenceStore = createInMemoryNotificationPreferenceStore(deviceRegistry);
  const pushSender = new FakePushSender();
  const notificationService = createNotificationService({
    deviceRegistry,
    notificationPreferenceStore,
    pushSender,
  });

  await deviceRegistry.registerDevice({
    token: 'josh-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
    deviceName: 'Josh',
  });
  await deviceRegistry.registerDevice({
    token: 'mallory-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
    deviceName: 'Mallory',
  });

  const push = await notificationService.sendWeatherAlertPush({
    title: 'Weather alert',
    body: 'High chance of thunderstorms in one hour, around 4 PM until 7 PM.',
    kind: 'thunderstorms',
    startsAt: '2026-07-01T22:00:00.000Z',
    endsAt: '2026-07-02T01:00:00.000Z',
    chance: 0.74,
  });

  assert.equal(push.attempted, true);
  assert.equal(push.sentNotificationCount, 2);
  assert.equal(pushSender.requests.length, 2);
  assert.deepEqual(pushSender.requests.map((request) => request.device.token), [
    'josh-apns-token',
    'mallory-apns-token',
  ]);
  assert.deepEqual(pushSender.requests[0].data, {
    category: 'weather_alerts',
    weatherKind: 'thunderstorms',
    startsAt: '2026-07-01T22:00:00.000Z',
    endsAt: '2026-07-02T01:00:00.000Z',
    chance: '0.74',
  });
});

test('notification service honors per-device weather alert preferences', async () => {
  const deviceRegistry = createInMemoryDeviceRegistry();
  const notificationPreferenceStore = createInMemoryNotificationPreferenceStore(deviceRegistry);
  const pushSender = new FakePushSender();
  const notificationService = createNotificationService({
    deviceRegistry,
    notificationPreferenceStore,
    pushSender,
  });

  await deviceRegistry.registerDevice({
    token: 'josh-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
    deviceName: 'Josh',
  });
  await deviceRegistry.registerDevice({
    token: 'mallory-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
    deviceName: 'Mallory',
  });
  await notificationPreferenceStore.updatePreferences({
    locator: {
      token: 'mallory-apns-token',
      provider: 'apns',
      environment: 'sandbox',
    },
    preferences: [{ category: 'weather_alerts', isEnabled: false }],
  });

  const push = await notificationService.sendWeatherAlertPush({
    title: 'Weather alert',
    body: 'Slight chance of light rain in one hour, around 9 AM until 11 AM.',
    kind: 'light rain',
    startsAt: '2026-07-01T15:00:00.000Z',
    endsAt: '2026-07-01T17:00:00.000Z',
    chance: 0.25,
  });

  assert.equal(push.attempted, true);
  assert.equal(push.sentNotificationCount, 1);
  assert.equal(pushSender.requests.length, 1);
  assert.equal(pushSender.requests[0].device.token, 'josh-apns-token');
});
