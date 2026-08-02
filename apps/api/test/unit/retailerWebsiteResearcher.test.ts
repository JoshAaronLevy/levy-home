import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { ShoppingStockPriceCheckItemSnapshot } from '../../src/contracts.js';
import {
  normalizeRenderedAvailability,
  RETAILER_WEBSITE_RESEARCH_SEQUENCE,
  RetailerWebsiteResearchValidationError,
  validateRetailerWebsiteResearchResult,
} from '../../src/services/shopping/retailerWebsiteResearcher.js';
import { retailerWebsiteResearchFixtures } from '../support/retailerWebsiteResearchFixtures.js';

const fixtureItem: ShoppingStockPriceCheckItemSnapshot = {
  itemId: 101,
  itemVersion: 3,
  name: 'Fixture item',
  quantity: 1,
  categoryId: null,
  storeListings: [],
};

test('research contract normalizes all Stage 1 rendered-page fixtures without network access', () => {
  for (const fixture of retailerWebsiteResearchFixtures) {
    const result = validateRetailerWebsiteResearchResult({
      item: fixtureItem,
      storeKey: fixture.storeKey,
    }, fixture.evidence);

    assert.equal(result.availability, fixture.outcome, fixture.name);
    assert.equal(result.matchStatus, fixture.matchStatus, fixture.name);
    assert.equal(Boolean(result.price), fixture.hasPrice, fixture.name);
    assert.equal(Boolean(result.aisle), fixture.hasAisle, fixture.name);

    if (fixture.matchStatus === 'matched') {
      assert.equal(result.store.confirmed, true, fixture.name);
      assert.ok(result.product, fixture.name);
      assert.ok(result.store.pageURL, fixture.name);
    }
  }
});

test('research results always derive the exact fixed store identity and sanitize page URLs', () => {
  const result = validateRetailerWebsiteResearchResult({
    item: fixtureItem,
    storeKey: 'target_highlands_ranch',
  }, {
    outcome: 'matched',
    navigation: {
      url: 'https://www.target.com/p/fixture?searchTerm=milk&session=not-persisted#details',
      method: 'GET',
    },
    renderedStoreText: 'Target 1365 Sgt Jon Stiles Dr Highlands Ranch CO',
    renderedAvailabilityText: 'In stock',
    product: { name: 'Fixture milk' },
  });

  assert.deepEqual(result.store, {
    storeId: 1,
    storeName: 'Target',
    source: 'target.com',
    selectedStoreAddress: '1365 Sgt Jon Stiles Dr, Highlands Ranch, CO',
    pageURL: 'https://www.target.com/p/fixture',
    confirmed: true,
  });
});

test('research contract rejects direct-endpoint-shaped, disallowed-host, and disallowed-method navigation', () => {
  const cases = [
    { url: 'https://www.target.com/api/products/fixture', method: 'GET' },
    { url: 'https://www.target.com/graphql', method: 'GET' },
    { url: 'https://www.kingsoopers.com/search', method: 'POST' },
    { url: 'https://third-party.example/product', method: 'GET' },
  ];

  for (const navigation of cases) {
    const result = validateRetailerWebsiteResearchResult({
      item: fixtureItem,
      storeKey: 'target_highlands_ranch',
    }, {
      outcome: 'matched',
      navigation,
      renderedStoreText: 'Target 1365 Sgt Jon Stiles Dr Highlands Ranch CO',
      renderedAvailabilityText: 'In stock',
      product: { name: 'Fixture item' },
    });

    assert.deepEqual(
      { availability: result.availability, matchStatus: result.matchStatus, failureCode: result.failureCode },
      { availability: 'unknown', matchStatus: 'domain_scope_failure', failureCode: 'site_scope_unavailable' },
    );
  }
});

test('research contract does not infer unconfirmed, malformed, or non-visible facts', () => {
  const unconfirmed = validateRetailerWebsiteResearchResult({
    item: fixtureItem,
    storeKey: 'king_soopers_wildcat_reserve',
  }, {
    outcome: 'matched',
    navigation: { url: 'https://www.kingsoopers.com/search', method: 'GET' },
    renderedStoreText: 'King Soopers another location',
    renderedAvailabilityText: 'In stock',
    product: { name: 'Fixture item' },
    price: { regular: 3.99 },
  });
  assert.deepEqual(
    { availability: unconfirmed.availability, matchStatus: unconfirmed.matchStatus, product: unconfirmed.product },
    { availability: 'unknown', matchStatus: 'store_unconfirmed', product: undefined },
  );

  assert.throws(
    () => validateRetailerWebsiteResearchResult({
      item: fixtureItem,
      storeKey: 'target_highlands_ranch',
    }, {
      outcome: 'matched',
      navigation: { url: 'https://target.com/p/fixture', method: 'GET' },
      renderedStoreText: '1365 Sgt Jon Stiles Dr Highlands Ranch CO',
      product: { name: 'Fixture item' },
      price: { regular: -1 },
    }),
    RetailerWebsiteResearchValidationError,
  );
  assert.throws(
    () => validateRetailerWebsiteResearchResult({
      item: fixtureItem,
      storeKey: 'target_highlands_ranch',
    }, {
      outcome: 'no_match',
      navigation: { url: 'https://target.com/s', method: 'GET' },
      renderedStoreText: '1365 Sgt Jon Stiles Dr Highlands Ranch CO',
      product: { name: 'Unexpected product' },
    }),
    RetailerWebsiteResearchValidationError,
  );
});

test('availability normalization recognizes only explicit inventory wording', () => {
  assert.equal(normalizeRenderedAvailability('Out of stock'), 'out_of_stock');
  assert.equal(normalizeRenderedAvailability('Only 2 left'), 'low_stock');
  assert.equal(normalizeRenderedAvailability('Available for pickup'), 'in_stock');
  assert.equal(normalizeRenderedAvailability('Contact the store'), 'unknown');
  assert.equal(normalizeRenderedAvailability(undefined), 'unknown');
  assert.deepEqual(RETAILER_WEBSITE_RESEARCH_SEQUENCE.length, 5);
});
