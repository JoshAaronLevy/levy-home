import assert from 'node:assert/strict';
import { test } from 'node:test';

import { redactLogValue, safeErrorMessage } from '../../../src/observability/logger.js';

test('redactLogValue redacts authorization headers and secret-like fields', () => {
  assert.equal(
    redactLogValue('Authorization: Bearer live-home-assistant-token'),
    'Authorization: Bearer [redacted]',
  );
  assert.equal(
    redactLogValue('Authorization: Basic abc123'),
    'Authorization: Basic [redacted]',
  );
  assert.equal(
    redactLogValue({
      token: 'sample-apns-token',
      nested: {
        APNS_PRIVATE_KEY: 'private-key-material',
        entityId: 'device_tracker.josh_iphone',
      },
    }),
    '{"token":"[redacted]","nested":{"APNS_PRIVATE_KEY":"[redacted]","entityId":"device_tracker.josh_iphone"}}',
  );
});

test('safeErrorMessage redacts secrets from Error messages', () => {
  assert.equal(
    safeErrorMessage(new Error('Home Assistant rejected Bearer test-home-assistant-token')),
    'Home Assistant rejected Bearer [redacted]',
  );
});
