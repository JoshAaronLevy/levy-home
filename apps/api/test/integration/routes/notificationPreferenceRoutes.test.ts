import assert from 'node:assert/strict';
import { afterEach, beforeEach, test } from 'node:test';

import { createApp } from '../../../src/app.js';
import {
  createInMemoryNotificationPreferenceRepository,
  type NotificationPreferenceRepository,
} from '../../../src/repositories/notificationPreferenceRepository.js';
import {
  createInMemoryPushDeviceRepository,
  type PushDeviceRepository,
} from '../../../src/repositories/pushDeviceRepository.js';
import { createInMemoryDeviceRegistry } from '../../../src/services/notifications/deviceRegistry.js';
import { createInMemoryNotificationPreferenceStore } from '../../../src/services/notifications/notificationPreferenceStore.js';
import { FakePushSender } from '../../support/fakePushSender.js';
import { createRouteTestHarness } from '../../support/routeTestHarness.js';
import { testConfig } from '../../support/testConfig.js';

const routes = createRouteTestHarness();

beforeEach(async () => {
  await routes.start(createApp({ config: testConfig }));
});

afterEach(async () => {
  await routes.close();
});

test('notification preferences can be synced and fetched by device token or device ID', async () => {
  const registered = await routes.postJSON('/api/devices/register', {
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
  });

  const tokenSync = await routes.putJSON('/api/notification-preferences', {
    deviceToken: 'sample-apns-token',
    provider: 'apns',
    environment: 'sandbox',
    preferences: [
      { category: 'garage_opened', isEnabled: false },
      { category: 'garage_left_open', isEnabled: false },
    ],
  });
  const tokenFetch = await routes.getJSON(
    '/api/notification-preferences?deviceToken=sample-apns-token&provider=apns&environment=sandbox',
  );

  assert.equal(tokenSync.ok, true);
  assert.equal(tokenFetch.preferences.length, 9);
  assert.equal(
    tokenFetch.preferences.find((preference: { category: string }) => preference.category === 'garage_opened')
      .isEnabled,
    false,
  );
  assert.equal(
    tokenFetch.preferences.find((preference: { category: string }) => preference.category === 'garage_closed')
      .isEnabled,
    true,
  );
  assert.equal(
    tokenFetch.preferences.find((preference: { category: string }) => preference.category === 'partner_presence')
      .isEnabled,
    true,
  );
  assert.equal(
    tokenFetch.preferences.find((preference: { category: string }) => preference.category === 'lighting_automation')
      .isEnabled,
    true,
  );

  const deviceSync = await routes.putJSON('/api/notification-preferences', {
    deviceId: registered.device.id,
    preferences: [{ category: 'garage_closed', isEnabled: false }],
  });
  const deviceFetch = await routes.getJSON(`/api/notification-preferences?deviceId=${registered.device.id}`);

  assert.equal(deviceSync.ok, true);
  assert.equal(
    deviceFetch.preferences.find((preference: { category: string }) => preference.category === 'garage_closed')
      .isEnabled,
    false,
  );
});

test('device registrations and notification preferences survive app instances backed by shared repositories', async () => {
  const pushDeviceRepository = createInMemoryPushDeviceRepository();
  const notificationPreferenceRepository = createInMemoryNotificationPreferenceRepository();
  const pushSender = new FakePushSender();

  await routes.restart(createNotificationPersistenceApp({
    notificationPreferenceRepository,
    pushDeviceRepository,
    pushSender,
  }));

  const registered = await routes.postJSON('/api/devices/register', {
    token: 'sample-apns-token',
    platform: 'ios',
    provider: 'apns',
    environment: 'sandbox',
  });

  await routes.putJSON('/api/notification-preferences', {
    deviceId: registered.device.id,
    preferences: [{ category: 'garage_opened', isEnabled: false }],
  });

  await routes.restart(createNotificationPersistenceApp({
    notificationPreferenceRepository,
    pushDeviceRepository,
    pushSender,
  }));

  const fetchedPreferences = await routes.getJSON(
    `/api/notification-preferences?deviceId=${registered.device.id}`,
  );
  const testPush = await routes.postJSON('/api/debug/send-test-push', {
    title: 'Persistence test',
    body: 'This should use the persisted device.',
  });

  assert.equal(
    fetchedPreferences.preferences.find((preference: { category: string }) => preference.category === 'garage_opened')
      .isEnabled,
    false,
  );
  assert.equal(testPush.registeredDeviceCount, 1);
  assert.equal(testPush.sentNotificationCount, 1);
  assert.equal(pushSender.requests.length, 1);
  assert.equal(pushSender.requests[0].device.id, registered.device.id);
});

function createNotificationPersistenceApp(options: {
  notificationPreferenceRepository: NotificationPreferenceRepository;
  pushDeviceRepository: PushDeviceRepository;
  pushSender: FakePushSender;
}) {
  const deviceRegistry = createInMemoryDeviceRegistry(options.pushDeviceRepository);
  const notificationPreferenceStore = createInMemoryNotificationPreferenceStore(
    deviceRegistry,
    options.notificationPreferenceRepository,
  );

  return createApp({
    config: testConfig,
    deviceRegistry,
    notificationPreferenceStore,
    pushSender: options.pushSender,
  });
}
