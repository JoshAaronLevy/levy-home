import assert from 'node:assert/strict';
import { test } from 'node:test';

import { createInMemoryDeviceRegistry } from '../../../../src/services/notifications/deviceRegistry.js';
import { createInMemoryNotificationPreferenceStore } from '../../../../src/services/notifications/notificationPreferenceStore.js';
import { createNotificationService } from '../../../../src/services/notifications/notificationService.js';
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
