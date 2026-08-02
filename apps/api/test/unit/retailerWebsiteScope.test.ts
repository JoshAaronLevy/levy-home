import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  RETAILER_WEBSITE_SCOPE,
  hasConfirmedRetailerWebsiteStoreAddress,
  isAllowedRetailerWebsiteNavigation,
  retailerWebsiteStoreForAppStoreId,
  retailerWebsiteStoreForKey,
} from '../../src/services/shopping/retailerWebsiteScope.js';
import { retailerWebsiteResearchFixtures } from '../support/retailerWebsiteResearchFixtures.js';

test('retailer website scope is fixed to the two requested stores and four hosts', () => {
  assert.deepEqual(RETAILER_WEBSITE_SCOPE.allowedHosts, [
    'target.com',
    'www.target.com',
    'kingsoopers.com',
    'www.kingsoopers.com',
  ]);
  assert.deepEqual(RETAILER_WEBSITE_SCOPE.allowedMethods, ['GET', 'HEAD', 'OPTIONS']);
  assert.deepEqual(RETAILER_WEBSITE_SCOPE.policy, {
    maxItemsPerJob: 100,
    maxBrowserNavigationsPerStore: 12,
    jobTimeoutMs: 120_000,
    retryPolicy: 'no_automatic_retailer_retry',
    displayPrecedence: 'freshest_confirmed_website_listing_then_manual_fallback',
    publicStatuses: [
      'queued',
      'running',
      'completed',
      'completed_with_issues',
      'failed',
      'ai_unavailable',
      'site_scope_unavailable',
      'store_not_confirmed',
      'website_unavailable',
      'invalid_agent_result',
    ],
  });
  assert.deepEqual(RETAILER_WEBSITE_SCOPE.stores.map((store) => ({
    key: store.key,
    appStoreId: store.appStoreId,
    address: store.address,
  })), [
    {
      key: 'target_highlands_ranch',
      appStoreId: 1,
      address: '1365 Sgt Jon Stiles Dr, Highlands Ranch, CO',
    },
    {
      key: 'king_soopers_wildcat_reserve',
      appStoreId: 2,
      address: '2205 W Wildcat Reserve Pkwy, Highlands Ranch, CO',
    },
  ]);
});

test('retailer website scope allows only approved HTTPS hosts and read methods', () => {
  assert.equal(isAllowedRetailerWebsiteNavigation('https://target.com/', 'GET'), true);
  assert.equal(isAllowedRetailerWebsiteNavigation('https://www.target.com/', 'HEAD'), true);
  assert.equal(isAllowedRetailerWebsiteNavigation('https://kingsoopers.com/', 'OPTIONS'), true);
  assert.equal(isAllowedRetailerWebsiteNavigation('https://www.kingsoopers.com/', 'get'), true);

  assert.equal(isAllowedRetailerWebsiteNavigation('http://target.com/', 'GET'), false);
  assert.equal(isAllowedRetailerWebsiteNavigation('https://api.target.com/', 'GET'), false);
  assert.equal(isAllowedRetailerWebsiteNavigation('https://target.com.evil.example/', 'GET'), false);
  assert.equal(isAllowedRetailerWebsiteNavigation('https://target.com:444/', 'GET'), false);
  assert.equal(isAllowedRetailerWebsiteNavigation('https://user:pass@target.com/', 'GET'), false);
  assert.equal(isAllowedRetailerWebsiteNavigation('https://www.kingsoopers.com/', 'POST'), false);
});

test('store confirmation requires the exact requested address', () => {
  const target = retailerWebsiteStoreForKey('target_highlands_ranch');
  const kingSoopers = retailerWebsiteStoreForKey('king_soopers_wildcat_reserve');

  assert.equal(
    hasConfirmedRetailerWebsiteStoreAddress('Target, 1365 Sgt. Jon Stiles Dr., Highlands Ranch, CO 80129', target),
    true,
  );
  assert.equal(
    hasConfirmedRetailerWebsiteStoreAddress('King Soopers, 2205 W Wildcat Reserve Pkwy, Highlands Ranch, CO 80129', kingSoopers),
    true,
  );
  assert.equal(hasConfirmedRetailerWebsiteStoreAddress('Target another Highlands Ranch store', target), false);
  assert.equal(retailerWebsiteStoreForAppStoreId(1), target);
  assert.equal(retailerWebsiteStoreForAppStoreId(2), kingSoopers);
  assert.equal(retailerWebsiteStoreForAppStoreId(99), undefined);
});

test('Stage 1 fixtures cover every required website-research outcome', () => {
  const fixtureNames = new Set(retailerWebsiteResearchFixtures.map((fixture) => fixture.name));

  assert.equal(retailerWebsiteResearchFixtures.length, 10);
  assert.equal(fixtureNames.size, retailerWebsiteResearchFixtures.length);
  assert.deepEqual(
    new Set(retailerWebsiteResearchFixtures.map((fixture) => fixture.matchStatus)),
    new Set(['matched', 'no_match', 'ambiguous', 'store_unconfirmed', 'website_error', 'domain_scope_failure']),
  );
  assert.equal(retailerWebsiteResearchFixtures.some((fixture) => fixture.outcome === 'in_stock'), true);
  assert.equal(retailerWebsiteResearchFixtures.some((fixture) => fixture.outcome === 'low_stock'), true);
  assert.equal(retailerWebsiteResearchFixtures.some((fixture) => fixture.outcome === 'out_of_stock'), true);
  assert.equal(retailerWebsiteResearchFixtures.some((fixture) => !fixture.hasPrice), true);
  assert.equal(retailerWebsiteResearchFixtures.some((fixture) => !fixture.hasAisle), true);
});
