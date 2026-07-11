import assert from 'node:assert/strict';
import { test } from 'node:test';

import { readConfig } from '../../../../src/config.js';
import { krogerProductSearchURL } from '../../../../src/integrations/kroger/productClient.js';

test('Kroger product searches request up to 50 products by default', () => {
  const config = readConfig({
    KROGER_API_BASE_URL: 'https://api.kroger.test/v1',
    KROGER_LOCATION_ID: '62000008',
  });

  const url = krogerProductSearchURL(config, 'Soy Milk');

  assert.equal(url.searchParams.get('filter.term'), 'Soy Milk');
  assert.equal(url.searchParams.get('filter.limit'), '50');
  assert.equal(url.searchParams.get('filter.locationId'), '62000008');
});
