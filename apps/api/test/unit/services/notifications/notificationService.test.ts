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

  deviceRegistry.registerDevice({
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
  });
  notificationPreferenceStore.updatePreferences({
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
