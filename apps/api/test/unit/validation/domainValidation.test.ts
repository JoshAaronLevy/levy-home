import assert from 'node:assert/strict';
import { test } from 'node:test';

import { validateHomeAssistantEventPayload } from '../../../src/validation/activityValidation.js';
import { validateRegisterDeviceBody } from '../../../src/validation/deviceValidation.js';
import { validateQuickActionBody } from '../../../src/validation/homeValidation.js';
import {
  validateNotificationPreferencesBody,
  validateNotificationPreferencesQuery,
  validateTestPushBody,
} from '../../../src/validation/notificationValidation.js';
import {
  validateCreateShoppingListItemBody,
  validateUpdateShoppingListItemBody,
} from '../../../src/validation/shoppingValidation.js';
import { validateCreateToDoLocationBody } from '../../../src/validation/todoValidation.js';
import { HTTPError } from '../../../src/http/errors.js';

test('shopping validators normalize create payloads and reject empty updates', () => {
  const request = validateCreateShoppingListItemBody({
    name: ' Whole milk ',
    brand: ' Horizon ',
    quantity: 2,
    notes: ' ',
    purchased: true,
    categoryId: 3,
    image: null,
    storeListings: [
      {
        storeId: 1,
        storeName: ' Target ',
        source: ' ',
        krogerLocationId: ' 62000123 ',
      },
    ],
    mutationId: ' mutation-1 ',
  });

  assert.deepEqual(request, {
    name: 'Whole milk',
    brand: 'Horizon',
    quantity: 2,
    notes: null,
    purchased: true,
    categoryId: 3,
    image: null,
    storeListings: [
      {
        storeId: 1,
        storeName: 'Target',
        krogerLocationId: '62000123',
      },
    ],
    mutationId: 'mutation-1',
  });

  assertHTTPError(
    () => validateUpdateShoppingListItemBody({ mutationId: 'only-metadata' }),
    'invalid_shopping_item',
  );
});

test('to-do location validator trims names and preserves favorited user id arrays', () => {
  const request = validateCreateToDoLocationBody({
    name: ' Denver Pediatrics ',
    address: null,
    latitude: 39.7392,
    longitude: -104.9903,
    createdBy: 1,
    favoritedBy: [2, 1, 2],
  });

  assert.deepEqual(request, {
    name: 'Denver Pediatrics',
    address: null,
    latitude: 39.7392,
    longitude: -104.9903,
    createdBy: 1,
    favoritedBy: [2, 1],
  });

  assertHTTPError(
    () => validateCreateToDoLocationBody({ name: 'School', favoritedBy: [1, 0] }),
    'invalid_todo_location',
  );
});

test('device registration validator supports APNs and legacy Expo payloads', () => {
  assert.deepEqual(
    validateRegisterDeviceBody({
      token: ' apns-token ',
      provider: 'apns',
      environment: 'sandbox',
      appVersion: '1.0',
      deviceName: ' Josh iPhone ',
    }),
    {
      token: 'apns-token',
      platform: 'ios',
      provider: 'apns',
      environment: 'sandbox',
      appVersion: '1.0',
      deviceName: 'Josh iPhone',
    },
  );

  assert.deepEqual(validateRegisterDeviceBody({ pushToken: 'expo-token' }), {
    token: 'expo-token',
    platform: 'unknown',
    provider: 'expo',
  });

  assertHTTPError(
    () => validateRegisterDeviceBody({ token: 'apns-token', provider: 'apns' }),
    'missing_apns_environment',
  );
});

test('notification validators parse preference updates, queries, and test pushes', () => {
  assert.deepEqual(
    validateNotificationPreferencesBody({
      deviceId: ' device-1 ',
      preferences: [
        { category: 'garage_opened', isEnabled: false },
        { category: 'partner_presence', isEnabled: true },
        { category: 'lighting_automation', isEnabled: true },
      ],
    }),
    {
      locator: { deviceId: 'device-1' },
      preferences: [
        { category: 'garage_opened', isEnabled: false },
        { category: 'partner_presence', isEnabled: true },
        { category: 'lighting_automation', isEnabled: true },
      ],
    },
  );
  assert.deepEqual(
    validateNotificationPreferencesQuery({
      deviceToken: ' apns-token ',
      provider: 'apns',
      environment: 'production',
    }),
    {
      token: 'apns-token',
      provider: 'apns',
      environment: 'production',
    },
  );
  assert.deepEqual(validateTestPushBody(undefined), {
    title: 'Levy Home test',
    body: 'This is a test notification from Levy Home.',
  });
  assert.deepEqual(
    validateNotificationPreferencesBody({
      token: 'apns-token',
      provider: 'apns',
      environment: 'sandbox',
      preferences: [{ category: 'doorbell', isEnabled: true }],
    }),
    {
      locator: { token: 'apns-token', provider: 'apns', environment: 'sandbox' },
      preferences: [{ category: 'doorbell', isEnabled: true }],
    },
  );
});

test('quick action validator accepts curated actions and rejects arbitrary Home Assistant payloads', () => {
  assert.deepEqual(
    validateQuickActionBody({
      actionId: 'turn_on_light_group',
      groupId: ' upstairs ',
    }),
    {
      actionId: 'turn_on_light_group',
      groupId: 'upstairs',
    },
  );

  assertHTTPError(
    () => validateQuickActionBody({ actionId: 'open_garage', entity_id: 'cover.garage' }),
    'arbitrary_home_assistant_payload_rejected',
  );
});

test('Home Assistant event validator returns validation results without throwing', () => {
  assert.deepEqual(validateHomeAssistantEventPayload({
    type: 'study_lights_on',
    entityId: ' automation.study_on_bright ',
    category: 'lighting',
    severity: 'normal',
    occurredAt: '2026-06-30T12:00:00Z',
    metadata: { automation: 'Study On Bright' },
  }), {
    ok: true,
    value: {
      type: 'study_lights_on',
      entityId: 'automation.study_on_bright',
      category: 'lighting',
      severity: 'normal',
      occurredAt: '2026-06-30T12:00:00Z',
      metadata: { automation: 'Study On Bright' },
    },
  });

  assert.deepEqual(validateHomeAssistantEventPayload({
    type: 'phone_state_changed',
    entityId: 'device_tracker.josh_iphone',
    metadata: [],
  }), {
    ok: false,
    error: 'metadata must be a JSON object when provided.',
  });
});

function assertHTTPError(action: () => unknown, expectedCode: string): void {
  let caughtError: unknown;

  try {
    action();
  } catch (error) {
    caughtError = error;
  }

  assert(caughtError instanceof HTTPError);
  assert.equal(caughtError.code, expectedCode);
}
